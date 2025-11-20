-- =============================================
-- DEPLOY: SP Calcular RMF Activos NACIONALES v5.2
-- SAFE HARBOR + VALIDACIÓN INPC + INPCs COMPLETOS
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
    DECLARE @INPC_Junio DECIMAL(18,6) = NULL;

    PRINT '========================================';
    PRINT 'Cálculo RMF Activos Nacionales v5.2';
    PRINT 'SAFE HARBOR + VALIDACIÓN INPC + INPCs COMPLETOS';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT '========================================';

    -- 1. Eliminar cálculos previos de esta compañía/año
    DELETE FROM Calculo_RMF
    WHERE ID_Compania = @ID_Compania
      AND Año_Calculo = @Año_Calculo
      AND Tipo_Activo = 'Nacional';

    PRINT 'Cálculos previos eliminados: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- 2. Obtener INPC de JUNIO del año de cálculo (para Safe Harbor)
    -- Buscar en tabla local INPC2
    SELECT @INPC_Junio = Indice
    FROM INPC2
    WHERE Anio = @Año_Calculo
      AND Mes = 6  -- JUNIO - FIJO para Safe Harbor
      AND Id_Pais = 1
      AND Id_Grupo_Simulacion = 8;

    IF @INPC_Junio IS NULL
    BEGIN
        PRINT 'ADVERTENCIA: No se encontró INPC de junio ' + CAST(@Año_Calculo AS VARCHAR(10)) + ' en tabla local INPC2';
        PRINT 'Se usará factor 1.0 para Safe Harbor';
        SET @INPC_Junio = 0;  -- Marcar como no encontrado
    END
    ELSE
    BEGIN
        PRINT 'INPC de junio ' + CAST(@Año_Calculo AS VARCHAR(10)) + ': ' + CAST(@INPC_Junio AS VARCHAR(20));
    END

    -- 3. Crear tabla temporal CON CAMPOS SAFE HARBOR
    CREATE TABLE #ActivosCalculo (
        ID_Staging BIGINT,
        ID_NUM_ACTIVO INT,
        MOI DECIMAL(18,4),
        Tasa_Anual DECIMAL(10,6),
        Tasa_Mensual DECIMAL(18,6),
        Dep_Anual DECIMAL(18,4),
        FECHA_COMPRA DATE,
        FECHA_INICIO_DEP DATE,
        FECHA_BAJA DATE,
        ID_PAIS INT,
        Dep_Acum_Inicio DECIMAL(18,4),

        -- INPC
        INPCCompra DECIMAL(18,6),
        INPCUtilizado DECIMAL(18,6),  -- Para fiscal (actualizado después)
        INPC_Mitad_Ejercicio DECIMAL(18,6),  -- INPC del 30 de junio
        INPC_Mitad_Periodo DECIMAL(18,6),  -- INPC de mitad del periodo de uso

        -- Meses
        Meses_Uso_Inicio_Ejercicio INT,
        Meses_Uso_Hasta_Mitad_Periodo INT,
        Meses_Uso_Ejercicio INT,

        -- Cálculos base
        Saldo_Inicio_Año DECIMAL(18,4),
        Dep_Ejercicio DECIMAL(18,4),
        Monto_Pendiente DECIMAL(18,4),

        -- ========================================
        -- CAMPOS FISCALES (actualizados después por programa externo)
        -- ========================================
        Factor_Actualizacion_Saldo DECIMAL(18,10),
        Saldo_Actualizado DECIMAL(18,4),
        Factor_Actualizacion_Dep DECIMAL(18,10),
        Dep_Actualizada DECIMAL(18,4),
        Valor_Promedio DECIMAL(18,4),
        Proporcion DECIMAL(18,4),

        -- ========================================
        -- CAMPOS SAFE HARBOR (calculados aquí con INPC de junio)
        -- ========================================
        INPC_SH_Junio DECIMAL(18,6),
        Factor_SH DECIMAL(18,10),
        Saldo_SH_Actualizado DECIMAL(18,4),
        Dep_SH_Actualizada DECIMAL(18,4),
        Valor_SH_Promedio DECIMAL(18,4),
        Proporcion_SH DECIMAL(18,4),
        Saldo_SH_Fiscal_Hist DECIMAL(18,4),
        Saldo_SH_Fiscal_Act DECIMAL(18,4),
        Valor_SH_Reportable DECIMAL(18,4),

        -- Resultado fiscal (placeholder, actualizado después)
        Prueba_10Pct DECIMAL(18,4),
        Valor_MXN DECIMAL(18,4),
        Aplica_Regla_10Pct BIT,

        -- Control
        Ruta_Calculo NVARCHAR(20),
        Descripcion_Ruta NVARCHAR(200),

        -- Validación INPC
        TieneErrorINPC BIT DEFAULT 0,
        MensajeErrorINPC NVARCHAR(500)
    );

    -- 4. Insertar activos NACIONALES
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
        s.FECHA_INICIO_DEP,
        s.FECHA_BAJA,
        s.ID_PAIS,
        ISNULL(s.Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio
    FROM Staging_Activo s
    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.ManejaFiscal = 'S'
      AND s.CostoMXN IS NOT NULL
      AND s.CostoMXN > 0
      AND s.Tasa_Anual > 0;

    SET @RegistrosProcesados = @@ROWCOUNT;
    PRINT 'Activos nacionales encontrados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));

    IF @RegistrosProcesados = 0
    BEGIN
        PRINT 'No hay activos nacionales para calcular';
        DROP TABLE #ActivosCalculo;
        RETURN 0;
    END

    -- 5. Obtener INPC de Compra de tabla local INPC2
    UPDATE ac
    SET ac.INPCCompra = inpc.Indice
    FROM #ActivosCalculo ac
    LEFT JOIN INPC2 inpc
        ON YEAR(ac.FECHA_COMPRA) = inpc.Anio
        AND MONTH(ac.FECHA_COMPRA) = inpc.Mes
        AND inpc.Id_Pais = 1
        AND inpc.Id_Grupo_Simulacion = 8;

    PRINT 'INPC de compra obtenidos de tabla local INPC2';

    -- 5.1. VALIDAR INPC FALTANTES - Marcar errores de cálculo
    DECLARE @ActivosConErrorINPC INT;

    UPDATE #ActivosCalculo
    SET TieneErrorINPC = 1,
        MensajeErrorINPC = 'ERROR: No se encontró INPC para ' +
            DATENAME(MONTH, FECHA_COMPRA) + ' ' + CAST(YEAR(FECHA_COMPRA) AS VARCHAR(4)) +
            ' (Año: ' + CAST(YEAR(FECHA_COMPRA) AS VARCHAR(4)) +
            ', Mes: ' + CAST(MONTH(FECHA_COMPRA) AS VARCHAR(2)) + ')'
    WHERE INPCCompra IS NULL
      AND FECHA_COMPRA IS NOT NULL;

    SET @ActivosConErrorINPC = @@ROWCOUNT;

    IF @ActivosConErrorINPC > 0
    BEGIN
        PRINT '';
        PRINT '*** ADVERTENCIA: ' + CAST(@ActivosConErrorINPC AS VARCHAR(10)) + ' activos con INPC faltante ***';
        PRINT 'Los cálculos de estos activos estarán marcados con ERROR';
        PRINT '';

        -- Mostrar detalle de INPCs faltantes
        DECLARE @INPCsFaltantes NVARCHAR(MAX);
        SELECT @INPCsFaltantes = STRING_AGG(
            CAST(YEAR(FECHA_COMPRA) AS VARCHAR(4)) + '-' +
            RIGHT('0' + CAST(MONTH(FECHA_COMPRA) AS VARCHAR(2)), 2) +
            ' (Folio: ' + CAST(ID_NUM_ACTIVO AS VARCHAR(10)) + ')',
            ', '
        )
        FROM #ActivosCalculo
        WHERE TieneErrorINPC = 1;

        PRINT 'INPCs faltantes: ' + ISNULL(@INPCsFaltantes, 'N/A');
        PRINT '';
    END

    -- 5.2. Obtener INPC Mitad Ejercicio (30 junio) para TODOS los activos
    UPDATE #ActivosCalculo
    SET INPC_Mitad_Ejercicio = @INPC_Junio;

    PRINT 'INPC Mitad Ejercicio (30 junio) asignado: ' + CAST(@INPC_Junio AS VARCHAR(20));

    -- 5.3. Calcular INPC Mitad Periodo
    -- Primero calcular la fecha de mitad del periodo de uso
    DECLARE @TempINPCMitadPeriodo TABLE (
        ID_Staging BIGINT,
        Fecha_Mitad_Periodo DATE,
        INPC_Mitad_Periodo DECIMAL(18,6)
    );

    INSERT INTO @TempINPCMitadPeriodo (ID_Staging, Fecha_Mitad_Periodo, INPC_Mitad_Periodo)
    SELECT
        ac.ID_Staging,
        -- Fecha mitad del periodo
        CASE
            WHEN ac.FECHA_BAJA IS NOT NULL AND YEAR(ac.FECHA_BAJA) = @Año_Calculo THEN
                DATEADD(DAY, DATEDIFF(DAY, CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE), ac.FECHA_BAJA) / 2,
                        CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE))
            WHEN ac.FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) THEN
                DATEADD(DAY, DATEDIFF(DAY, ac.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31' AS DATE)) / 2, ac.FECHA_COMPRA)
            ELSE
                @Fecha_30_Junio  -- Activo todo el año: mitad = 30 junio
        END AS Fecha_Mitad_Periodo,
        NULL AS INPC_Mitad_Periodo
    FROM #ActivosCalculo ac;

    -- Obtener INPC de esa fecha
    UPDATE tmp
    SET tmp.INPC_Mitad_Periodo = inpc.Indice
    FROM @TempINPCMitadPeriodo tmp
    LEFT JOIN INPC2 inpc
        ON YEAR(tmp.Fecha_Mitad_Periodo) = inpc.Anio
        AND MONTH(tmp.Fecha_Mitad_Periodo) = inpc.Mes
        AND inpc.Id_Pais = 1
        AND inpc.Id_Grupo_Simulacion = 8;

    -- Actualizar tabla principal
    UPDATE ac
    SET ac.INPC_Mitad_Periodo = tmp.INPC_Mitad_Periodo
    FROM #ActivosCalculo ac
    INNER JOIN @TempINPCMitadPeriodo tmp ON ac.ID_Staging = tmp.ID_Staging;

    PRINT 'INPC Mitad Periodo calculado';

    -- 6. Calcular Depreciación Anual
    UPDATE #ActivosCalculo
    SET Dep_Anual = MOI * (Tasa_Anual / 100);

    -- 7. Calcular meses de uso al inicio del ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Inicio_Ejercicio =
        CASE
            WHEN FECHA_INICIO_DEP IS NULL OR FECHA_INICIO_DEP >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 0
            ELSE DATEDIFF(MONTH, FECHA_INICIO_DEP, CAST(CAST(@Año_Anterior AS VARCHAR(4)) + '-12-31' AS DATE)) + 1
        END;

    -- 8. Calcular meses hasta la mitad del periodo
    UPDATE #ActivosCalculo
    SET Meses_Uso_Hasta_Mitad_Periodo =
        CASE
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA) / 2
            WHEN FECHA_COMPRA < CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 6
            ELSE (13 - MONTH(FECHA_COMPRA)) / 2
        END;

    -- 9. Calcular meses de uso en el ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Ejercicio =
        CASE
            WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo
            THEN MONTH(FECHA_BAJA)
            WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 13 - MONTH(FECHA_COMPRA)
            ELSE 12
        END;

    PRINT 'Meses de uso calculados';

    -- 10. Calcular Saldo por Deducir ISR al Inicio del Año
    UPDATE #ActivosCalculo
    SET Saldo_Inicio_Año = MOI - Dep_Acum_Inicio;

    -- 11. EXCLUIR activos totalmente depreciados
    DELETE FROM #ActivosCalculo
    WHERE Saldo_Inicio_Año <= 0;

    PRINT 'Activos totalmente depreciados excluidos: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- 12. Calcular Depreciación Fiscal del Ejercicio
    UPDATE #ActivosCalculo
    SET Dep_Ejercicio =
        CASE
            WHEN (MOI * (Tasa_Anual / 12 / 100) * Meses_Uso_Ejercicio) > Saldo_Inicio_Año
            THEN Saldo_Inicio_Año
            ELSE MOI * (Tasa_Anual / 12 / 100) * Meses_Uso_Ejercicio
        END;

    -- 13. Calcular Monto Pendiente
    UPDATE #ActivosCalculo
    SET Monto_Pendiente =
        CASE
            WHEN (Saldo_Inicio_Año - Dep_Ejercicio) < 0 THEN 0
            ELSE (Saldo_Inicio_Año - Dep_Ejercicio)
        END;

    -- ========================================
    -- CÁLCULOS FISCALES (placeholder - actualizados después)
    -- ========================================
    UPDATE #ActivosCalculo
    SET Factor_Actualizacion_Saldo = 1.0,
        Saldo_Actualizado = Saldo_Inicio_Año,
        Factor_Actualizacion_Dep = 1.0,
        Dep_Actualizada = Dep_Ejercicio,
        Valor_Promedio = Saldo_Inicio_Año - (Dep_Ejercicio * 0.5),
        Proporcion = (Saldo_Inicio_Año - (Dep_Ejercicio * 0.5)) * (Meses_Uso_Ejercicio / 12.0);

    PRINT 'Valores fiscales calculados (sin actualización INPC - se aplicará después)';

    -- ========================================
    -- CÁLCULOS SAFE HARBOR con INPC de JUNIO
    -- ========================================
    PRINT '';
    PRINT '========================================';
    PRINT 'CALCULANDO SAFE HARBOR (INPC de junio)';
    PRINT '========================================';

    -- 14. Asignar INPC de Junio a todos los activos
    UPDATE #ActivosCalculo
    SET INPC_SH_Junio = @INPC_Junio;

    -- 15. Calcular Factor Safe Harbor (INPC Junio / INPC Compra)
    UPDATE #ActivosCalculo
    SET Factor_SH =
        CASE
            WHEN INPCCompra IS NOT NULL AND INPCCompra > 0 AND @INPC_Junio > 0
            THEN @INPC_Junio / INPCCompra
            ELSE 1.0
        END;

    PRINT 'Factor Safe Harbor calculado (INPC Junio / INPC Compra)';

    -- 16. Calcular Saldo Safe Harbor Actualizado
    UPDATE #ActivosCalculo
    SET Saldo_SH_Actualizado = Saldo_Inicio_Año * Factor_SH;

    -- 17. Calcular Depreciación Safe Harbor Actualizada
    UPDATE #ActivosCalculo
    SET Dep_SH_Actualizada = Dep_Ejercicio * Factor_SH;

    -- 18. Calcular Valor Promedio Safe Harbor
    -- Fórmula: Saldo Actualizado - 50% de Depreciación Actualizada
    UPDATE #ActivosCalculo
    SET Valor_SH_Promedio = Saldo_SH_Actualizado - (Dep_SH_Actualizada * 0.5);

    -- 19. Calcular Proporción Safe Harbor
    -- Fórmula: (Valor Promedio / 12) × Meses de Uso
    UPDATE #ActivosCalculo
    SET Proporcion_SH = (Valor_SH_Promedio / 12.0) * Meses_Uso_Ejercicio;

    -- 20. Calcular Saldo Fiscal por Deducir Histórico (sin actualizar)
    -- Fórmula: MOI - Dep Acum Inicio - Dep Ejercicio
    UPDATE #ActivosCalculo
    SET Saldo_SH_Fiscal_Hist = MOI - Dep_Acum_Inicio - Dep_Ejercicio;

    -- 21. Calcular Saldo Fiscal por Deducir Actualizado
    -- Fórmula: Saldo Histórico × Factor Safe Harbor
    UPDATE #ActivosCalculo
    SET Saldo_SH_Fiscal_Act = Saldo_SH_Fiscal_Hist * Factor_SH;

    -- 22. Calcular Valor Reportable Safe Harbor (aplicar regla 10% MOI)
    -- Fórmula: MAX(Proporción Safe Harbor, 10% MOI)
    UPDATE #ActivosCalculo
    SET Prueba_10Pct = MOI * 0.10,
        Valor_SH_Reportable =
            CASE
                WHEN Proporcion_SH > (MOI * 0.10) THEN Proporcion_SH
                ELSE MOI * 0.10
            END;

    PRINT 'Valor Reportable Safe Harbor calculado con regla 10% MOI';

    -- ========================================
    -- VALOR FISCAL (placeholder)
    -- ========================================
    UPDATE #ActivosCalculo
    SET Valor_MXN =  -- Valor fiscal placeholder
            CASE
                WHEN Proporcion > (MOI * 0.10) THEN Proporcion
                ELSE MOI * 0.10
            END,
        Aplica_Regla_10Pct =
            CASE
                WHEN Proporcion <= (MOI * 0.10) THEN 1
                ELSE 0
            END;

    -- 23. Determinar ruta de cálculo
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

    -- 24. Insertar resultados en Calculo_RMF (CON CAMPOS SAFE HARBOR)
    INSERT INTO Calculo_RMF (
        ID_Staging, ID_Compania, ID_NUM_ACTIVO, Año_Calculo, Tipo_Activo,
        ID_PAIS, Ruta_Calculo, Descripcion_Ruta,
        MOI, Tasa_Anual, Tasa_Mensual, Dep_Anual, Dep_Acum_Inicio,

        -- INPC
        INPCCompra, INPCUtilizado, INPC_Mitad_Ejercicio, INPC_Mitad_Periodo,

        -- CAMPOS FISCALES (actualizados después por programa externo)
        Factor_Actualizacion_Saldo, Factor_Actualizacion_Dep,
        Saldo_Actualizado, Dep_Actualizada, Valor_Promedio, Proporcion,

        -- CAMPOS SAFE HARBOR (calculados aquí)
        INPC_SH_Junio, Factor_SH,
        Saldo_SH_Actualizado, Dep_SH_Actualizada,
        Valor_SH_Promedio, Proporcion_SH,
        Saldo_SH_Fiscal_Hist, Saldo_SH_Fiscal_Act,
        Valor_SH_Reportable,

        -- Meses
        Meses_Uso_Inicio_Ejercicio, Meses_Uso_Hasta_Mitad_Periodo, Meses_Uso_En_Ejercicio,

        -- Otros
        Saldo_Inicio_Año, Dep_Fiscal_Ejercicio, Monto_Pendiente,
        Prueba_10_Pct_MOI, Aplica_10_Pct,
        Valor_Reportable_USD, Tipo_Cambio_30_Junio, Valor_Reportable_MXN,
        Fecha_Adquisicion, Fecha_Baja, Observaciones, Fecha_Calculo, Version_SP
    )
    SELECT
        ID_Staging, @ID_Compania, ID_NUM_ACTIVO, @Año_Calculo, 'Nacional',
        ID_PAIS, Ruta_Calculo, Descripcion_Ruta,
        MOI, Tasa_Anual, Tasa_Mensual, Dep_Anual, Dep_Acum_Inicio,

        -- INPC
        INPCCompra, INPCUtilizado, INPC_Mitad_Ejercicio, INPC_Mitad_Periodo,

        -- CAMPOS FISCALES
        Factor_Actualizacion_Saldo, Factor_Actualizacion_Dep,
        Saldo_Actualizado, Dep_Actualizada, Valor_Promedio, Proporcion,

        -- CAMPOS SAFE HARBOR
        INPC_SH_Junio, Factor_SH,
        Saldo_SH_Actualizado, Dep_SH_Actualizada,
        Valor_SH_Promedio, Proporcion_SH,
        Saldo_SH_Fiscal_Hist, Saldo_SH_Fiscal_Act,
        Valor_SH_Reportable,

        -- Meses
        Meses_Uso_Inicio_Ejercicio, Meses_Uso_Hasta_Mitad_Periodo, Meses_Uso_Ejercicio,

        -- Otros
        Saldo_Inicio_Año, Dep_Ejercicio, Monto_Pendiente,
        Prueba_10Pct, Aplica_Regla_10Pct,
        NULL, NULL, Valor_MXN,  -- No aplican USD ni TC para nacionales
        FECHA_COMPRA, FECHA_BAJA,
        -- Observaciones con error de INPC si aplica
        CASE
            WHEN TieneErrorINPC = 1 THEN MensajeErrorINPC
            ELSE NULL
        END,
        GETDATE(), 'v5.2-INPC-COMPLETE'
    FROM #ActivosCalculo;

    SET @RegistrosProcesados = @@ROWCOUNT;

    -- 25. Mostrar resumen
    DECLARE @TotalValorFiscal DECIMAL(18,2);
    DECLARE @TotalValorSafeHarbor DECIMAL(18,2);
    DECLARE @ActivosRegla10Pct INT;
    DECLARE @TotalActivosConError INT;

    SELECT
        @TotalValorFiscal = SUM(Valor_MXN),
        @TotalValorSafeHarbor = SUM(Valor_SH_Reportable),
        @ActivosRegla10Pct = SUM(CAST(Aplica_Regla_10Pct AS INT)),
        @TotalActivosConError = SUM(CAST(TieneErrorINPC AS INT))
    FROM #ActivosCalculo;

    PRINT '';
    PRINT '========================================';
    PRINT 'RESUMEN DE CÁLCULO';
    PRINT '========================================';
    PRINT 'Registros procesados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));
    PRINT 'Total valor FISCAL (MXN): $' + FORMAT(@TotalValorFiscal, 'N2');
    PRINT 'Total valor SAFE HARBOR (MXN): $' + FORMAT(@TotalValorSafeHarbor, 'N2');
    PRINT 'Activos con regla 10% MOI: ' + CAST(@ActivosRegla10Pct AS VARCHAR(10));
    PRINT 'INPC Junio utilizado: ' + CAST(@INPC_Junio AS VARCHAR(20));
    IF @TotalActivosConError > 0
    BEGIN
        PRINT '';
        PRINT '*** ATENCIÓN: ' + CAST(@TotalActivosConError AS VARCHAR(10)) + ' activos con ERROR de INPC ***';
        PRINT '*** Revisar campo Observaciones en el reporte Excel ***';
    END
    PRINT '';

    DROP TABLE #ActivosCalculo;

    PRINT 'Cálculo completado exitosamente';
    PRINT '========================================';

    RETURN @RegistrosProcesados;

END
GO

PRINT 'SP sp_Calcular_RMF_Activos_Nacionales v5.0 SAFE HARBOR creado';
GO


PRINT SP sp_Calcular_RMF_Activos_Nacionales v5.2 desplegado exitosamente;
PRINT Cambios v5.2:;
PRINT   - INPC_Mitad_Ejercicio calculado y guardado;
PRINT   - INPC_Mitad_Periodo calculado y guardado;
PRINT   - Validación de INPC faltantes (v5.1);
GO

