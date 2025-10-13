-- =============================================
-- Insertar 5 Casos de Prueba del Excel
-- Para validar que SP v4 calcule correctamente
-- =============================================

DECLARE @Lote_Prueba UNIQUEIDENTIFIER = NEWID();
DECLARE @ID_Compania INT = 188;
DECLARE @Año_Calculo INT = 2024;

PRINT 'Lote de prueba: ' + CAST(@Lote_Prueba AS VARCHAR(50));
PRINT 'Insertando 5 casos del Excel...';

-- Limpiar casos anteriores de prueba
DELETE FROM Staging_Activo
WHERE ID_Compania = @ID_Compania
  AND ID_ACTIVO LIKE 'EXCEL-%';

-- CASO 1: Activo en Uso en 2024 (Fila 6 Excel)
-- Resultado esperado: $1,021,876.80 MXN
INSERT INTO Staging_Activo (
    ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
    ID_PAIS, FLG_PROPIO, COSTO_REVALUADO,
    Tasa_Anual, Tasa_Mensual,
    FECHA_COMPRA, FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    Año_Calculo, Lote_Importacion, Fecha_Importacion
)
VALUES (
    @ID_Compania, 9999001, 'EXCEL-CASO1', 'Caso 1: Activo en uso 2024',
    20, -- USA (ID_PAIS extranjero)
    1,  -- PROPIO
    100000.00,  -- MOI en USD
    0.08,       -- 8% anual
    0.006666667, -- Tasa mensual
    '2019-01-20', -- Fecha adquisición
    NULL,         -- No dado de baja
    40000.00,    -- Dep acumulada al inicio (60 meses * tasa)
    @Año_Calculo,
    @Lote_Prueba,
    GETDATE()
);

-- CASO 2: Activo Adquirido en 2024 Antes de Junio (Fila 7 Excel)
-- Resultado esperado: $881,977 MXN
INSERT INTO Staging_Activo (
    ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
    ID_PAIS, FLG_PROPIO, COSTO_REVALUADO,
    Tasa_Anual, Tasa_Mensual,
    FECHA_COMPRA, FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    Año_Calculo, Lote_Importacion, Fecha_Importacion
)
VALUES (
    @ID_Compania, 9999002, 'EXCEL-CASO2', 'Caso 2: Adquirido antes de junio 2024',
    20, -- USA
    1,  -- PROPIO
    60000.00,   -- MOI en USD
    0.08,
    0.006666667,
    '2024-03-20', -- Marzo 2024
    NULL,
    0.00,        -- Sin depreciación previa (nuevo en 2024)
    @Año_Calculo,
    @Lote_Prueba,
    GETDATE()
);

-- CASO 3: Activo Adquirido Después de Junio (Fila 8 Excel)
-- Resultado esperado: $4,917,782.10 MXN
INSERT INTO Staging_Activo (
    ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
    ID_PAIS, FLG_PROPIO, COSTO_REVALUADO,
    Tasa_Anual, Tasa_Mensual,
    FECHA_COMPRA, FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    Año_Calculo, Lote_Importacion, Fecha_Importacion
)
VALUES (
    @ID_Compania, 9999003, 'EXCEL-CASO3', 'Caso 3: Adquirido después de junio 2024',
    20, -- USA
    1,  -- PROPIO
    550000.00,  -- MOI en USD
    0.08,
    0.006666667,
    '2024-07-20', -- Julio 2024
    NULL,
    0.00,
    @Año_Calculo,
    @Lote_Prueba,
    GETDATE()
);

-- CASO 4: Activo Dado de Baja (Fila 9 Excel)
-- Resultado esperado: $1,313,841.60 MXN
INSERT INTO Staging_Activo (
    ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
    ID_PAIS, FLG_PROPIO, COSTO_REVALUADO,
    Tasa_Anual, Tasa_Mensual,
    FECHA_COMPRA, FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    Año_Calculo, Lote_Importacion, Fecha_Importacion
)
VALUES (
    @ID_Compania, 9999004, 'EXCEL-CASO4', 'Caso 4: Dado de baja en 2024',
    20, -- USA
    1,  -- PROPIO
    200000.00,  -- MOI en USD
    0.08,
    0.006666667,
    '2018-08-20',  -- Agosto 2018
    '2024-08-20',  -- Baja en Agosto 2024
    86666.67,      -- 65 meses de depreciación
    @Año_Calculo,
    @Lote_Prueba,
    GETDATE()
);

-- CASO 5: Activo con Prueba 10% MOI (Fila 10 Excel)
-- Resultado esperado: $1,459,824 MXN (usa 10% porque proporción < 10%)
INSERT INTO Staging_Activo (
    ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
    ID_PAIS, FLG_PROPIO, COSTO_REVALUADO,
    Tasa_Anual, Tasa_Mensual,
    FECHA_COMPRA, FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    Año_Calculo, Lote_Importacion, Fecha_Importacion
)
VALUES (
    @ID_Compania, 9999005, 'EXCEL-CASO5', 'Caso 5: Prueba 10% MOI (Art 182)',
    20, -- USA
    1,  -- PROPIO
    800000.00,  -- MOI en USD
    0.08,
    0.006666667,
    '2012-01-20',  -- Enero 2012 (132 meses)
    NULL,
    704000.00,     -- 88% depreciado
    @Año_Calculo,
    @Lote_Prueba,
    GETDATE()
);

PRINT '';
PRINT '✓ 5 casos insertados exitosamente';
PRINT 'Lote: ' + CAST(@Lote_Prueba AS VARCHAR(50));
PRINT '';

-- Mostrar resumen
SELECT
    ID_ACTIVO,
    DESCRIPCION,
    COSTO_REVALUADO AS MOI_USD,
    FECHA_COMPRA,
    FECHA_BAJA,
    Dep_Acum_Inicio_Año,
    FLG_PROPIO
FROM Staging_Activo
WHERE Lote_Importacion = @Lote_Prueba
ORDER BY ID_NUM_ACTIVO;

-- Guardar el lote para ejecutar el SP
SELECT @Lote_Prueba AS Lote_Para_SP;
