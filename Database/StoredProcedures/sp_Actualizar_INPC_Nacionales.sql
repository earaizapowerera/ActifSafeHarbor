-- =============================================
-- Stored Procedure: sp_Actualizar_INPC_Nacionales
-- Versión: 2.4
-- Descripción: Actualiza INPCCompra e INPCUtilizado en Calculo_RMF
--              según la lógica fiscal del SAT
--
-- DEBE ejecutarse DESPUÉS de sp_Calcular_RMF_Activos_Nacionales
-- y ANTES de generar el reporte final
--
-- Basado en: usp_CalculoINPCActivo del sistema Actif legacy
--
-- v2.3: Usa FECHA_FIN_DEPREC, implementa lógica de 2 años con
--       tablas inpcdeprec e INPCbajas según algoritmo original
-- v2.4: Procesa TODOS los activos (no solo INPCCompra IS NULL)
--       Fix: sp_Calcular ya puebla INPCCompra pero deja factores en 1.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Actualizar_INPC_Nacionales', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Actualizar_INPC_Nacionales;
GO

CREATE PROCEDURE dbo.sp_Actualizar_INPC_Nacionales
    @ID_Compania INT,
    @Año_Calculo INT,
    @Id_Grupo_Simulacion INT = 8  -- Por defecto grupo 8 (con INPC reales actualizados)
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '========================================';
    PRINT 'Actualizando INPC para activos nacionales';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT 'Grupo Simulación INPC: ' + CAST(@Id_Grupo_Simulacion AS VARCHAR(10));
    PRINT '========================================';

    DECLARE @ActualizadosTotal INT = 0;
    DECLARE @ErrorCount INT = 0;

    -- Tabla temporal para almacenar los datos de INPC
    CREATE TABLE #INPC_Temp (
        ID_Calculo BIGINT,
        INPCCompra DECIMAL(18,6),
        INPCUtilizado DECIMAL(18,6),
        Factor DECIMAL(18,10),
        PasoINPC NVARCHAR(50)
    );

    -- ================================================
    -- LEER ACTIVOS NACIONALES DE Calculo_RMF
    -- ================================================
    DECLARE @ID_Calculo BIGINT,
            @Fecha_Compra DATE,
            @FECHA_INICIO_DEP DATE,
            @Fecha_Fin_Deprec DATE,
            @Fecha_Baja DATE,
            @MOI DECIMAL(18,4),
            @Saldo_Inicio_Año DECIMAL(18,4),
            @Dep_Fiscal_Ejercicio DECIMAL(18,4),
            @Meses_Uso_En_Ejercicio INT,
            @Dep_Acum_Inicio DECIMAL(18,4);

    -- Cursor para procesar cada activo nacional
    DECLARE cursor_activos CURSOR FOR
    SELECT
        ID_Calculo,
        Fecha_Adquisicion,
        Fecha_Inicio_Depreciacion,
        Fecha_Fin_Depreciacion,
        Fecha_Baja,
        MOI,
        Saldo_Inicio_Año,
        Dep_Fiscal_Ejercicio,
        Meses_Uso_En_Ejercicio,
        Dep_Acum_Inicio
    FROM Calculo_RMF
    WHERE ID_Compania = @ID_Compania
      AND Año_Calculo = @Año_Calculo
      AND Tipo_Activo = 'Nacional';
      -- Cambio v2.4: Procesar TODOS los activos, no solo los que tienen INPCCompra NULL
      -- El SP sp_Calcular_RMF_Activos_Nacionales ya puebla INPCCompra, pero deja factores en 1.0

    OPEN cursor_activos;
    FETCH NEXT FROM cursor_activos INTO @ID_Calculo, @Fecha_Compra, @FECHA_INICIO_DEP, @Fecha_Fin_Deprec,
                                         @Fecha_Baja, @MOI, @Saldo_Inicio_Año, @Dep_Fiscal_Ejercicio,
                                         @Meses_Uso_En_Ejercicio, @Dep_Acum_Inicio;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @INPC_Compra DECIMAL(18,6) = NULL;
        DECLARE @INPC_Utilizado DECIMAL(18,6) = NULL;
        DECLARE @Factor DECIMAL(18,10) = 1.0;
        DECLARE @PasoINPC NVARCHAR(50) = '';

        -- ==================================================
        -- PASO 1: Obtener INPC de Compra
        -- ==================================================
        SELECT @INPC_Compra = Indice
        FROM dbo.INPC2
        WHERE Mes = MONTH(@Fecha_Compra)
          AND Anio = YEAR(@Fecha_Compra)
          AND Id_Pais = 1
          AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;

        IF @INPC_Compra IS NULL
        BEGIN
            PRINT '  ⚠️ Activo ID=' + CAST(@ID_Calculo AS VARCHAR(20)) + ': INPC Compra no encontrado para ' +
                  CAST(YEAR(@Fecha_Compra) AS VARCHAR(4)) + '-' + RIGHT('0' + CAST(MONTH(@Fecha_Compra) AS VARCHAR(2)), 2);
            SET @ErrorCount = @ErrorCount + 1;
            GOTO NextRecord;
        END

        -- ==================================================
        -- PASO 2: Determinar INPC a Utilizar según lógica SAT
        -- ==================================================

        -- CASO 1: Antes de iniciar depreciación
        IF @Año_Calculo < YEAR(@FECHA_INICIO_DEP)
           OR (@Año_Calculo = YEAR(@FECHA_INICIO_DEP) AND 12 <= MONTH(@FECHA_INICIO_DEP))
        BEGIN
            SET @INPC_Utilizado = @INPC_Compra;
            SET @Factor = 1.0;
            SET @PasoINPC = 'inic';
        END
        -- CASO 2: Completamente depreciado
        ELSE IF ABS(@MOI - @Dep_Acum_Inicio) < 1 AND @Fecha_Fin_Deprec IS NOT NULL
        BEGIN
            DECLARE @Mes_INPC_Utilizado INT;
            DECLARE @Año_INPC_Utilizado INT;
            DECLARE @Años_Desde_Fin_Deprec INT = YEAR(CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31' AS DATE)) - YEAR(@Fecha_Fin_Deprec);

            -- Verificar si tiene menos de 2 años desde que terminó de depreciarse
            IF @Años_Desde_Fin_Deprec < 2 AND (@Fecha_Baja IS NULL OR @Fecha_Baja > @Fecha_Fin_Deprec)
            BEGIN
                -- Usar tabla inpcdeprec con mes medio
                DECLARE @Id_Mes_INPC_Deprec INT;
                DECLARE @Año_INPC_Deprec INT;

                SELECT @Año_INPC_Deprec = YEAR(@Fecha_Fin_Deprec) + AñoINPC,
                       @Id_Mes_INPC_Deprec = Id_Mes_INPC
                FROM dbo.inpcdeprec
                WHERE Id_Mes_Fin_Deprec = MONTH(@Fecha_Fin_Deprec);

                IF @Año_INPC_Deprec IS NOT NULL AND @Id_Mes_INPC_Deprec IS NOT NULL
                BEGIN
                    SELECT @INPC_Utilizado = Indice
                    FROM dbo.INPC2
                    WHERE Anio = @Año_INPC_Deprec
                      AND Mes = @Id_Mes_INPC_Deprec
                      AND Id_Pais = 1
                      AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;

                    SET @PasoINPC = 'DeprecMesMedio';
                END
            END
            ELSE
            BEGIN
                -- Más de 2 años: usar mes de fin de depreciación directo
                SELECT @INPC_Utilizado = Indice
                FROM dbo.INPC2
                WHERE Mes = MONTH(@Fecha_Fin_Deprec)
                  AND Anio = YEAR(@Fecha_Fin_Deprec)
                  AND Id_Pais = 1
                  AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;

                SET @PasoINPC = 'DepreciadoMesFin';
            END

            IF @INPC_Utilizado IS NOT NULL
            BEGIN
                SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
                IF @Factor < 1 SET @Factor = 1;
            END
        END
        -- CASO 3: Dado de baja en el año
        ELSE IF @Fecha_Baja IS NOT NULL AND YEAR(@Fecha_Baja) = @Año_Calculo
        BEGIN
            DECLARE @Mes_Anterior_Baja INT = MONTH(DATEADD(MONTH, -1, @Fecha_Baja));
            DECLARE @Año_Baja_INPC INT;
            DECLARE @Id_MesINPC INT;
            DECLARE @Años_Desde_Baja INT = YEAR(CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31' AS DATE)) - YEAR(@Fecha_Baja);

            -- Verificar si tiene menos de 2 años desde la baja
            IF @Años_Desde_Baja < 2
            BEGIN
                -- Buscar en tabla INPCbajas con mes medio
                SELECT @Año_Baja_INPC = YEAR(DATEADD(MONTH, -1, @Fecha_Baja)) + AñoINPC,
                       @Id_MesINPC = Id_MesINPC
                FROM dbo.INPCbajas
                WHERE Id_Mes = @Mes_Anterior_Baja;

                IF @Año_Baja_INPC IS NOT NULL AND @Id_MesINPC IS NOT NULL
                BEGIN
                    SELECT @INPC_Utilizado = Indice
                    FROM dbo.INPC2
                    WHERE Anio = @Año_Baja_INPC
                      AND Mes = @Id_MesINPC
                      AND Id_Pais = 1
                      AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;
                END
            END
            ELSE
            BEGIN
                -- Más de 2 años: usar mes anterior a la baja directamente
                SELECT @INPC_Utilizado = Indice
                FROM dbo.INPC2
                WHERE Mes = @Mes_Anterior_Baja
                  AND Anio = YEAR(DATEADD(MONTH, -1, @Fecha_Baja))
                  AND Id_Pais = 1
                  AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;
            END

            IF @INPC_Utilizado IS NOT NULL
            BEGIN
                SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
                IF @Factor < 1 SET @Factor = 1;
            END
            SET @PasoINPC = 'baja';
        END
        -- CASO 4: Adquirido en el año actual
        ELSE IF YEAR(@Fecha_Compra) = @Año_Calculo
        BEGIN
            -- Fórmula SAT: mes_medio = ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)
            DECLARE @Mes_Medio INT;
            SET @Mes_Medio = ROUND((12.0 - (MONTH(@Fecha_Compra) - 1)) / 2.0, 0, 1) + (MONTH(@Fecha_Compra) - 1);

            SELECT @INPC_Utilizado = Indice
            FROM dbo.INPC2
            WHERE Anio = @Año_Calculo
              AND Mes = @Mes_Medio
              AND Id_Pais = 1
              AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;

            IF @INPC_Utilizado IS NOT NULL
            BEGIN
                SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
                IF @Factor < 1 SET @Factor = 1;
            END
            SET @PasoINPC = 'mismoaño';
        END
        -- CASO 5: De años anteriores, activo normal
        ELSE IF YEAR(@Fecha_Compra) < @Año_Calculo
        BEGIN
            DECLARE @MesINPC_SegunTabla INT;
            DECLARE @AñoINPC_SegunTabla INT;

            -- Buscar en tabla INPCSegunMes (para diciembre Safe Harbor = mes 6 = junio)
            SELECT @MesINPC_SegunTabla = MesINPC,
                   @AñoINPC_SegunTabla = @Año_Calculo + AñoINPC
            FROM dbo.INPCSegunMes
            WHERE MesCalculo = 12;  -- Safe Harbor anual usa diciembre

            IF @MesINPC_SegunTabla IS NOT NULL
            BEGIN
                SELECT @INPC_Utilizado = Indice
                FROM dbo.INPC2
                WHERE Anio = @AñoINPC_SegunTabla
                  AND Mes = @MesINPC_SegunTabla
                  AND Id_Pais = 1
                  AND Id_Grupo_Simulacion = @Id_Grupo_Simulacion;

                IF @INPC_Utilizado IS NOT NULL
                BEGIN
                    SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
                    IF ISNULL(@Factor, 0) < 1 SET @Factor = 1;
                END
            END
            SET @PasoINPC = 'AñosAnteriores';
        END

        -- Insertar en tabla temporal
        IF @INPC_Compra IS NOT NULL AND @INPC_Utilizado IS NOT NULL
        BEGIN
            INSERT INTO #INPC_Temp (ID_Calculo, INPCCompra, INPCUtilizado, Factor, PasoINPC)
            VALUES (@ID_Calculo, @INPC_Compra, @INPC_Utilizado, @Factor, @PasoINPC);

            SET @ActualizadosTotal = @ActualizadosTotal + 1;
        END
        ELSE
        BEGIN
            PRINT '  ⚠️ Activo ID=' + CAST(@ID_Calculo AS VARCHAR(20)) + ': No se pudo determinar INPC Utilizado';
            SET @ErrorCount = @ErrorCount + 1;
        END

NextRecord:
        FETCH NEXT FROM cursor_activos INTO @ID_Calculo, @Fecha_Compra, @FECHA_INICIO_DEP, @Fecha_Fin_Deprec,
                                             @Fecha_Baja, @MOI, @Saldo_Inicio_Año, @Dep_Fiscal_Ejercicio,
                                             @Meses_Uso_En_Ejercicio, @Dep_Acum_Inicio;
    END

    CLOSE cursor_activos;
    DEALLOCATE cursor_activos;

    PRINT '';
    PRINT 'Activos procesados: ' + CAST(@ActualizadosTotal AS VARCHAR(10));
    PRINT 'Errores encontrados: ' + CAST(@ErrorCount AS VARCHAR(10));

    -- ================================================
    -- ACTUALIZAR Calculo_RMF CON INPC Y RECALCULAR
    -- ================================================
    PRINT '';
    PRINT 'Actualizando Calculo_RMF con INPC y recalculando valores...';

    UPDATE c
    SET
        c.INPCCompra = t.INPCCompra,
        c.INPCUtilizado = t.INPCUtilizado,
        c.Factor_Actualizacion_Saldo = t.Factor,
        c.Factor_Actualizacion_Dep = t.Factor,
        c.Saldo_Actualizado = c.Saldo_Inicio_Año * t.Factor,
        c.Dep_Actualizada = c.Dep_Fiscal_Ejercicio * t.Factor,
        c.Valor_Promedio = (c.Saldo_Inicio_Año * t.Factor) - ((c.Dep_Fiscal_Ejercicio * t.Factor) * 0.5),
        c.Proporcion = ((c.Saldo_Inicio_Año * t.Factor) - ((c.Dep_Fiscal_Ejercicio * t.Factor) * 0.5)) * (c.Meses_Uso_En_Ejercicio / 12.0),
        c.Valor_Reportable_MXN =
            CASE
                WHEN (((c.Saldo_Inicio_Año * t.Factor) - ((c.Dep_Fiscal_Ejercicio * t.Factor) * 0.5)) * (c.Meses_Uso_En_Ejercicio / 12.0)) > (c.MOI * 0.10)
                THEN ((c.Saldo_Inicio_Año * t.Factor) - ((c.Dep_Fiscal_Ejercicio * t.Factor) * 0.5)) * (c.Meses_Uso_En_Ejercicio / 12.0)
                ELSE c.MOI * 0.10
            END,
        c.Aplica_10_Pct =
            CASE
                WHEN (((c.Saldo_Inicio_Año * t.Factor) - ((c.Dep_Fiscal_Ejercicio * t.Factor) * 0.5)) * (c.Meses_Uso_En_Ejercicio / 12.0)) <= (c.MOI * 0.10)
                THEN 1
                ELSE 0
            END
    FROM Calculo_RMF c
    INNER JOIN #INPC_Temp t ON c.ID_Calculo = t.ID_Calculo;

    DECLARE @RegistrosActualizados INT = @@ROWCOUNT;

    PRINT 'Registros actualizados en Calculo_RMF: ' + CAST(@RegistrosActualizados AS VARCHAR(10));

    -- ================================================
    -- RESUMEN
    -- ================================================
    PRINT '';
    PRINT '========================================';
    PRINT 'RESUMEN POR TIPO DE CÁLCULO INPC:';
    PRINT '========================================';

    SELECT
        PasoINPC,
        COUNT(*) AS Cantidad
    FROM #INPC_Temp
    GROUP BY PasoINPC
    ORDER BY PasoINPC;

    PRINT '';
    PRINT '========================================';
    PRINT 'TOTAL ACTIVOS ACTUALIZADOS: ' + CAST(@ActualizadosTotal AS VARCHAR(10));

    IF @ErrorCount > 0
    BEGIN
        PRINT '⚠️ ADVERTENCIA: ' + CAST(@ErrorCount AS VARCHAR(10)) + ' activos con errores (INPC no encontrado)';
    END

    PRINT '========================================';

    -- Limpiar tabla temporal
    DROP TABLE #INPC_Temp;

    RETURN @ActualizadosTotal;
END
GO

PRINT 'SP sp_Actualizar_INPC_Nacionales v2.4 creado exitosamente';
PRINT 'IMPORTANTE: Este SP actualiza Calculo_RMF (NO Staging_Activo)';
PRINT 'Debe ejecutarse DESPUÉS de sp_Calcular_RMF_Activos_Nacionales';
PRINT 'v2.4: Procesa TODOS los activos (fix: factores fiscales en 1.0)';
GO
