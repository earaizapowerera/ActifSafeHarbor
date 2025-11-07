-- =============================================
-- Tabla: ConfiguracionCompania_Deleted
-- Descripción: Tabla de auditoría para compañías eliminadas
-- Fecha: 2025-11-06
-- =============================================

USE Actif_RMF;
GO

-- Verificar si existe y eliminar
IF OBJECT_ID('dbo.ConfiguracionCompania_Deleted', 'U') IS NOT NULL
BEGIN
    PRINT 'Eliminando tabla existente ConfiguracionCompania_Deleted...'
    DROP TABLE dbo.ConfiguracionCompania_Deleted;
END
GO

-- Crear tabla ConfiguracionCompania_Deleted
CREATE TABLE dbo.ConfiguracionCompania_Deleted (
    ID_Deleted BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Columnas originales de ConfiguracionCompania
    ID_Configuracion INT NOT NULL,
    ID_Compania INT NOT NULL,
    Nombre_Compania NVARCHAR(200) NOT NULL,
    Nombre_Corto NVARCHAR(50) NOT NULL,
    ConnectionString_Actif NVARCHAR(500) NOT NULL,
    Activo BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME NOT NULL DEFAULT GETDATE(),
    FechaModificacion DATETIME NULL,
    UsuarioCreacion NVARCHAR(100) NULL,
    Query_ETL NVARCHAR(MAX) NULL,

    -- Columnas de auditoría (según trigger)
    Fecha_Eliminacion DATETIME NOT NULL DEFAULT GETDATE(),
    Tipo_Operacion NVARCHAR(50) NULL,  -- 'UPDATE', 'DELETE', etc.

    -- Índice para búsquedas
    INDEX IX_ConfigCompania_Deleted_IDCompania (ID_Compania),
    INDEX IX_ConfigCompania_Deleted_FechaEliminacion (FechaEliminacion)
);
GO

PRINT '✅ Tabla ConfiguracionCompania_Deleted creada exitosamente';
PRINT '';
PRINT 'Estructura:';
PRINT '  - ID_Deleted: IDENTITY(1,1) PRIMARY KEY';
PRINT '  - Columnas originales de ConfiguracionCompania (10 campos)';
PRINT '  - Fecha_Eliminacion: Fecha de eliminación (sin tilde)';
PRINT '  - Tipo_Operacion: UPDATE, DELETE, etc.';
PRINT '';
PRINT 'Compatible con triggers:';
PRINT '  - trg_ConfiguracionCompania_Update_Backup';
PRINT '  - trg_ConfiguracionCompania_Delete_Backup';
GO
