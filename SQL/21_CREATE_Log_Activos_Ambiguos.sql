-- ==========================================
-- Tabla: Log_Activos_Ambiguos
-- Descripción: Registra activos que tienen ambos costos
--              (COSTO_REEXPRESADO y COSTO_REVALUADO > 0)
--              para corrección manual
-- Versión: 1.0.0
-- ==========================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.Log_Activos_Ambiguos', 'U') IS NOT NULL
    DROP TABLE dbo.Log_Activos_Ambiguos;
GO

CREATE TABLE dbo.Log_Activos_Ambiguos (
    ID_Log BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Datos del activo
    ID_Staging BIGINT NOT NULL,
    ID_Compania INT NOT NULL,
    ID_NUM_ACTIVO INT NOT NULL,
    ID_ACTIVO NVARCHAR(50),
    DESCRIPCION NVARCHAR(500),

    -- Costos conflictivos
    COSTO_REEXPRESADO DECIMAL(18,4),  -- Slot USGAAP
    COSTO_REVALUADO DECIMAL(18,4),    -- Slot Fiscal

    -- Metadatos
    Lote_Calculo UNIQUEIDENTIFIER NOT NULL,
    Fecha_Deteccion DATETIME NOT NULL DEFAULT GETDATE(),
    Fecha_Corregido DATETIME NULL,
    Usuario_Correccion NVARCHAR(100) NULL,
    Estado NVARCHAR(20) DEFAULT 'Pendiente', -- Pendiente, Corregido, Ignorado

    -- Índices
    INDEX IX_Log_Activos_Ambiguos_Compania (ID_Compania, Estado),
    INDEX IX_Log_Activos_Ambiguos_Estado (Estado, Fecha_Deteccion)
);
GO

PRINT 'Tabla Log_Activos_Ambiguos creada exitosamente';
GO

-- ==========================================
-- Vista: vw_Activos_Ambiguos_Activos
-- Descripción: Muestra solo activos ambiguos pendientes
-- ==========================================

IF OBJECT_ID('dbo.vw_Activos_Ambiguos_Activos', 'V') IS NOT NULL
    DROP VIEW dbo.vw_Activos_Ambiguos_Activos;
GO

CREATE VIEW dbo.vw_Activos_Ambiguos_Activos AS
SELECT
    l.ID_Log,
    l.ID_Compania,
    c.Nombre AS Compania,
    l.ID_NUM_ACTIVO,
    l.ID_ACTIVO AS Placa,
    l.DESCRIPCION,
    l.COSTO_REEXPRESADO AS Costo_USGAAP,
    l.COSTO_REVALUADO AS Costo_Fiscal,
    l.Fecha_Deteccion,
    DATEDIFF(DAY, l.Fecha_Deteccion, GETDATE()) AS Dias_Pendiente,
    'ERROR: Activo con ambos costos - Debe corregirse en Actif origen' AS Estado
FROM dbo.Log_Activos_Ambiguos l
INNER JOIN dbo.Compania c ON l.ID_Compania = c.ID_Compania
WHERE l.Estado = 'Pendiente';
GO

PRINT 'Vista vw_Activos_Ambiguos_Activos creada exitosamente';
GO

-- ==========================================
-- Query útil: Obtener resumen de ambigüedad
-- ==========================================

PRINT '';
PRINT 'Query de ejemplo para ver activos ambiguos:';
PRINT '';
PRINT 'SELECT * FROM vw_Activos_Ambiguos_Activos ORDER BY Dias_Pendiente DESC;';
PRINT '';
