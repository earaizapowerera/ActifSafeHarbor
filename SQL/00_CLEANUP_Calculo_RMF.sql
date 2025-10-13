-- =============================================
-- Script de limpieza para remover objetos huérfanos
-- =============================================

-- Drop constraint huérfana si existe (sin verificar la tabla)
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_Calculo_Staging')
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    SELECT @sql = 'ALTER TABLE ' + OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) + ' DROP CONSTRAINT FK_Calculo_Staging'
    FROM sys.foreign_keys
    WHERE name = 'FK_Calculo_Staging';

    IF @sql IS NOT NULL
        EXEC sp_executesql @sql;
END
GO

-- Drop tabla si existe
IF OBJECT_ID('dbo.Calculo_RMF', 'U') IS NOT NULL
    DROP TABLE dbo.Calculo_RMF;
GO
