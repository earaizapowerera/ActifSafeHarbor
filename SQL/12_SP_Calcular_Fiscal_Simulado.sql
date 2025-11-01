-- =============================================
-- Stored Procedure: sp_Calcular_Fiscal_Simulado
-- Descripción: Calcula depreciación fiscal simulada para activos que solo tienen USGAAP
--              Aplica a activos con FLG_NOCAPITALIZABLE_3='S' y FLG_NOCAPITALIZABLE_2<>'S'
--              Usa COSTO_REEXPRESADO convertido a pesos con TC del 30 junio
--              Calcula acumulado hasta diciembre del año anterior
-- Versión: 1.0.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_Fiscal_Simulado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_Fiscal_Simulado;
GO

CREATE PROCEDURE dbo.sp_Calcular_Fiscal_Simulado
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER,
    @ConnectionString_Actif NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '1.0.0';
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

    PRINT '==========================================';
    PRINT 'CÁLCULO FISCAL SIMULADO (SOLO USGAAP)';
    PRINT '==========================================';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR);
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR);
    PRINT 'Tipo Cambio 30-Jun: ' + CAST(@Tipo_Cambio_30_Junio AS VARCHAR);
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50));
    PRINT '';

    -- Variables para procesamiento fila por fila
    DECLARE @ID_Staging BIGINT;
    DECLARE @ID_NUM_ACTIVO INT;
    DECLARE @COSTO_REEXPRESADO DECIMAL(18,4);
    DECLARE @ID_MONEDA INT;
    DECLARE @Nombre_Moneda NVARCHAR(50);
    DECLARE @FECHA_INIC_DEPREC_3 DATETIME;
    DECLARE @ID_TIPO_ACTIVO INT;
    DECLARE @ID_SUBTIPO_ACTIVO INT;

    -- Variables de cálculo
    DECLARE @Costo_Fiscal_Simulado_MXN DECIMAL(18,4);
    DECLARE @Tasa_Anual_Fiscal DECIMAL(10,6);
    DECLARE @Tasa_Mensual_Fiscal DECIMAL(10,6);
    DECLARE @Fecha_Corte_Calculo DATE;
    DECLARE @Meses_Depreciados INT;
    DECLARE @Dep_Mensual_Simulada DECIMAL(18,4);
    DECLARE @Dep_Acum_Simulada DECIMAL(18,4);
    DECLARE @Observaciones NVARCHAR(500);

    -- Fecha de corte: 31 de diciembre del año anterior
    SET @Fecha_Corte_Calculo = CAST(CAST((@Año_Calculo - 1) AS VARCHAR) + '-12-31' AS DATE);

    PRINT 'Fecha de corte para acumulado: ' + CAST(@Fecha_Corte_Calculo AS VARCHAR);
    PRINT '';

    -- Cursor para activos que solo tienen USGAAP (no tienen fiscal)
    DECLARE cur_activos_usgaap CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            s.ID_Staging,
            s.ID_NUM_ACTIVO,
            s.COSTO_REEXPRESADO,
            s.ID_MONEDA,
            s.Nombre_Moneda,
            s.FECHA_INIC_DEPREC_3,
            s.ID_TIPO_ACTIVO,
            s.ID_SUBTIPO_ACTIVO
        FROM dbo.Staging_Activo s
        WHERE s.ID_Compania = @ID_Compania
          AND s.Año_Calculo = @Año_Calculo
          AND s.Lote_Importacion = @Lote_Importacion
          AND s.FLG_NOCAPITALIZABLE_3 = 'S'  -- Tiene USGAAP
          AND ISNULL(s.FLG_NOCAPITALIZABLE_2, 'N') <> 'S'  -- NO tiene fiscal
          AND s.COSTO_REEXPRESADO IS NOT NULL
          AND s.COSTO_REEXPRESADO > 0
          AND s.FECHA_INIC_DEPREC_3 IS NOT NULL
        ORDER BY s.ID_NUM_ACTIVO;

    OPEN cur_activos_usgaap;

    FETCH NEXT FROM cur_activos_usgaap INTO
        @ID_Staging, @ID_NUM_ACTIVO, @COSTO_REEXPRESADO, @ID_MONEDA, @Nombre_Moneda,
        @FECHA_INIC_DEPREC_3, @ID_TIPO_ACTIVO, @ID_SUBTIPO_ACTIVO;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Inicializar
        SET @Observaciones = '';
        SET @Tasa_Anual_Fiscal = NULL;

        -- =============================================
        -- 1. CONVERTIR COSTO USGAAP A PESOS
        -- =============================================
        SET @Costo_Fiscal_Simulado_MXN = @COSTO_REEXPRESADO * @Tipo_Cambio_30_Junio;

        -- =============================================
        -- 2. OBTENER PORCENTAJE FISCAL DE CATÁLOGO
        -- =============================================
        -- Buscar en la base de datos origen (Actif) el porcentaje fiscal
        DECLARE @SQL_Porcentaje NVARCHAR(MAX);

        SET @SQL_Porcentaje = N'
        SELECT @Tasa_OUT = pd.PORC_SEGUNDO_ANO
        FROM OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString_Actif + ''',
            ''SELECT ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO, PORC_SEGUNDO_ANO
              FROM porcentaje_depreciacion
              WHERE ID_TIPO_DEP = 2''
        ) AS pd
        WHERE pd.ID_TIPO_ACTIVO = @ID_TIPO_ACTIVO_IN
          AND pd.ID_SUBTIPO_ACTIVO = @ID_SUBTIPO_ACTIVO_IN';

        BEGIN TRY
            EXEC sp_executesql @SQL_Porcentaje,
                N'@Tasa_OUT DECIMAL(10,6) OUTPUT, @ID_TIPO_ACTIVO_IN INT, @ID_SUBTIPO_ACTIVO_IN INT',
                @Tasa_OUT = @Tasa_Anual_Fiscal OUTPUT,
                @ID_TIPO_ACTIVO_IN = @ID_TIPO_ACTIVO,
                @ID_SUBTIPO_ACTIVO_IN = @ID_SUBTIPO_ACTIVO;
        END TRY
        BEGIN CATCH
            SET @Observaciones = 'ERROR: No se pudo obtener porcentaje fiscal. ' + ERROR_MESSAGE();
            PRINT 'Activo ' + CAST(@ID_NUM_ACTIVO AS VARCHAR) + ': ' + @Observaciones;
        END CATCH

        IF @Tasa_Anual_Fiscal IS NULL OR @Tasa_Anual_Fiscal = 0
        BEGIN
            SET @Observaciones = 'ADVERTENCIA: No se encontró porcentaje fiscal para Tipo=' +
                CAST(@ID_TIPO_ACTIVO AS VARCHAR) + ', Subtipo=' + CAST(@ID_SUBTIPO_ACTIVO AS VARCHAR);
            SET @Tasa_Anual_Fiscal = 0;
            SET @Tasa_Mensual_Fiscal = 0;
            SET @Dep_Mensual_Simulada = 0;
            SET @Meses_Depreciados = 0;
            SET @Dep_Acum_Simulada = 0;

            PRINT 'Activo ' + CAST(@ID_NUM_ACTIVO AS VARCHAR) + ': ' + @Observaciones;
        END
        ELSE
        BEGIN
            -- =============================================
            -- 3. CALCULAR MESES DEPRECIADOS
            -- =============================================
            SET @Tasa_Mensual_Fiscal = @Tasa_Anual_Fiscal / 12.0;

            -- Calcular meses desde inicio de depreciación hasta dic del año anterior
            IF @FECHA_INIC_DEPREC_3 > @Fecha_Corte_Calculo
            BEGIN
                -- Activo que inicia depreciación después del corte
                SET @Meses_Depreciados = 0;
                SET @Observaciones = 'Activo inicia depreciación después del ' +
                    CAST(@Fecha_Corte_Calculo AS VARCHAR) + '. No hay depreciación acumulada.';
            END
            ELSE
            BEGIN
                SET @Meses_Depreciados = DATEDIFF(MONTH, @FECHA_INIC_DEPREC_3, @Fecha_Corte_Calculo) + 1;

                IF @Meses_Depreciados < 0
                    SET @Meses_Depreciados = 0;
            END

            -- =============================================
            -- 4. CALCULAR DEPRECIACIÓN SIMULADA
            -- =============================================
            SET @Dep_Mensual_Simulada = @Costo_Fiscal_Simulado_MXN * (@Tasa_Mensual_Fiscal / 100.0);
            SET @Dep_Acum_Simulada = @Dep_Mensual_Simulada * @Meses_Depreciados;

            -- Validar que no supere el 100%
            IF @Dep_Acum_Simulada > @Costo_Fiscal_Simulado_MXN
            BEGIN
                SET @Dep_Acum_Simulada = @Costo_Fiscal_Simulado_MXN;
                SET @Observaciones = @Observaciones + ' Depreciación limitada al 100% del costo.';
            END

            SET @Observaciones = @Observaciones +
                ' Tasa: ' + CAST(@Tasa_Anual_Fiscal AS VARCHAR) + '% anual. ' +
                'Meses: ' + CAST(@Meses_Depreciados AS VARCHAR) + '.';
        END

        -- =============================================
        -- 5. GUARDAR RESULTADO
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
        VALUES (
            @ID_Staging, @ID_Compania, @ID_NUM_ACTIVO, @Año_Calculo,
            @COSTO_REEXPRESADO, @ID_MONEDA, @Nombre_Moneda,
            @Tipo_Cambio_30_Junio, @Costo_Fiscal_Simulado_MXN,
            @FECHA_INIC_DEPREC_3,
            @ID_TIPO_ACTIVO, @ID_SUBTIPO_ACTIVO, 2, -- ID_TIPO_DEP = 2 (Fiscal)
            @Tasa_Anual_Fiscal, @Tasa_Mensual_Fiscal,
            @Fecha_Corte_Calculo, @Meses_Depreciados,
            @Dep_Mensual_Simulada, @Dep_Acum_Simulada,
            @Observaciones, @Lote_Calculo, @Version_SP
        );

        SET @Registros_Procesados = @Registros_Procesados + 1;

        IF @Registros_Procesados % 10 = 0
            PRINT 'Procesados: ' + CAST(@Registros_Procesados AS VARCHAR) + ' activos...';

        FETCH NEXT FROM cur_activos_usgaap INTO
            @ID_Staging, @ID_NUM_ACTIVO, @COSTO_REEXPRESADO, @ID_MONEDA, @Nombre_Moneda,
            @FECHA_INIC_DEPREC_3, @ID_TIPO_ACTIVO, @ID_SUBTIPO_ACTIVO;
    END

    CLOSE cur_activos_usgaap;
    DEALLOCATE cur_activos_usgaap;

    PRINT '';
    PRINT 'Total activos con fiscal simulado: ' + CAST(@Registros_Procesados AS VARCHAR);
    PRINT '';

    -- =============================================
    -- 6. RETORNAR RESUMEN
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

PRINT 'Stored Procedure sp_Calcular_Fiscal_Simulado creado (Version 1.0.0)';
GO
