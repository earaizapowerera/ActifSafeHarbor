-- =============================================
-- Función: fn_CalcularDepFiscal_Tipo2
-- Descripción:
--   Calcula la depreciación fiscal acumulada para activos tipo 2 (sin cálculo fiscal)
--   usando la fecha de inicio de depreciación USGAAP (FECHA_INIC_DEPREC_3)
--
-- Parámetros:
--   @MOI: Monto Original de Inversión (COSTO_REVALUADO)
--   @Tasa_Mensual: Tasa de depreciación mensual
--   @Fecha_Inicio_Deprec_3: Fecha de inicio de depreciación USGAAP
--   @Año_Anterior: Año anterior al año de cálculo (Ej: 2024 si calculamos 2025)
--   @ID_PAIS: ID del país del activo
--   @Tipo_Cambio: Tipo de cambio al 31 de diciembre del año anterior (para extranjeros)
--
-- Retorna:
--   Depreciación fiscal acumulada al inicio del año de cálculo
--
-- Lógica:
--   1. Calcula meses transcurridos desde FECHA_INIC_DEPREC_3 hasta el 31 de diciembre del año anterior
--   2. Calcula depreciación: Meses_Transcurridos * Tasa_Mensual * MOI
--   3. Si la depreciación supera el MOI, limita al MOI
--   4. Para activos extranjeros (ID_PAIS > 1), multiplica por tipo de cambio
--
-- Fecha: 2025-10-13
-- =============================================

USE Actif_RMF;
GO

