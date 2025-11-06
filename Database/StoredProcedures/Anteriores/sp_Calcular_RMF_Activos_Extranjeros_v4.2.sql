-- =============================================
-- DROP y RE-CREATE del Stored Procedure v4.2
-- CAMBIOS v4.2:
-- - CORRECCIÓN CRÍTICA: Adquirido antes de junio usa (13-MES)/2 NO DATEDIFF
-- - La lógica es: mitad del período desde adquisición hasta diciembre
-- - Ejemplo: Marzo → (13-3)/2 = 5 meses (mitad de Mar-Dic)
-- =============================================

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Extranjeros', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Año_Anterior INT = @Año_Calculo - 1;
    DECLARE @Fecha_30_Junio DATE = CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-06-30' AS DATE);
    DECLARE @TipoCambio_30Jun DECIMAL(18,6);
    DECLARE @RegistrosProcesados INT = 0;
    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();

    PRINT '========================================';
    PRINT 'Iniciando cálculo RMF Activos Extranjeros v4.2';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT 'Lote Importación: ' + CAST(@Lote_Importacion AS VARCHAR(50));
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50));
    PRINT '========================================';

    -- 1. Obtener tipo de cambio del 30 de junio
    SELECT TOP 1 @TipoCambio_30Jun = Tipo_Cambio
    FROM Tipo_Cambio
    WHERE Año = @Año_Calculo
      AND MONTH(Fecha) = 6
      AND DAY(Fecha) = 30
    ORDER BY Fecha DESC;

    IF @TipoCambio_30Jun IS NULL
    BEGIN
        PRINT 'ERROR: No se encontró tipo de cambio para el 30 de junio de ' + CAST(@Año_Calculo AS VARCHAR(10));
        RETURN -1;
    END

    PRINT 'Tipo de cambio 30-Jun-' + CAST(@Año_Calculo AS VARCHAR(10)) + ': ' + CAST(@TipoCambio_30Jun AS VARCHAR(20));

    -- Crear tabla temporal
    CREATE TABLE #ActivosCalculo (
        ID_Staging BIGINT,
        ID_NUM_ACTIVO INT,
        ID_ACTIVO NVARCHAR(50),
        DESCRIPCION NVARCHAR(500),
        FLG_PROPIO BIT,
        MOI DECIMAL(18,4),
        Tasa_Mensual DECIMAL(18,6),
        FECHA_COMPRA DATE,
        FECHA_BAJA DATE,
        ID_PAIS INT,
        Dep_Acum_Inicio DECIMAL(18,4),
        Meses_Uso_Inicio_Ejercicio INT,
        Meses_Hasta_Mitad_Periodo INT,
        Meses_Uso_Ejercicio INT,
        Saldo_Inicio_Año DECIMAL(18,4),
        Dep_Ejercicio DECIMAL(18,4),
        Monto_Pendiente DECIMAL(18,4),
        Proporcion DECIMAL(18,4),
        Prueba_10Pct DECIMAL(18,4),
        Valor_USD DECIMAL(18,4),
        Valor_MXN DECIMAL(18,4),
        Aplica_Regla_10Pct BIT,
        Ruta_Calculo NVARCHAR(20),
        Descripcion_Ruta NVARCHAR(200)
    );

    -- 2. Insertar TODOS los activos extranjeros (propios Y no propios)
    INSERT INTO #ActivosCalculo (
        ID_Staging, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
        FLG_PROPIO, MOI, Tasa_Mensual,
        FECHA_COMPRA, FECHA_BAJA, ID_PAIS,
        Dep_Acum_Inicio
    )
    SELECT
        s.ID_Staging,
        s.ID_NUM_ACTIVO,
        s.ID_ACTIVO,
        s.DESCRIPCION,
        s.FLG_PROPIO,
        s.COSTO_REVALUADO AS MOI,
        s.Tasa_Mensual,
        s.FECHA_COMPRA,
        s.FECHA_BAJA,
        s.ID_PAIS,
        ISNULL(s.Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio
    FROM Staging_Activo s
    WHERE s.ID_Compania = @ID_Compania
      AND s.Lote_Importacion = @Lote_Importacion
      AND s.ID_PAIS > 1  -- Solo extranjeros
      AND s.COSTO_REVALUADO IS NOT NULL
      AND s.COSTO_REVALUADO > 0;

    SET @RegistrosProcesados = @@ROWCOUNT;
    PRINT 'Activos extranjeros encontrados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));

    IF @RegistrosProcesados = 0
    BEGIN
        PRINT 'No hay activos extranjeros para calcular';
        RETURN 0;
    END

    -- 3. Calcular meses de uso al inicio del ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Inicio_Ejercicio =
        CASE
            WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 0
            ELSE DATEDIFF(MONTH, FECHA_COMPRA, CAST(CAST(@Año_Anterior AS VARCHAR(4)) + '-12-31' AS DATE)) + 1
        END;

    -- 4. Calcular meses hasta la mitad del periodo (CORREGIDO v4.2)
    UPDATE #ActivosCalculo
    SET Meses_Hasta_Mitad_Periodo =
        CASE
            -- Caso: Activo dado de baja en el año
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA) / 2

            -- Caso: Activo existente desde antes del año (usa enero a junio = 6 meses)
            WHEN FECHA_COMPRA < CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 6

            -- Caso: Activo adquirido en el año (ANTES o DESPUÉS de junio)
            -- Usa mitad del período desde adquisición hasta diciembre: (13 - MES) / 2
            -- Ejemplo: Marzo → (13-3)/2 = 5, Julio → (13-7)/2 = 3
            ELSE (13 - MONTH(FECHA_COMPRA)) / 2
        END;

    -- 5. Calcular meses de uso en el ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Ejercicio =
        CASE
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA)
            WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 13 - MONTH(FECHA_COMPRA)
            ELSE 12
        END;

    -- =============================================
    -- CÁLCULO DIFERENCIADO SEGÚN FLG_PROPIO
    -- =============================================

    -- 6. PROPIOS: Calcular Saldo por Deducir ISR al Inicio del Año
    UPDATE #ActivosCalculo
    SET Saldo_Inicio_Año =
        CASE
            WHEN FLG_PROPIO = 1 THEN MOI - Dep_Acum_Inicio
            ELSE 0  -- NO PROPIOS no usan este campo
        END;

    -- 7. PROPIOS: Calcular Depreciación Fiscal del Ejercicio
    UPDATE #ActivosCalculo
    SET Dep_Ejercicio =
        CASE
            WHEN FLG_PROPIO = 1 THEN MOI * Tasa_Mensual * Meses_Hasta_Mitad_Periodo
            ELSE 0  -- NO PROPIOS no deprecian
        END;

    -- 8. PROPIOS: Calcular Monto Pendiente por Deducir
    UPDATE #ActivosCalculo
    SET Monto_Pendiente =
        CASE
            WHEN FLG_PROPIO = 1 THEN
                CASE
                    WHEN (Saldo_Inicio_Año - Dep_Ejercicio) < 0 THEN 0
                    ELSE (Saldo_Inicio_Año - Dep_Ejercicio)
                END
            ELSE 0  -- NO PROPIOS no usan este campo
        END;

    -- 9. PROPIOS: Calcular Proporción del Monto Pendiente
    UPDATE #ActivosCalculo
    SET Proporcion =
        CASE
            WHEN FLG_PROPIO = 1 THEN (Monto_Pendiente / 12.0) * Meses_Uso_Ejercicio
            ELSE 0  -- NO PROPIOS no usan este campo
        END;

    -- 10. APLICAR REGLA SEGÚN TIPO DE ACTIVO
    UPDATE #ActivosCalculo
    SET Prueba_10Pct = MOI * 0.10,
        Valor_USD =
            CASE
                -- NO PROPIOS: Safe Harbor 10% MOI directo
                WHEN FLG_PROPIO = 0 THEN MOI * 0.10
                -- PROPIOS: Aplicar regla del mayor (proporción vs 10% MOI)
                WHEN Proporcion > (MOI * 0.10) THEN Proporcion
                ELSE MOI * 0.10
            END,
        Aplica_Regla_10Pct =
            CASE
                -- NO PROPIOS: Siempre aplican 10%
                WHEN FLG_PROPIO = 0 THEN 1
                -- PROPIOS: Solo si proporción <= 10%
                WHEN Proporcion <= (MOI * 0.10) THEN 1
                ELSE 0
            END;

    -- 11. Conversión a Pesos
    UPDATE #ActivosCalculo
    SET Valor_MXN = Valor_USD * @TipoCambio_30Jun;

    -- 12. Determinar ruta de cálculo
    UPDATE #ActivosCalculo
    SET Ruta_Calculo =
            CASE
                WHEN FLG_PROPIO = 0 THEN 'EXT-NO-PROPIO'
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'EXT-BAJA'
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'EXT-ANTES-JUN'
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'EXT-DESP-JUN'
                WHEN Aplica_Regla_10Pct = 1 THEN 'EXT-10PCT'
                ELSE 'EXT-NORMAL'
            END,
        Descripcion_Ruta =
            CASE
                WHEN FLG_PROPIO = 0 THEN 'Activo NO propio - Safe Harbor 10% MOI (Art 182 LISR)'
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'Activo dado de baja en ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'Activo adquirido antes de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'Activo adquirido después de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN Aplica_Regla_10Pct = 1 THEN 'Activo PROPIO - Aplicó regla 10% MOI (Art 182 LISR)'
                ELSE 'Activo PROPIO en uso normal en ' + CAST(@Año_Calculo AS VARCHAR(10))
            END;

    -- 13. Insertar resultados en Calculo_RMF
    INSERT INTO Calculo_RMF (
        ID_Staging,
        ID_Compania,
        ID_NUM_ACTIVO,
        Año_Calculo,
        Tipo_Activo,
        ID_PAIS,
        Ruta_Calculo,
        Descripcion_Ruta,
        MOI,
        Tasa_Mensual,
        Dep_Acum_Inicio,
        Meses_Uso_Inicio_Ejercicio,
        Meses_Uso_Hasta_Mitad_Periodo,
        Meses_Uso_En_Ejercicio,
        Saldo_Inicio_Año,
        Dep_Fiscal_Ejercicio,
        Monto_Pendiente,
        Proporcion,
        Prueba_10_Pct_MOI,
        Aplica_10_Pct,
        Tipo_Cambio_30_Junio,
        Valor_Reportable_MXN,
        Fecha_Calculo,
        Lote_Calculo,
        Version_SP
    )
    SELECT
        ID_Staging,
        @ID_Compania,
        ID_NUM_ACTIVO,
        @Año_Calculo,
        CASE WHEN FLG_PROPIO = 0 THEN 'Extranjero NO Propio' ELSE 'Extranjero Propio' END,
        ID_PAIS,
        Ruta_Calculo,
        Descripcion_Ruta,
        MOI,
        Tasa_Mensual,
        Dep_Acum_Inicio,
        Meses_Uso_Inicio_Ejercicio,
        Meses_Hasta_Mitad_Periodo,
        Meses_Uso_Ejercicio,
        Saldo_Inicio_Año,
        Dep_Ejercicio,
        Monto_Pendiente,
        Proporcion,
        Prueba_10Pct,
        Aplica_Regla_10Pct,
        @TipoCambio_30Jun,
        Valor_MXN,
        GETDATE(),
        @Lote_Calculo,
        'v4.2'
    FROM #ActivosCalculo
    WHERE Valor_MXN IS NOT NULL;

    SET @RegistrosProcesados = @@ROWCOUNT;

    -- 14. Mostrar resumen
    DECLARE @TotalValorReportable DECIMAL(18,2);
    DECLARE @ActivosRegla10Pct INT;
    DECLARE @ActivosNoPropios INT;
    DECLARE @ActivosPropios INT;

    SELECT
        @TotalValorReportable = SUM(Valor_MXN),
        @ActivosRegla10Pct = SUM(CAST(Aplica_Regla_10Pct AS INT)),
        @ActivosNoPropios = SUM(CASE WHEN FLG_PROPIO = 0 THEN 1 ELSE 0 END),
        @ActivosPropios = SUM(CASE WHEN FLG_PROPIO = 1 THEN 1 ELSE 0 END)
    FROM #ActivosCalculo;

    PRINT '';
    PRINT '========================================';
    PRINT 'RESUMEN DE CÁLCULO';
    PRINT '========================================';
    PRINT 'Registros procesados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));
    PRINT 'Activos NO propios: ' + CAST(@ActivosNoPropios AS VARCHAR(10));
    PRINT 'Activos PROPIOS: ' + CAST(@ActivosPropios AS VARCHAR(10));
    PRINT 'Total valor reportable (MXN): $' + FORMAT(@TotalValorReportable, 'N2');
    PRINT 'Activos con regla 10% MOI: ' + CAST(@ActivosRegla10Pct AS VARCHAR(10));
    PRINT '';

    -- Limpiar
    DROP TABLE #ActivosCalculo;

    PRINT 'Cálculo completado exitosamente';
    PRINT '========================================';

    RETURN 0;
END
GO

PRINT 'Stored procedure sp_Calcular_RMF_Activos_Extranjeros v4.2 creado exitosamente';
GO
