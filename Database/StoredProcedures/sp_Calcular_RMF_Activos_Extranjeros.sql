-- =============================================
-- DROP y RE-CREATE del Stored Procedure v4.8
-- CAMBIOS v4.8:
-- - ELIMINADO: Campos INPC de tabla temporal y queries (extranjeros no usan INPC)
-- - Staging_Activo ya no tiene campos INPC
-- - INPCCompra e INPCUtilizado en Calculo_RMF se guardan como NULL (no aplican)
-- CAMBIOS v4.7:
-- - ELIMINADO: Parámetro @Lote_Importacion
-- - Sistema ahora procesa TODOS los activos del año/compañía en Staging_Activo
-- - Filtro cambiado de Lote_Importacion a Año_Calculo
-- - Mantiene filtro ID_PAIS > 1 para evitar duplicación
-- - Activos mexicanos con ManejaUSGAAP='S' se procesan en SP Nacionales usando CostoMXN
-- =============================================

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Extranjeros', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros
    @ID_Compania INT,
    @Año_Calculo INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Año_Anterior INT = @Año_Calculo - 1;
    DECLARE @Fecha_30_Junio DATE = CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-06-30' AS DATE);
    DECLARE @TipoCambio_30Jun DECIMAL(18,6);
    DECLARE @TipoCambio_31Dic_AñoAnterior DECIMAL(18,6);
    DECLARE @RegistrosProcesados INT = 0;

    PRINT '========================================';
    PRINT 'Iniciando cálculo RMF Activos Extranjeros v4.8';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT '========================================';

    -- 1. Obtener tipo de cambio del 30 de junio del año actual
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

    -- 2. Obtener tipo de cambio del 31 de diciembre del año anterior (para cálculo de depreciación tipo 2)
    SELECT TOP 1 @TipoCambio_31Dic_AñoAnterior = Tipo_Cambio
    FROM Tipo_Cambio
    WHERE Año = @Año_Anterior
      AND MONTH(Fecha) = 12
      AND DAY(Fecha) = 31
    ORDER BY Fecha DESC;

    IF @TipoCambio_31Dic_AñoAnterior IS NULL
    BEGIN
        PRINT 'ADVERTENCIA: No se encontró tipo de cambio para el 31 de diciembre de ' + CAST(@Año_Anterior AS VARCHAR(10));
        PRINT 'Se usará tipo de cambio de 30-Jun para cálculos de activos tipo 2';
        SET @TipoCambio_31Dic_AñoAnterior = @TipoCambio_30Jun;
    END
    ELSE
    BEGIN
        PRINT 'Tipo de cambio 31-Dic-' + CAST(@Año_Anterior AS VARCHAR(10)) + ': ' + CAST(@TipoCambio_31Dic_AñoAnterior AS VARCHAR(20));
    END

    -- Crear tabla temporal
    CREATE TABLE #ActivosCalculo (
        ID_Staging BIGINT,
        ID_NUM_ACTIVO INT,
        ID_ACTIVO NVARCHAR(50),
        DESCRIPCION NVARCHAR(500),
        MOI DECIMAL(18,4),
        Tasa_Anual DECIMAL(10,6),
        Tasa_Mensual DECIMAL(18,6),
        Dep_Anual DECIMAL(18,4),
        FECHA_COMPRA DATE,
        FECHA_BAJA DATE,
        FECHA_INIC_DEPREC_3 DATE,
        ID_PAIS INT,
        Dep_Acum_Inicio DECIMAL(18,4),
        Dep_Acum_Calculada DECIMAL(18,4),
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
        Descripcion_Ruta NVARCHAR(200),
        Usa_Calculo_Tipo2 BIT
    );

    -- 2. Insertar SOLO activos extranjeros (ID_PAIS > 1)
    -- IMPORTANTE: NO incluir activos mexicanos (ID_PAIS=1) aunque tengan ManejaUSGAAP='S'
    -- Los activos mexicanos con USGAAP se procesan en el SP de Nacionales usando CostoMXN
    -- v4.7: Procesa TODOS los activos del año/compañía (sin filtrar por Lote_Importacion)
    INSERT INTO #ActivosCalculo (
        ID_Staging, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
        MOI, Tasa_Anual, Tasa_Mensual,
        FECHA_COMPRA, FECHA_BAJA, FECHA_INIC_DEPREC_3, ID_PAIS,
        Dep_Acum_Inicio,
        Usa_Calculo_Tipo2
    )
    SELECT
        s.ID_Staging,
        s.ID_NUM_ACTIVO,
        s.ID_ACTIVO,
        s.DESCRIPCION,
        s.CostoUSD AS MOI,  -- Usar CostoUSD para activos extranjeros
        s.Tasa_Anual,
        s.Tasa_Mensual,
        s.FECHA_COMPRA,
        s.FECHA_BAJA,
        s.FECHA_INIC_DEPREC_3,
        s.ID_PAIS,
        ISNULL(s.Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio,
        -- Marcar si usará cálculo tipo 2 (cuando no tiene depreciación acumulada o es 0)
        CASE WHEN ISNULL(s.Dep_Acum_Inicio_Año, 0) = 0 THEN 1 ELSE 0 END AS Usa_Calculo_Tipo2
    FROM Staging_Activo s
    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo  -- v4.7: Filtro por año en lugar de lote
      AND s.ID_PAIS > 1  -- CRÍTICO: Solo extranjeros (excluye México = 1)
      AND s.CostoUSD IS NOT NULL
      AND s.CostoUSD > 0;

    SET @RegistrosProcesados = @@ROWCOUNT;
    PRINT 'Activos extranjeros encontrados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));

    IF @RegistrosProcesados = 0
    BEGIN
        PRINT 'No hay activos extranjeros para calcular';
        RETURN 0;
    END

    -- 2.1. Calcular depreciación acumulada para activos tipo 2 usando la función
    -- Solo para activos marcados con Usa_Calculo_Tipo2 = 1
    -- USAR Tasa_Anual para mayor precisión (la función calcula tasa mensual internamente)
    UPDATE #ActivosCalculo
    SET Dep_Acum_Calculada = dbo.fn_CalcularDepFiscal_Tipo2(
        MOI,
        Tasa_Anual,
        FECHA_INIC_DEPREC_3,
        @Año_Anterior,
        ID_PAIS,
        @TipoCambio_31Dic_AñoAnterior
    )
    WHERE Usa_Calculo_Tipo2 = 1
      AND FECHA_INIC_DEPREC_3 IS NOT NULL;

    -- 2.2. Actualizar Dep_Acum_Inicio con el valor calculado para activos tipo 2
    -- Si ya tenía valor (activos con cálculo fiscal), mantenerlo
    UPDATE #ActivosCalculo
    SET Dep_Acum_Inicio = CASE
        WHEN Usa_Calculo_Tipo2 = 1 THEN ISNULL(Dep_Acum_Calculada, 0)
        ELSE Dep_Acum_Inicio
    END;

    -- 2.3. Reportar cuántos activos usaron cálculo tipo 2
    DECLARE @ActivosTipo2 INT;
    SELECT @ActivosTipo2 = COUNT(*)
    FROM #ActivosCalculo
    WHERE Usa_Calculo_Tipo2 = 1;

    PRINT 'Activos con cálculo tipo 2 (FECHA_INIC_DEPREC_3): ' + CAST(@ActivosTipo2 AS VARCHAR(10));

    -- 2.4. Calcular Depreciación Anual
    -- IMPORTANTE: Tasa_Anual está como entero (ej: 5 para 5%), dividir entre 100
    UPDATE #ActivosCalculo
    SET Dep_Anual = MOI * (Tasa_Anual / 100);

    -- 3. Calcular meses de uso al inicio del ejercicio
    UPDATE #ActivosCalculo
    SET Meses_Uso_Inicio_Ejercicio =
        CASE
            WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE)
            THEN 0
            ELSE DATEDIFF(MONTH, FECHA_COMPRA, CAST(CAST(@Año_Anterior AS VARCHAR(4)) + '-12-31' AS DATE)) + 1
        END;

    -- 4. Calcular meses hasta la mitad del periodo
    UPDATE #ActivosCalculo
    SET Meses_Hasta_Mitad_Periodo =
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
    -- CÁLCULO PARA TODOS LOS ACTIVOS EXTRANJEROS
    -- =============================================

    -- 6. Calcular Saldo por Deducir ISR al Inicio del Año
    UPDATE #ActivosCalculo
    SET Saldo_Inicio_Año = MOI - Dep_Acum_Inicio;

    -- 7. Calcular Depreciación Fiscal del Ejercicio
    -- USAR Tasa_Anual/12/100 para mayor precisión (no Tasa_Mensual con 6 decimales)
    UPDATE #ActivosCalculo
    SET Dep_Ejercicio = MOI * (Tasa_Anual / 12 / 100) * Meses_Hasta_Mitad_Periodo;

    -- 8. Calcular Monto Pendiente por Deducir
    UPDATE #ActivosCalculo
    SET Monto_Pendiente =
        CASE
            WHEN (Saldo_Inicio_Año - Dep_Ejercicio) < 0 THEN 0
            ELSE (Saldo_Inicio_Año - Dep_Ejercicio)
        END;

    -- 9. Calcular Proporción del Monto Pendiente
    UPDATE #ActivosCalculo
    SET Proporcion = (Monto_Pendiente / 12.0) * Meses_Uso_Ejercicio;

    -- 10. APLICAR REGLA DEL MAYOR (Proporción vs 10% MOI)
    UPDATE #ActivosCalculo
    SET Prueba_10Pct = MOI * 0.10,
        Valor_USD =
            CASE
                WHEN Proporcion > (MOI * 0.10) THEN Proporcion
                ELSE MOI * 0.10
            END,
        Aplica_Regla_10Pct =
            CASE
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
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'EXT-BAJA'
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'EXT-ANTES-JUN'
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'EXT-DESP-JUN'
                WHEN Aplica_Regla_10Pct = 1 THEN 'EXT-10PCT'
                ELSE 'EXT-NORMAL'
            END,
        Descripcion_Ruta =
            CASE
                WHEN FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo THEN 'Activo dado de baja en ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA >= CAST(CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' AS DATE) AND FECHA_COMPRA <= @Fecha_30_Junio THEN 'Activo adquirido antes de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN FECHA_COMPRA > @Fecha_30_Junio THEN 'Activo adquirido después de junio ' + CAST(@Año_Calculo AS VARCHAR(10))
                WHEN Aplica_Regla_10Pct = 1 THEN 'Aplicó regla 10% MOI (Art 182 LISR)'
                ELSE 'Activo en uso normal en ' + CAST(@Año_Calculo AS VARCHAR(10))
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
        Tasa_Anual,
        Tasa_Mensual,
        Dep_Anual,
        Dep_Acum_Inicio,
        INPCCompra,
        INPCUtilizado,
        Meses_Uso_Inicio_Ejercicio,
        Meses_Uso_Hasta_Mitad_Periodo,
        Meses_Uso_En_Ejercicio,
        Saldo_Inicio_Año,
        Dep_Fiscal_Ejercicio,
        Monto_Pendiente,
        Proporcion,
        Prueba_10_Pct_MOI,
        Aplica_10_Pct,
        Valor_Reportable_USD,
        Tipo_Cambio_30_Junio,
        Valor_Reportable_MXN,
        Fecha_Adquisicion,
        Fecha_Baja,
        Fecha_Calculo,
        Version_SP
    )
    SELECT
        ID_Staging,
        @ID_Compania,
        ID_NUM_ACTIVO,
        @Año_Calculo,
        'Extranjero',
        ID_PAIS,
        Ruta_Calculo,
        Descripcion_Ruta,
        MOI,
        Tasa_Anual,
        Tasa_Mensual,
        Dep_Anual,
        Dep_Acum_Inicio,
        NULL,  -- INPCCompra: No aplica para extranjeros
        NULL,  -- INPCUtilizado: No aplica para extranjeros
        Meses_Uso_Inicio_Ejercicio,
        Meses_Hasta_Mitad_Periodo,
        Meses_Uso_Ejercicio,
        Saldo_Inicio_Año,
        Dep_Ejercicio,
        Monto_Pendiente,
        Proporcion,
        Prueba_10Pct,
        Aplica_Regla_10Pct,
        Valor_USD,
        @TipoCambio_30Jun,
        Valor_MXN,
        FECHA_COMPRA,
        FECHA_BAJA,
        GETDATE(),
        'v4.9-LIMPIO'
    FROM #ActivosCalculo
    WHERE Valor_MXN IS NOT NULL;

    SET @RegistrosProcesados = @@ROWCOUNT;

    -- 14. Mostrar resumen
    DECLARE @TotalValorReportable DECIMAL(18,2);
    DECLARE @ActivosRegla10Pct INT;

    SELECT
        @TotalValorReportable = SUM(Valor_MXN),
        @ActivosRegla10Pct = SUM(CAST(Aplica_Regla_10Pct AS INT))
    FROM #ActivosCalculo;

    PRINT '';
    PRINT '========================================';
    PRINT 'RESUMEN DE CÁLCULO v4.7';
    PRINT '========================================';
    PRINT 'Registros procesados: ' + CAST(@RegistrosProcesados AS VARCHAR(10));
    PRINT 'Activos con cálculo tipo 2: ' + CAST(@ActivosTipo2 AS VARCHAR(10));
    PRINT 'Total valor reportable (MXN): $' + FORMAT(@TotalValorReportable, 'N2');
    PRINT 'Activos con regla 10% MOI: ' + CAST(@ActivosRegla10Pct AS VARCHAR(10));
    PRINT '';

    -- Mostrar detalle por ruta
    SELECT
        Ruta_Calculo,
        COUNT(*) AS Cantidad,
        SUM(Valor_MXN) AS Total_MXN,
        SUM(CASE WHEN Aplica_Regla_10Pct = 1 THEN 1 ELSE 0 END) AS Con_Regla_10Pct
    FROM #ActivosCalculo
    GROUP BY Ruta_Calculo
    ORDER BY Ruta_Calculo;

    -- Limpiar
    DROP TABLE #ActivosCalculo;

    PRINT '';
    PRINT 'Cálculo completado exitosamente';
    PRINT '========================================';

    RETURN @RegistrosProcesados;
