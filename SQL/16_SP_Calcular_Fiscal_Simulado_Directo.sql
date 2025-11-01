-- =============================================
-- Stored Procedure: sp_Calcular_Fiscal_Simulado_Directo
-- Descripción: Versión simplificada que usa cross-database queries directas
--              (sin OPENROWSET, para SQL Server Linux)
-- Versión: 1.1.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_Fiscal_Simulado_Directo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_Fiscal_Simulado_Directo;
GO

CREATE PROCEDURE dbo.sp_Calcular_Fiscal_Simulado_Directo
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '1.1.0';
    DECLARE @Registros_Procesados INT = 0;

    -- Obtener tipo de cambio del 30 de junio del año de cálculo
    DECLARE @Tipo_Cambio_30_Junio DECIMAL(10,6);

    SELECT @Tipo_Cambio_30_Junio = Tipo_Cambio
    FROM dbo.Tipo_Cambio
    WHERE Año = @Año_Calculo
      AND MONTH(Fecha) = 6
      AND DAY(Fecha) = 30
      AND ID_Moneda = 2; -- USD

    IF @Tipo_Cambio_30_Junio IS NULL
    BEGIN
        RAISERROR('No se encontró tipo de cambio para el 30 de junio de %d', 16, 1, @Año_Calculo);
        RETURN;
    END

    PRINT '=========================================='
    PRINT 'CÁLCULO FISCAL SIMULADO DIRECTO'
    PRINT '=========================================='
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR)
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR)
    PRINT 'Tipo Cambio 30-Jun: ' + CAST(@Tipo_Cambio_30_Junio AS VARCHAR)
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50))
    PRINT ''

    -- Fecha de corte: 31 de diciembre del año anterior
    DECLARE @Fecha_Corte_Calculo DATE = CAST(CAST((@Año_Calculo - 1) AS VARCHAR) + '-12-31' AS DATE);

    PRINT 'Fecha de corte para acumulado: ' + CAST(@Fecha_Corte_Calculo AS VARCHAR)
    PRINT ''

    -- =============================================
    -- INSERTAR CÁLCULOS USANDO CROSS-DATABASE QUERY
    -- =============================================

    INSERT INTO dbo.Calculo_Fiscal_Simulado (
        ID_Staging, ID_Compania, ID_NUM_ACTIVO, Año_Calculo,
        COSTO_REEXPRESADO, ID_MONEDA, Nombre_Moneda,
        Tipo_Cambio_30_Junio, Costo_Fiscal_Simulado_MXN,
        FECHA_INIC_DEPREC_3,
        ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO, ID_TIPO_DEP,
        Tasa_Anual_Fiscal, Tasa_Mensual_Fiscal,
        Fecha_Corte_Calculo, Meses_Depreciados,
        Dep_Mensual_Simulada, Dep_Acum_Año_Anterior_Simulada,
        Observaciones, Lote_Calculo, Version_SP
    )
    SELECT
        s.ID_Staging,
        s.ID_Compania,
        s.ID_NUM_ACTIVO,
        s.Año_Calculo,

        -- Datos base
        s.COSTO_REEXPRESADO,
        s.ID_MONEDA,
        s.Nombre_Moneda,

        -- Conversión a pesos
        @Tipo_Cambio_30_Junio AS Tipo_Cambio_30_Junio,
        s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio AS Costo_Fiscal_Simulado_MXN,

        -- Fechas
        s.FECHA_INIC_DEPREC_3,

        -- Tipo de activo
        s.ID_TIPO_ACTIVO,
        s.ID_SUBTIPO_ACTIVO,
        2 AS ID_TIPO_DEP, -- Fiscal

        -- Tasa fiscal
        ISNULL(pd.PORC_SEGUNDO_ANO, 0) AS Tasa_Anual_Fiscal,
        ISNULL(pd.PORC_SEGUNDO_ANO, 0) / 12.0 AS Tasa_Mensual_Fiscal,

        -- Cálculo de meses
        @Fecha_Corte_Calculo AS Fecha_Corte_Calculo,
        CASE
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo THEN 0
            ELSE DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1
        END AS Meses_Depreciados,

        -- Depreciación calculada
        (s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio) * (ISNULL(pd.PORC_SEGUNDO_ANO, 0) / 12.0 / 100.0) AS Dep_Mensual_Simulada,

        CASE
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo THEN 0
            WHEN ISNULL(pd.PORC_SEGUNDO_ANO, 0) = 0 THEN 0
            ELSE
                CASE
                    WHEN ((s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio) * (ISNULL(pd.PORC_SEGUNDO_ANO, 0) / 12.0 / 100.0) *
                         (DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1)) > (s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio)
                    THEN (s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio)
                    ELSE ((s.COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio) * (ISNULL(pd.PORC_SEGUNDO_ANO, 0) / 12.0 / 100.0) *
                         (DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1))
                END
        END AS Dep_Acum_Año_Anterior_Simulada,

        -- Observaciones
        CASE
            WHEN pd.PORC_SEGUNDO_ANO IS NULL OR pd.PORC_SEGUNDO_ANO = 0
                THEN 'ADVERTENCIA: No se encontró porcentaje fiscal para Tipo=' + CAST(s.ID_TIPO_ACTIVO AS VARCHAR) +
                     ', Subtipo=' + CAST(s.ID_SUBTIPO_ACTIVO AS VARCHAR)
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo
                THEN 'Activo inicia depreciación después del ' + CAST(@Fecha_Corte_Calculo AS VARCHAR) + '. No hay depreciación acumulada.'
            ELSE 'Tasa: ' + CAST(pd.PORC_SEGUNDO_ANO AS VARCHAR) + '% anual. Meses: ' +
                 CAST(DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1 AS VARCHAR) + '.'
        END AS Observaciones,

        @Lote_Calculo AS Lote_Calculo,
        @Version_SP AS Version_SP

    FROM dbo.Staging_Activo s

    -- Join con porcentaje_depreciacion FISCAL usando cross-database
    LEFT JOIN actif_web_cima_dev.dbo.porcentaje_depreciacion pd
        ON s.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
        AND s.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
        AND pd.ID_TIPO_DEP = 2

    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.Lote_Importacion = @Lote_Importacion
      AND s.FLG_NOCAPITALIZABLE_3 = 'S'  -- Tiene USGAAP
      AND ISNULL(s.FLG_NOCAPITALIZABLE_2, 'N') <> 'S'  -- NO tiene fiscal
      AND s.COSTO_REEXPRESADO IS NOT NULL
      AND s.COSTO_REEXPRESADO > 0
      AND s.FECHA_INIC_DEPREC_3 IS NOT NULL;

    SET @Registros_Procesados = @@ROWCOUNT;

    PRINT ''
    PRINT 'Total activos con fiscal simulado: ' + CAST(@Registros_Procesados AS VARCHAR)
    PRINT ''

    -- =============================================
    -- RETORNAR RESUMEN
    -- =============================================
    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        'Fiscal Simulado' AS Tipo_Calculo,
        @Registros_Procesados AS Registros_Calculados,
        @Lote_Calculo AS Lote_Calculo,
        SUM(Dep_Acum_Año_Anterior_Simulada) AS Total_Dep_Acum_Simulada,
        AVG(Tasa_Anual_Fiscal) AS Tasa_Promedio,
        MIN(Meses_Depreciados) AS Min_Meses_Depreciados,
        MAX(Meses_Depreciados) AS Max_Meses_Depreciados,
        COUNT(CASE WHEN Tasa_Anual_Fiscal = 0 THEN 1 END) AS Activos_Sin_Tasa
    FROM dbo.Calculo_Fiscal_Simulado
    WHERE Lote_Calculo = @Lote_Calculo;

END
GO

PRINT 'Stored Procedure sp_Calcular_Fiscal_Simulado_Directo creado (Version 1.1.0)';
GO
