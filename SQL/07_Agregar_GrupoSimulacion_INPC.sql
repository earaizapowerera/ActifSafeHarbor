-- =============================================
-- Script: Agregar columna Id_GrupoSimulacion a INPC_Importado
-- Descripción: Permite filtrar y actualizar INPC por grupo de simulación
-- =============================================

USE Actif_RMF;
GO

-- Agregar columna Id_GrupoSimulacion si no existe
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.INPC_Importado')
    AND name = 'Id_GrupoSimulacion'
)
BEGIN
    ALTER TABLE dbo.INPC_Importado
    ADD Id_GrupoSimulacion INT NULL;

    PRINT 'Columna Id_GrupoSimulacion agregada a INPC_Importado';
END
ELSE
BEGIN
    PRINT 'Columna Id_GrupoSimulacion ya existe en INPC_Importado';
END
GO

-- Crear índice para mejorar consultas por grupo de simulación
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_INPC_GrupoSimulacion'
    AND object_id = OBJECT_ID('dbo.INPC_Importado')
)
BEGIN
    CREATE INDEX IX_INPC_GrupoSimulacion
    ON dbo.INPC_Importado(Id_GrupoSimulacion);

    PRINT 'Índice IX_INPC_GrupoSimulacion creado';
END
ELSE
BEGIN
    PRINT 'Índice IX_INPC_GrupoSimulacion ya existe';
END
GO

PRINT 'Script completado exitosamente';
GO