-- Eliminar función si ya existe
IF OBJECT_ID('dbo.fn_CalcularDepFiscal_Tipo2', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CalcularDepFiscal_Tipo2;
GO

CREATE FUNCTION dbo.fn_CalcularDepFiscal_Tipo2
(
    @MOI DECIMAL(18,4),
    @Tasa_Anual DECIMAL(18,6),
    @Fecha_Inicio_Deprec_3 DATE,
    @Año_Anterior INT,
    @ID_PAIS INT,
    @Tipo_Cambio DECIMAL(18,6)
)
RETURNS DECIMAL(18,4)
AS
BEGIN
    DECLARE @Depreciacion_Calculada DECIMAL(18,4) = 0;
    DECLARE @Fecha_Fin_Año_Anterior DATE;
    DECLARE @Meses_Transcurridos INT = 0;
    DECLARE @Tasa_Mensual_Calculada DECIMAL(18,10);

    -- Validar parámetros de entrada
    IF @MOI IS NULL OR @MOI <= 0
        RETURN 0;

    IF @Tasa_Anual IS NULL OR @Tasa_Anual <= 0
        RETURN 0;

    -- Calcular tasa mensual con mayor precisión (10 decimales)
    SET @Tasa_Mensual_Calculada = @Tasa_Anual / 12 / 100;

    IF @Fecha_Inicio_Deprec_3 IS NULL
        RETURN 0;

    IF @Año_Anterior IS NULL
        RETURN 0;

    -- Calcular fecha fin del año anterior (31 de diciembre)
    SET @Fecha_Fin_Año_Anterior = DATEFROMPARTS(@Año_Anterior, 12, 31);

    -- Validar que la fecha de inicio de depreciación sea anterior o igual al fin del año anterior
    IF @Fecha_Inicio_Deprec_3 > @Fecha_Fin_Año_Anterior
        RETURN 0;

    -- Calcular meses transcurridos desde inicio de depreciación hasta el 31 de diciembre del año anterior
    -- DATEDIFF(MONTH, ...) cuenta la diferencia de meses
    -- Agregamos 1 porque el mes de inicio también cuenta
    SET @Meses_Transcurridos = DATEDIFF(MONTH, @Fecha_Inicio_Deprec_3, @Fecha_Fin_Año_Anterior) + 1;

    -- Validar que los meses transcurridos sean positivos
    IF @Meses_Transcurridos <= 0
        RETURN 0;

    -- Calcular depreciación: Meses * Tasa_Mensual * MOI
    -- Usar tasa mensual calculada con mayor precisión
    SET @Depreciacion_Calculada = @Meses_Transcurridos * @Tasa_Mensual_Calculada * @MOI;

    -- Validar que la depreciación no supere el MOI (100% depreciado)
    IF @Depreciacion_Calculada > @MOI
        SET @Depreciacion_Calculada = @MOI;

    -- Para activos extranjeros (ID_PAIS > 1), multiplicar por tipo de cambio
    -- NOTA: El tipo de cambio debe ser del 31 de diciembre del año anterior
    IF @ID_PAIS > 1 AND @Tipo_Cambio IS NOT NULL AND @Tipo_Cambio > 0
    BEGIN
        SET @Depreciacion_Calculada = @Depreciacion_Calculada * @Tipo_Cambio;
    END

    RETURN @Depreciacion_Calculada;
END
GO

PRINT 'Función dbo.fn_CalcularDepFiscal_Tipo2 creada exitosamente';
GO

-- =============================================
-- PRUEBAS DE LA FUNCIÓN
-- =============================================

PRINT '';
PRINT '===================================';
PRINT 'PRUEBAS DE LA FUNCIÓN';
PRINT '===================================';
PRINT '';

-- Prueba 1: Activo mexicano (ID_PAIS = 1) con 12 meses de depreciación
DECLARE @Test1 DECIMAL(18,4);
SET @Test1 = dbo.fn_CalcularDepFiscal_Tipo2(
    100000,                          -- @MOI: $100,000
    0.0833333,                       -- @Tasa_Mensual: 10% anual / 12 = 0.833333% mensual
    '2024-01-01',                    -- @Fecha_Inicio_Deprec_3: 1 de enero 2024
    2024,                            -- @Año_Anterior: 2024
    1,                               -- @ID_PAIS: México
    NULL                             -- @Tipo_Cambio: No aplica para México
);
PRINT 'Prueba 1 - Activo mexicano con 12 meses:';
PRINT '  MOI: $100,000';
PRINT '  Tasa anual: 10% (0.833333% mensual)';
PRINT '  Meses: 12 (Ene 2024 - Dic 2024)';
PRINT '  Depreciación esperada: $10,000';
PRINT '  Depreciación calculada: $' + CAST(@Test1 AS VARCHAR(20));
PRINT '';

-- Prueba 2: Activo extranjero (ID_PAIS = 2) con 6 meses y tipo de cambio
DECLARE @Test2 DECIMAL(18,4);
SET @Test2 = dbo.fn_CalcularDepFiscal_Tipo2(
    50000,                           -- @MOI: $50,000 USD
    0.0416667,                       -- @Tasa_Mensual: 5% anual / 12 = 0.416667% mensual
    '2024-07-01',                    -- @Fecha_Inicio_Deprec_3: 1 de julio 2024
    2024,                            -- @Año_Anterior: 2024
    2,                               -- @ID_PAIS: USA (extranjero)
    20.50                            -- @Tipo_Cambio: $20.50 MXN por USD
);
PRINT 'Prueba 2 - Activo extranjero con 6 meses y TC:';
PRINT '  MOI: $50,000 USD';
PRINT '  Tasa anual: 5% (0.416667% mensual)';
PRINT '  Meses: 6 (Jul 2024 - Dic 2024)';
PRINT '  Tipo de cambio: $20.50 MXN/USD';
PRINT '  Depreciación esperada: $1,250 USD * 20.50 = $25,625 MXN';
PRINT '  Depreciación calculada: $' + CAST(@Test2 AS VARCHAR(20));
PRINT '';

-- Prueba 3: Activo con depreciación que supera el MOI (debe limitarse al MOI)
DECLARE @Test3 DECIMAL(18,4);
SET @Test3 = dbo.fn_CalcularDepFiscal_Tipo2(
    10000,                           -- @MOI: $10,000
    0.0833333,                       -- @Tasa_Mensual: 10% anual / 12 = 0.833333% mensual
    '2014-01-01',                    -- @Fecha_Inicio_Deprec_3: 10 años atrás
    2024,                            -- @Año_Anterior: 2024
    1,                               -- @ID_PAIS: México
    NULL                             -- @Tipo_Cambio: No aplica
);
PRINT 'Prueba 3 - Activo con depreciación que supera MOI:';
PRINT '  MOI: $10,000';
PRINT '  Tasa anual: 10% (0.833333% mensual)';
PRINT '  Meses: 120 (10 años)';
PRINT '  Depreciación calculada sin límite: $100,000';
PRINT '  Depreciación limitada al MOI: $' + CAST(@Test3 AS VARCHAR(20));
PRINT '';

-- Prueba 4: Fecha de inicio posterior al año anterior (debe retornar 0)
DECLARE @Test4 DECIMAL(18,4);
SET @Test4 = dbo.fn_CalcularDepFiscal_Tipo2(
    100000,                          -- @MOI: $100,000
    0.0833333,                       -- @Tasa_Mensual: 10% anual
    '2025-01-01',                    -- @Fecha_Inicio_Deprec_3: Posterior al año anterior
    2024,                            -- @Año_Anterior: 2024
    1,                               -- @ID_PAIS: México
    NULL                             -- @Tipo_Cambio: No aplica
);
PRINT 'Prueba 4 - Fecha inicio posterior al año anterior:';
PRINT '  Fecha inicio: 2025-01-01 (posterior a 2024-12-31)';
PRINT '  Depreciación esperada: $0';
PRINT '  Depreciación calculada: $' + CAST(@Test4 AS VARCHAR(20));
PRINT '';

PRINT '===================================';
PRINT 'PRUEBAS COMPLETADAS';
PRINT '===================================';
GO
