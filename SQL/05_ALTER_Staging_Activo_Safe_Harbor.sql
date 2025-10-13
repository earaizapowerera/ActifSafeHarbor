-- Modificación de tabla Staging_Activo para Safe Harbor
-- Agrega Costo_Fiscal y elimina columnas INPC
-- Fecha: 2025-10-12
-- Versión: 1.0.0

USE Actif_RMF;
GO

-- 1. Agregar columna COSTO_REVALUADO (valor fiscal del activo)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'COSTO_REVALUADO')
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD COSTO_REVALUADO DECIMAL(18, 2) NULL;

    PRINT '✅ Columna COSTO_REVALUADO agregada a Staging_Activo';
END
ELSE
BEGIN
    PRINT 'ℹ️  Columna COSTO_REVALUADO ya existe';
END
GO

-- 2. Eliminar columnas INPC (ya no se extraen en ETL, se obtienen por separado)
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'INPC_Adquisicion')
BEGIN
    ALTER TABLE dbo.Staging_Activo
    DROP COLUMN INPC_Adquisicion;

    PRINT '✅ Columna INPC_Adquisicion eliminada de Staging_Activo';
END
ELSE
BEGIN
    PRINT 'ℹ️  Columna INPC_Adquisicion no existe';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'INPC_Mitad_Ejercicio')
BEGIN
    ALTER TABLE dbo.Staging_Activo
    DROP COLUMN INPC_Mitad_Ejercicio;

    PRINT '✅ Columna INPC_Mitad_Ejercicio eliminada de Staging_Activo';
END
ELSE
BEGIN
    PRINT 'ℹ️  Columna INPC_Mitad_Ejercicio no existe';
END
GO

-- 3. Corregir tipo de datos de FLG_PROPIO (debe ser VARCHAR, no INT)
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staging_Activo') AND name = 'FLG_PROPIO' AND system_type_id = 56) -- 56 = INT
BEGIN
    -- Primero eliminar el índice si existe
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Staging_Activo_FLG_Propio' AND object_id = OBJECT_ID('dbo.Staging_Activo'))
    BEGIN
        DROP INDEX IX_Staging_Activo_FLG_Propio ON dbo.Staging_Activo;
        PRINT '✅ Índice IX_Staging_Activo_FLG_Propio eliminado';
    END

    -- Cambiar tipo de columna
    ALTER TABLE dbo.Staging_Activo
    ALTER COLUMN FLG_PROPIO VARCHAR(1) NULL;
    PRINT '✅ Columna FLG_PROPIO convertida a VARCHAR(1)';

    -- Recrear el índice
    CREATE NONCLUSTERED INDEX IX_Staging_Activo_FLG_Propio
    ON dbo.Staging_Activo (FLG_PROPIO);
    PRINT '✅ Índice IX_Staging_Activo_FLG_Propio recreado';
END
ELSE
BEGIN
    PRINT 'ℹ️  Columna FLG_PROPIO ya es VARCHAR';
END
GO

-- 4. Mostrar estructura final de la tabla
PRINT '';
PRINT '📋 Estructura final de Staging_Activo:';
PRINT '======================================';

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Staging_Activo'
ORDER BY ORDINAL_POSITION;
GO

PRINT '';
PRINT '✅ Modificaciones completadas exitosamente';
PRINT 'ℹ️  Nota: INPC ahora se obtiene por separado mediante INPCService';
GO
