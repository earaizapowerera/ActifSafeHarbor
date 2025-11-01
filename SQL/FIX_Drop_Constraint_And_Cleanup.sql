-- =============================================
-- Fix: Drop UQ_Staging_Activo constraint and cleanup
-- =============================================

USE Actif_RMF;
GO

PRINT '==========================================';
PRINT 'Eliminando constraint UQ_Staging_Activo';
PRINT '==========================================';

-- Drop constraint if exists
IF EXISTS (
    SELECT 1
    FROM sys.key_constraints
    WHERE name = 'UQ_Staging_Activo'
      AND parent_object_id = OBJECT_ID('dbo.Staging_Activo')
)
BEGIN
    ALTER TABLE dbo.Staging_Activo DROP CONSTRAINT UQ_Staging_Activo;
    PRINT 'Constraint UQ_Staging_Activo eliminado';
END
ELSE
BEGIN
    PRINT 'Constraint UQ_Staging_Activo no existe (ya fue eliminado)';
END
GO

PRINT '';
PRINT '==========================================';
PRINT 'Limpiando datos de ejecución fallida';
PRINT '==========================================';

-- Limpiar staging de company 122, año 2024
DELETE FROM Staging_Activo
WHERE ID_Compania = 122
  AND Año_Calculo = 2024;

PRINT 'Registros eliminados: ' + CAST(@@ROWCOUNT AS VARCHAR);
GO

PRINT '';
PRINT '==========================================';
PRINT 'Verificando estado de la tabla';
PRINT '==========================================';

-- Ver constraints actuales
SELECT
    kc.name AS Constraint_Name,
    kc.type_desc AS Constraint_Type
FROM sys.key_constraints kc
WHERE kc.parent_object_id = OBJECT_ID('dbo.Staging_Activo');

-- Contar registros
SELECT
    ID_Compania,
    Año_Calculo,
    COUNT(*) AS Total_Registros
FROM Staging_Activo
WHERE ID_Compania = 122
GROUP BY ID_Compania, Año_Calculo;

PRINT '';
PRINT '==========================================';
PRINT 'Listo para re-ejecutar ETL';
PRINT '==========================================';
GO
