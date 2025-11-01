-- =============================================
-- Stored Procedure: sp_Calcular_Fiscal_Simulado_V2
-- Descripción: Calcula depreciación fiscal simulada para activos que solo tienen USGAAP
--              Usa campos renombrados: ManejaFiscal, ManejaUSGAAP, CostoUSD, CostoMXN
--              Sin cross-database queries - asume datos ya en Staging
-- Versión: 2.0.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_Fiscal_Simulado_V2', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_Fiscal_Simulado_V2;
GO

CREATE PROCEDURE dbo.sp_Calcular_Fiscal_Simulado_V2
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '2.0.0';
    DECLARE @Registros_Procesados INT = 0;
    DECLARE @Fecha_Corte_Calculo DATE;

    -- Fecha de corte: 31 de diciembre del año anterior
    SET @Fecha_Corte_Calculo = CAST(CAST((@Año_Calculo - 1) AS VARCHAR) + '-12-31' AS DATE);

    PRINT '=========================================='
    PRINT 'CÁLCULO FISCAL SIMULADO V2'
    PRINT '=========================================='
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR)
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR)
    PRINT 'Fecha corte: ' + CAST(@Fecha_Corte_Calculo AS VARCHAR)
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50))
    PRINT ''

    -- =============================================
    -- CALCULAR FISCAL SIMULADO
    -- =============================================
    -- Solo para activos con ManejaUSGAAP='S' y ManejaFiscal<>'S'
    -- Usa CostoMXN que ya viene calculado desde el ETL

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

        -- Datos base (CostoUSD = COSTO_REEXPRESADO del ETL)
        s.CostoUSD AS COSTO_REEXPRESADO,
        s.ID_MONEDA,
        s.Nombre_Moneda,

        -- Tipo de cambio (implícito en el cálculo: CostoMXN / CostoUSD)
        CASE WHEN s.CostoUSD > 0 THEN s.CostoMXN / s.CostoUSD ELSE 0 END AS Tipo_Cambio_30_Junio,

        -- Costo fiscal simulado en MXN (ya viene calculado del ETL)
        s.CostoMXN AS Costo_Fiscal_Simulado_MXN,

        -- Fechas
        s.FECHA_INIC_DEPREC_3,

        -- Tipo de activo
        s.ID_TIPO_ACTIVO,
        s.ID_SUBTIPO_ACTIVO,
        2 AS ID_TIPO_DEP, -- Fiscal

        -- Tasa fiscal (ya viene del ETL)
        ISNULL(s.Tasa_Anual, 0) AS Tasa_Anual_Fiscal,
        ISNULL(s.Tasa_Mensual, 0) AS Tasa_Mensual_Fiscal,

        -- Cálculo de meses
        @Fecha_Corte_Calculo AS Fecha_Corte_Calculo,
        CASE
            WHEN s.FECHA_INIC_DEPREC_3 IS NULL THEN 0
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo THEN 0
            ELSE DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1
        END AS Meses_Depreciados,

        -- Depreciación calculada
        s.CostoMXN * (ISNULL(s.Tasa_Mensual, 0) / 100.0) AS Dep_Mensual_Simulada,

        CASE
            WHEN s.FECHA_INIC_DEPREC_3 IS NULL THEN 0
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo THEN 0
            WHEN ISNULL(s.Tasa_Anual, 0) = 0 THEN 0
            ELSE
                CASE
                    WHEN ((s.CostoMXN * (ISNULL(s.Tasa_Mensual, 0) / 100.0) *
                         (DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1))) > s.CostoMXN
                    THEN s.CostoMXN
                    ELSE (s.CostoMXN * (ISNULL(s.Tasa_Mensual, 0) / 100.0) *
                         (DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1))
                END
        END AS Dep_Acum_Año_Anterior_Simulada,

        -- Observaciones
        CASE
            WHEN s.Tasa_Anual IS NULL OR s.Tasa_Anual = 0
                THEN 'Sin porcentaje fiscal para Tipo=' + CAST(s.ID_TIPO_ACTIVO AS VARCHAR) +
                     ', Subtipo=' + CAST(s.ID_SUBTIPO_ACTIVO AS VARCHAR)
            WHEN s.FECHA_INIC_DEPREC_3 IS NULL
                THEN 'Sin fecha inicio depreciación USGAAP'
            WHEN s.FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo
                THEN 'Inicia depreciación después del ' + CAST(@Fecha_Corte_Calculo AS VARCHAR)
            ELSE 'Tasa: ' + CAST(s.Tasa_Anual AS VARCHAR) + '% anual, Meses: ' +
                 CAST(DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1 AS VARCHAR)
        END AS Observaciones,

        @Lote_Calculo AS Lote_Calculo,
        @Version_SP AS Version_SP

    FROM dbo.Staging_Activo s

    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.Lote_Importacion = @Lote_Importacion
      AND s.ManejaUSGAAP = 'S'  -- Tiene USGAAP
      AND ISNULL(s.ManejaFiscal, 'N') <> 'S'  -- NO tiene fiscal
      AND s.CostoUSD IS NOT NULL
      AND s.CostoUSD > 0
      AND s.CostoMXN IS NOT NULL
      AND s.CostoMXN > 0;

    SET @Registros_Procesados = @@ROWCOUNT;

    PRINT ''
    PRINT 'Activos con fiscal simulado: ' + CAST(@Registros_Procesados AS VARCHAR)
    PRINT ''

    -- =============================================
    -- RETORNAR RESUMEN
    -- =============================================
    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        'Fiscal Simulado V2' AS Tipo_Calculo,
        @Registros_Procesados AS Registros_Calculados,
        @Lote_Calculo AS Lote_Calculo,
        SUM(Dep_Acum_Año_Anterior_Simulada) AS Total_Dep_Acum_Simulada,
        AVG(Tasa_Anual_Fiscal) AS Tasa_Promedio,
        MIN(Meses_Depreciados) AS Min_Meses_Depreciados,
        MAX(Meses_Depreciados) AS Max_Meses_Depreciados,
        COUNT(CASE WHEN Tasa_Anual_Fiscal = 0 THEN 1 END) AS Activos_Sin_Tasa
    FROM dbo.Calculo_Fiscal_Simulado
    WHERE Lote_Calculo = @Lote_Calculo;

    PRINT '=========================================='
    PRINT 'CÁLCULO COMPLETADO'
    PRINT '=========================================='

END
GO

PRINT 'Stored Procedure sp_Calcular_Fiscal_Simulado_V2 creado (Version 2.0.0)';
GO
