-- =============================================
-- Script: Renombrar campos y agregar costos separados
-- Descripción:
--   - Renombra FLG_NOCAPITALIZABLE_2 → ManejaFiscal
--   - Renombra FLG_NOCAPITALIZABLE_3 → ManejaUSGAAP
--   - Agrega CostoUSD y CostoMXN
-- =============================================

USE Actif_RMF;
GO

PRINT '=========================================='
PRINT 'RENOMBRANDO CAMPOS EN STAGING_ACTIVO'
PRINT '=========================================='
PRINT ''

-- =============================================
-- 1. RENOMBRAR FLG_NOCAPITALIZABLE_2 → ManejaFiscal
-- =============================================

IF EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'FLG_NOCAPITALIZABLE_2'
)
BEGIN
    EXEC sp_rename 'dbo.Staging_Activo.FLG_NOCAPITALIZABLE_2', 'ManejaFiscal', 'COLUMN';
    PRINT 'Campo FLG_NOCAPITALIZABLE_2 renombrado a ManejaFiscal';
END
ELSE
BEGIN
    PRINT 'Campo FLG_NOCAPITALIZABLE_2 no existe (ya fue renombrado?)';
END
GO

-- =============================================
-- 2. RENOMBRAR FLG_NOCAPITALIZABLE_3 → ManejaUSGAAP
-- =============================================

IF EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'FLG_NOCAPITALIZABLE_3'
)
BEGIN
    EXEC sp_rename 'dbo.Staging_Activo.FLG_NOCAPITALIZABLE_3', 'ManejaUSGAAP', 'COLUMN';
    PRINT 'Campo FLG_NOCAPITALIZABLE_3 renombrado a ManejaUSGAAP';
END
ELSE
BEGIN
    PRINT 'Campo FLG_NOCAPITALIZABLE_3 no existe (ya fue renombrado?)';
END
GO

-- =============================================
-- 3. AGREGAR CostoUSD
-- =============================================

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'CostoUSD'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD CostoUSD DECIMAL(18,4) NULL;
    PRINT 'Campo CostoUSD agregado';
END
ELSE
BEGIN
    PRINT 'Campo CostoUSD ya existe';
END
GO

-- =============================================
-- 4. AGREGAR CostoMXN
-- =============================================

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'CostoMXN'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD CostoMXN DECIMAL(18,4) NULL;
    PRINT 'Campo CostoMXN agregado';
END
ELSE
BEGIN
    PRINT 'Campo CostoMXN ya existe';
END
GO

-- =============================================
-- 5. MIGRAR DATOS EXISTENTES (si existen)
-- =============================================

-- Migrar de COSTO_REEXPRESADO a CostoUSD donde ManejaUSGAAP='S'
IF EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'COSTO_REEXPRESADO')
BEGIN
    UPDATE dbo.Staging_Activo
    SET CostoUSD = COSTO_REEXPRESADO
    WHERE ManejaUSGAAP = 'S'
      AND COSTO_REEXPRESADO IS NOT NULL
      AND CostoUSD IS NULL;

    PRINT 'Datos migrados de COSTO_REEXPRESADO a CostoUSD: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' registros';
END
GO

-- Migrar de Costo_Fiscal a CostoMXN donde ManejaFiscal='S'
IF EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'Costo_Fiscal')
BEGIN
    UPDATE dbo.Staging_Activo
    SET CostoMXN = Costo_Fiscal
    WHERE ManejaFiscal = 'S'
      AND Costo_Fiscal IS NOT NULL
      AND CostoMXN IS NULL;

    PRINT 'Datos migrados de Costo_Fiscal a CostoMXN: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' registros';
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'CAMPOS RENOMBRADOS Y AGREGADOS'
PRINT '=========================================='
PRINT ''

-- Mostrar estructura actualizada
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Staging_Activo'
  AND COLUMN_NAME IN ('ManejaFiscal', 'ManejaUSGAAP', 'CostoUSD', 'CostoMXN',
                      'FECHA_INIC_DEPREC_3', 'COSTO_REEXPRESADO', 'Costo_Fiscal')
ORDER BY COLUMN_NAME;
GO
