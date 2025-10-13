-- =============================================
-- Tabla de Configuración para INPC
-- =============================================
USE Actif_RMF;
GO

-- Crear tabla de configuración INPC
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ConfiguracionINPC')
BEGIN
    CREATE TABLE dbo.ConfiguracionINPC
    (
        ID_Configuracion INT IDENTITY(1,1) PRIMARY KEY,
        Nombre_Configuracion NVARCHAR(100) NOT NULL,
        ConnectionString_INPC NVARCHAR(500) NOT NULL,
        Query_Actualizacion_INPC NVARCHAR(MAX) NOT NULL,
        Activo BIT NOT NULL DEFAULT 1,
        Fecha_Creacion DATETIME NOT NULL DEFAULT GETDATE(),
        Fecha_Modificacion DATETIME NULL,
        Usuario_Creacion NVARCHAR(50) NULL,
        Usuario_Modificacion NVARCHAR(50) NULL
    );

    PRINT 'Tabla ConfiguracionINPC creada exitosamente';
END
ELSE
BEGIN
    PRINT 'Tabla ConfiguracionINPC ya existe';
END
GO

-- Insertar configuración inicial de INPC
IF NOT EXISTS (SELECT * FROM dbo.ConfiguracionINPC WHERE ID_Configuracion = 1)
BEGIN
    INSERT INTO dbo.ConfiguracionINPC
        (Nombre_Configuracion, ConnectionString_INPC, Query_Actualizacion_INPC, Activo, Usuario_Creacion)
    VALUES
        (
            'INPC General',
            'Server=dbdev.powerera.com;Database=actif_web_CIMA_Dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;',
            'SELECT * FROM INPC2',
            1,
            'Sistema'
        );

    PRINT 'Configuración inicial de INPC insertada exitosamente';
END
ELSE
BEGIN
    PRINT 'Configuración de INPC ya existe';
END
GO

-- Crear tabla para almacenar INPC importado
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'INPC_Importado')
BEGIN
    CREATE TABLE dbo.INPC_Importado
    (
        ID_INPC BIGINT IDENTITY(1,1) PRIMARY KEY,
        Anio INT NOT NULL,
        Mes INT NOT NULL,
        Id_Pais INT NULL,
        Indice DECIMAL(18,6) NOT NULL,
        Fecha_Importacion DATETIME NOT NULL DEFAULT GETDATE(),
        Lote_Importacion UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_INPC_Anio_Mes UNIQUE (Anio, Mes)
    );

    PRINT 'Tabla INPC_Importado creada exitosamente';
END
ELSE
BEGIN
    PRINT 'Tabla INPC_Importado ya existe';
END
GO

PRINT 'Script de configuración INPC completado exitosamente';
GO
