-- =============================================
-- SP Calcular RMF Activos NACIONALES (FIXED)
-- Solo parámetros: @ID_Compania, @Año_Calculo
-- Elimina cálculos previos antes de calcular
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Nacionales', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Nacionales;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Activos_Nacionales
    @ID_Compania INT,
    @Año_Calculo INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Año_Anterior INT = @Año_Calculo - 1;
    DECLARE @Fecha_30_Junio DATE = CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-06-30' AS DATE);
    DECLARE @RegistrosProcesados INT = 0;

    PRINT '========================================';
    PRINT 'Cálculo RMF Activos Nacionales';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT '========================================';

    -- 1. Eliminar cálculos previos de esta compañía/año
    DELETE FROM Calculo_RMF
    WHERE ID_Compania = @ID_Compania
      AND Año_Calculo = @Año_Calculo
      AND Tipo_Activo = 'Nacional';

    PRINT 'Cálculos previos eliminados: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- 2. Crear tabla temporal
    CREATE TABLE #ActivosCalculo (
        ID_Staging BIGINT,
        ID_NUM_ACTIVO INT,
        MOI DECIMAL(18,4),
        Tasa_Anual DECIMAL(10,6),
        Tasa_Mensual DECIMAL(18,6),
        Dep_Anual DECIMAL(18,4),
        FECHA_COMPRA DATE,
        FECHA_INICIO_DEP DATE,  -- FECHA_INIC_DEPREC para calcular meses de depreciación
        FECHA_BAJA DATE,
        ID_PAIS INT,
        Dep_Acum_Inicio DECIMAL(18,4),
        INPCCompra DECIMAL(18,6),
        INPCUtilizado DECIMAL(18,6),
        Meses_Uso_Inicio_Ejercicio INT,
        Meses_Uso_Hasta_Mitad_Periodo INT,
        Meses_Uso_Ejercicio INT,
        Saldo_Inicio_Año DECIMAL(18,4),
        Dep_Ejercicio DECIMAL(18,4),
        Monto_Pendiente DECIMAL(18,4),
        -- Campos de actualización por INPC
        Factor_Actualizacion_Saldo DECIMAL(18,10),
        Saldo_Actualizado DECIMAL(18,4),
        Factor_Actualizacion_Dep DECIMAL(18,10),
        Dep_Actualizada DECIMAL(18,4),
        Valor_Promedio DECIMAL(18,4),
        Proporcion DECIMAL(18,4),
        Prueba_10Pct DECIMAL(18,4),
        Valor_MXN DECIMAL(18,4),
        Aplica_Regla_10Pct BIT,
        Ruta_Calculo NVARCHAR(20),
        Descripcion_Ruta NVARCHAR(200)
    );

    -- 3. Insertar activos NACIONALES (Fiscal)
    -- Criterio: ManejaFiscal='S' AND CostoMXN > 0 AND Tasa_Anual > 0
    INSERT INTO #ActivosCalculo (
        ID_Staging, ID_NUM_ACTIVO, MOI, Tasa_Anual, Tasa_Mensual,
        FECHA_COMPRA, FECHA_INICIO_DEP, FECHA_BAJA, ID_PAIS, Dep_Acum_Inicio
    )
    SELECT
        s.ID_Staging,
        s.ID_NUM_ACTIVO,
        s.CostoMXN AS MOI,
        s.Tasa_Anual,
        s.Tasa_Mensual,
        s.FECHA_COMPRA,
        s.FECHA_INICIO_DEP,  -- Para calcular meses de depreciación
        s.FECHA_BAJA,
        s.ID_PAIS,
        ISNULL(s.Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio  -- Usar histórico, NUNCA calcular
    FROM Staging_Activo s
    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.ManejaFiscal = 'S'  -- NACIONALES: ManejaFiscal = 'S'
      AND s.CostoMXN IS NOT NULL
      AND s.CostoMXN > 0
      AND s.Tasa_Anual > 0;  -- EXCLUIR terrenos y activos sin depreciación (NO aplican Safe Harbor)

    SET @RegistrosProcesados = @@ROWCOUNT;
    PRINT 'Activos nacionales encontrados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));

    IF @RegistrosProcesados = 0
    BEGIN
        PRINT 'No hay activos nacionales para calcular';
        DROP TABLE #ActivosCalculo;
        RETURN 0;
    END

    -- 4. Calcular Depreciación Anual
    UPDATE #ActivosCalculo
    SET Dep_Anual = MOI * (Tasa_Anual / 100);

    -- 5. Calcular meses de uso al inicio del ejercicio
    -- USAR FECHA_INICIO_DEP para calcular meses de depreciación acumulada
    UPDATE #ActivosCalculo
    SET Meses_Uso_Inicio_Ejercicio =
        CASE
            WHEN FECHA_INICIO_DEP IS NULL OR FECHA_INICIO_DEP >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 0
            ELSE DATEDIFF(MONTH, FECHA_INICIO_DEP, CAST(CAST(@Año_Anterior AS VARCHAR(4)) + '-12-31' AS DATE)) + 1
        END;

    -- 6. Calcular meses hasta la mitad del periodo (para depreciación en el ejercicio)
    UPDATE #ActivosCalculo
    SET Meses_Uso_Hasta_Mitad_Periodo =
        CASE
            -- Caso: Activo dado de baja en el año
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA) / 2
            -- Caso: Activo existente desde antes del año (usa enero a junio = 6 meses)
            WHEN FECHA_COMPRA < CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 6
            -- Caso: Activo adquirido en el año
            ELSE (13 - MONTH(FECHA_COMPRA)) / 2
        END;

    -- 7. Calcular meses de uso en el ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Ejercicio =
        CASE
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA)
            WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 13 - MONTH(FECHA_COMPRA)
            ELSE 12
        END;

    PRINT 'Meses de uso en ejercicio calculados';

    -- 8. Calcular Saldo por Deducir ISR al Inicio del Año
    UPDATE #ActivosCalculo
    SET Saldo_Inicio_Año = MOI - Dep_Acum_Inicio;

    -- 8b. EXCLUIR activos totalmente depreciados (sin saldo por deducir)
    DELETE FROM #ActivosCalculo
    WHERE Saldo_Inicio_Año <= 0;

    PRINT 'Activos totalmente depreciados excluidos: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- 9. Calcular Depreciación Fiscal del Ejercicio
    -- IMPORTANTE: La depreciación no puede exceder el saldo disponible
    -- USAR Tasa_Anual/12/100 para mayor precisión (no Tasa_Mensual con 6 decimales)
    -- CORRECCIÓN: Usar Meses_Uso_Ejercicio (no Meses_Hasta_Mitad_Periodo)
    -- El 50% se aplica después en el cálculo del Valor_Promedio
    UPDATE #ActivosCalculo
    SET Dep_Ejercicio =
        CASE
            WHEN (MOI * (Tasa_Anual / 12 / 100) * Meses_Uso_Ejercicio) > Saldo_Inicio_Año
            THEN Saldo_Inicio_Año  -- Limitar a saldo disponible
            ELSE MOI * (Tasa_Anual / 12 / 100) * Meses_Uso_Ejercicio
        END;

    -- 10. Calcular Monto Pendiente por Deducir
    UPDATE #ActivosCalculo
    SET Monto_Pendiente =
        CASE
            WHEN (Saldo_Inicio_Año - Dep_Ejercicio) < 0 THEN 0
            ELSE (Saldo_Inicio_Año - Dep_Ejercicio)
        END;

    -- 11-16. Cálculos con INPC: Se harán DESPUÉS por sp_Actualizar_INPC_Nacionales
    -- Los INPC se obtendrán según lógica SAT y se guardarán en Calculo_RMF
    -- Por ahora, usar factor 1.0 (sin actualización) como placeholder

    UPDATE #ActivosCalculo
    SET Factor_Actualizacion_Saldo = 1.0,
        Saldo_Actualizado = Saldo_Inicio_Año,
        Factor_Actualizacion_Dep = 1.0,
        Dep_Actualizada = Dep_Ejercicio,
        Valor_Promedio = Saldo_Inicio_Año - (Dep_Ejercicio * 0.5),
        Proporcion = (Saldo_Inicio_Año - (Dep_Ejercicio * 0.5)) * (Meses_Uso_Ejercicio / 12.0);

    PRINT 'Proporción calculada (sin actualización INPC - se aplicará después)';

    -- 17. APLICAR REGLA DEL MAYOR (Proporción vs 10% MOI)
    UPDATE #ActivosCalculo
    SET Prueba_10Pct = MOI * 0.10,
        Valor_MXN =  -- Para nacionales, Valor_MXN es directamente el mayor
            CASE
                WHEN Proporcion > (MOI * 0.10) THEN Proporcion
                ELSE MOI * 0.10
            END,
        Aplica_Regla_10Pct =
            CASE
                WHEN Proporcion <= (MOI * 0.10) THEN 1
                ELSE 0
            END;

    -- 13. Determinar ruta de cálculo
    UPDATE #ActivosCalculo
    SET Ruta_Calculo =
            CASE
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'NAC-BAJA'
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'NAC-ANTES-JUN'
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'NAC-DESP-JUN'
                WHEN Aplica_Regla_10Pct = 1 THEN 'NAC-10PCT'
                ELSE 'NAC-NORMAL'
            END,
        Descripcion_Ruta =
            CASE
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'Activo dado de baja en ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'Activo adquirido antes de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'Activo adquirido después de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN Aplica_Regla_10Pct = 1 THEN 'Aplicó regla 10% MOI (Art 182 LISR)'
                ELSE 'Activo en uso normal en ' + CAST(@Año_Calculo AS VARCHAR(10))
            END;

    -- 14. Insertar resultados en Calculo_RMF
    INSERT INTO Calculo_RMF (
        ID_Staging, ID_Compania, ID_NUM_ACTIVO, Año_Calculo, Tipo_Activo,
        ID_PAIS, Ruta_Calculo, Descripcion_Ruta,
        MOI, Tasa_Anual, Tasa_Mensual, Dep_Anual, Dep_Acum_Inicio,
        INPCCompra, INPCUtilizado,
        Factor_Actualizacion_Saldo, Factor_Actualizacion_Dep,
        Saldo_Actualizado, Dep_Actualizada, Valor_Promedio,
        Meses_Uso_Inicio_Ejercicio, Meses_Uso_Hasta_Mitad_Periodo, Meses_Uso_En_Ejercicio,
        Saldo_Inicio_Año, Dep_Fiscal_Ejercicio, Monto_Pendiente, Proporcion,
        Prueba_10_Pct_MOI, Aplica_10_Pct,
        Valor_Reportable_USD, Tipo_Cambio_30_Junio, Valor_Reportable_MXN,
        Fecha_Adquisicion, Fecha_Baja, Fecha_Calculo, Version_SP
    )
    SELECT
        ID_Staging, @ID_Compania, ID_NUM_ACTIVO, @Año_Calculo, 'Nacional',
        ID_PAIS, Ruta_Calculo, Descripcion_Ruta,
        MOI, Tasa_Anual, Tasa_Mensual, Dep_Anual, Dep_Acum_Inicio,
        INPCCompra, INPCUtilizado,  -- NULL por ahora, se actualizarán después por sp_Actualizar_INPC_Nacionales
        Factor_Actualizacion_Saldo, Factor_Actualizacion_Dep,
        Saldo_Actualizado, Dep_Actualizada, Valor_Promedio,
        Meses_Uso_Inicio_Ejercicio, Meses_Uso_Hasta_Mitad_Periodo, Meses_Uso_Ejercicio,
        Saldo_Inicio_Año, Dep_Ejercicio, Monto_Pendiente, Proporcion,
        Prueba_10Pct, Aplica_Regla_10Pct,
        NULL, NULL, Valor_MXN,  -- No aplican USD ni TC para nacionales
        FECHA_COMPRA, FECHA_BAJA, GETDATE(), 'v4.5-LIMPIO'
    FROM #ActivosCalculo;

    SET @RegistrosProcesados = @@ROWCOUNT;

    -- 15. Mostrar resumen
    DECLARE @TotalValorReportable DECIMAL(18,2);
    DECLARE @ActivosRegla10Pct INT;

    SELECT
        @TotalValorReportable = SUM(Valor_MXN),
        @ActivosRegla10Pct = SUM(CAST(Aplica_Regla_10Pct AS INT))
    FROM #ActivosCalculo;

    PRINT '';
    PRINT '========================================';
    PRINT 'RESUMEN DE CÁLCULO';
    PRINT '========================================';
    PRINT 'Registros procesados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));
    PRINT 'Total valor reportable (MXN): $' + FORMAT(@TotalValorReportable, 'N2');
    PRINT 'Activos con regla 10% MOI: ' + CAST(@ActivosRegla10Pct AS VARCHAR(10));
    PRINT '';

    DROP TABLE #ActivosCalculo;

    PRINT 'Cálculo completado exitosamente';
    PRINT '========================================';

    RETURN @RegistrosProcesados;
END
GO

PRINT 'SP sp_Calcular_RMF_Activos_Nacionales creado (v3.0-FIXED)';
GO