END
GO

PRINT 'Stored procedure sp_Calcular_RMF_Activos_Extranjeros v4.9-LIMPIO creado exitosamente';
GO

-- =============================================
-- DOCUMENTACIÓN DE CAMBIOS v4.7
-- =============================================
/*
CAMBIOS PRINCIPALES EN v4.7:

1. CAMBIO DE ARQUITECTURA - PROCESAMIENTO POR AÑO:
   - Eliminado parámetro @Lote_Importacion del stored procedure
   - Filtro cambiado de "s.Lote_Importacion = @Lote_Importacion" a "s.Año_Calculo = @Año_Calculo"
   - Ahora procesa TODOS los activos del año/compañía en Staging_Activo
   - El ETL limpia datos anteriores del mismo año/compañía antes de insertar nuevos

2. MANTIENE CORRECCIÓN CRÍTICA v4.6 - PREVENCIÓN DE DUPLICADOS:
   - Mantiene filtro ID_PAIS > 1 estrictamente
   - NO procesa activos mexicanos (ID_PAIS=1) aunque tengan ManejaUSGAAP='S'
   - Activos mexicanos con contabilidad USGAAP se procesan en SP Nacionales
   - Elimina duplicación de cálculos

3. REGLA DE NEGOCIO:
   - Activos EXTRANJEROS: ID_PAIS > 1, usan COSTO_REVALUADO (USD), este SP
   - Activos NACIONALES con USGAAP: ID_PAIS=1, usan CostoMXN, SP Nacionales
   - La bandera ManejaUSGAAP no determina qué SP usar, solo el ID_PAIS

4. MANTIENE FUNCIONALIDAD:
   - Cálculo automático tipo 2 con FECHA_INIC_DEPREC_3
   - Función fn_CalcularDepFiscal_Tipo2 para depreciación
   - Tipo de cambio del 31-Dic año anterior para cálculos tipo 2
   - Regla del mayor (Proporción vs 10% MOI)

NOTA IMPORTANTE:
- El Lote_Calculo se mantiene para historial/auditoría pero ya no se usa Lote_Importacion
- ETL debe limpiar Staging_Activo antes de cada importación (mismo año/compañía)
- NO MODIFICAR el filtro ID_PAIS > 1 sin revisar el impacto en el SP de Nacionales
*/
