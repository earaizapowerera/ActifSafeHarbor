-- =============================================
-- Script: Agregar columna FECHA_INIC_DEPREC_3 a Staging_Activo
-- Descripción:
--   Esta columna almacena la fecha de inicio de depreciación USGAAP (TIPO_DEP = 3)
--   que se usa para calcular la depreciación fiscal de activos tipo 2 (sin cálculo fiscal)
-- Fecha: 2025-10-13
-- =============================================

USE Actif_RMF;
GO

-- Verificar si la columna ya existe
IF NOT EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo'
      AND TABLE_NAME = 'Staging_Activo'
      AND COLUMN_NAME = 'FECHA_INIC_DEPREC_3'
)
BEGIN
    PRINT 'Agregando columna FECHA_INIC_DEPREC_3 a tabla Staging_Activo...';

    ALTER TABLE dbo.Staging_Activo
    ADD FECHA_INIC_DEPREC_3 DATE NULL;

    PRINT 'Columna FECHA_INIC_DEPREC_3 agregada exitosamente.';
END
ELSE
BEGIN
    PRINT 'La columna FECHA_INIC_DEPREC_3 ya existe en la tabla Staging_Activo.';
END
GO

-- Crear índice para mejorar performance de búsquedas
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Staging_Activo_FECHA_INIC_DEPREC_3'
      AND object_id = OBJECT_ID('dbo.Staging_Activo')
)
BEGIN
    PRINT 'Creando índice IX_Staging_Activo_FECHA_INIC_DEPREC_3...';

    CREATE INDEX IX_Staging_Activo_FECHA_INIC_DEPREC_3
    ON dbo.Staging_Activo(FECHA_INIC_DEPREC_3)
    WHERE FECHA_INIC_DEPREC_3 IS NOT NULL;

    PRINT 'Índice creado exitosamente.';
END
ELSE
BEGIN
    PRINT 'El índice IX_Staging_Activo_FECHA_INIC_DEPREC_3 ya existe.';
END
GO

PRINT '';
PRINT '===================================';
PRINT 'Script ejecutado exitosamente';
PRINT '===================================';
PRINT '';
PRINT 'NOTAS:';
PRINT '- FECHA_INIC_DEPREC_3 almacena la fecha de inicio de depreciación USGAAP';
PRINT '- Esta fecha se usa para calcular depreciación fiscal de activos TIPO_DEP = 2';
PRINT '- Para activos extranjeros, la depreciación calculada se multiplicará por TC';
PRINT '';
GO
