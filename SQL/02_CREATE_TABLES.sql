-- =============================================
-- Script: Creación de Tablas para Actif_RMF
-- Descripción: Tablas de configuración, staging y resultados
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- 1. TABLA DE CONFIGURACIÓN DE COMPAÑÍAS
-- =============================================

IF OBJECT_ID('dbo.ConfiguracionCompania', 'U') IS NOT NULL
    DROP TABLE dbo.ConfiguracionCompania;
GO

CREATE TABLE dbo.ConfiguracionCompania (
    ID_Configuracion INT IDENTITY(1,1) PRIMARY KEY,
    ID_Compania INT NOT NULL,
    Nombre_Compania NVARCHAR(200) NOT NULL,
    Nombre_Corto NVARCHAR(50) NOT NULL, -- CIMA, GILL, LEARCORP

    -- Connection string a la base de datos Actif de origen
    ConnectionString_Actif NVARCHAR(500) NOT NULL,

    -- Query ETL personalizado para esta compañía
    Query_ETL NVARCHAR(MAX) NULL,

    -- Configuración adicional
    Activo BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME NOT NULL DEFAULT GETDATE(),
    FechaModificacion DATETIME NULL,
    UsuarioCreacion NVARCHAR(100) NULL,

    -- Índices
    CONSTRAINT UQ_ConfigCompania_IDCompania UNIQUE (ID_Compania),
    CONSTRAINT UQ_ConfigCompania_NombreCorto UNIQUE (Nombre_Corto)
);
GO

CREATE INDEX IX_ConfigCompania_Activo ON dbo.ConfiguracionCompania(Activo);
GO

PRINT 'Tabla ConfiguracionCompania creada';
GO

-- =============================================
-- 2. TABLA DE STAGING - ACTIVOS IMPORTADOS
-- =============================================

IF OBJECT_ID('dbo.Staging_Activo', 'U') IS NOT NULL
    DROP TABLE dbo.Staging_Activo;
GO

CREATE TABLE dbo.Staging_Activo (
    -- PK de staging
    ID_Staging BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Identificación de origen
    ID_Compania INT NOT NULL,
    ID_NUM_ACTIVO INT NOT NULL,
    ID_ACTIVO NVARCHAR(50) NULL, -- Placa

    -- Clasificación
    ID_TIPO_ACTIVO INT NULL,
    ID_SUBTIPO_ACTIVO INT NULL,
    Nombre_TipoActivo NVARCHAR(200) NULL,
    DESCRIPCION NVARCHAR(500) NULL,

    -- Datos financieros
    COSTO_ADQUISICION DECIMAL(18,4) NOT NULL,
    ID_MONEDA INT NULL,
    Nombre_Moneda NVARCHAR(50) NULL,

    -- Ubicación/País
    ID_PAIS INT NOT NULL,
    Nombre_Pais NVARCHAR(100) NULL,

    -- Fechas
    FECHA_COMPRA DATETIME NULL,
    FECHA_BAJA DATETIME NULL,
    FECHA_INICIO_DEP DATETIME NULL,
    STATUS NVARCHAR(10) NULL,

    -- Ownership
    FLG_PROPIO INT NULL, -- 0=NO propio, 1=Propio

    -- Depreciación
    Tasa_Anual DECIMAL(10,6) NULL,
    Tasa_Mensual DECIMAL(10,6) NULL,

    -- Depreciación acumulada al inicio del año
    Dep_Acum_Inicio_Año DECIMAL(18,4) NULL,

    -- INPC (solo para activos mexicanos)
    INPC_Adquisicion DECIMAL(18,6) NULL,
    INPC_Mitad_Ejercicio DECIMAL(18,6) NULL,

    -- Control ETL
    Año_Calculo INT NOT NULL,
    Fecha_Importacion DATETIME NOT NULL DEFAULT GETDATE(),
    Lote_Importacion UNIQUEIDENTIFIER NOT NULL,

    -- Índices
    CONSTRAINT UQ_Staging_Activo UNIQUE (ID_Compania, ID_NUM_ACTIVO, Año_Calculo, Lote_Importacion)
);
GO

CREATE INDEX IX_Staging_Activo_Compania_Año ON dbo.Staging_Activo(ID_Compania, Año_Calculo);
CREATE INDEX IX_Staging_Activo_Pais ON dbo.Staging_Activo(ID_PAIS);
CREATE INDEX IX_Staging_Activo_FLG_Propio ON dbo.Staging_Activo(FLG_PROPIO);
CREATE INDEX IX_Staging_Activo_Lote ON dbo.Staging_Activo(Lote_Importacion);
GO

PRINT 'Tabla Staging_Activo creada';
GO

-- =============================================
-- 3. TABLA DE RESULTADOS DE CÁLCULO
-- =============================================

-- Drop FK constraint first if it exists
IF OBJECT_ID('FK_Calculo_Staging', 'F') IS NOT NULL
    ALTER TABLE dbo.Calculo_RMF DROP CONSTRAINT FK_Calculo_Staging;
GO

IF OBJECT_ID('dbo.Calculo_RMF', 'U') IS NOT NULL
    DROP TABLE dbo.Calculo_RMF;
GO

CREATE TABLE dbo.Calculo_RMF (
    -- PK
    ID_Calculo BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Referencias
    ID_Staging BIGINT NOT NULL,
    ID_Compania INT NOT NULL,
    ID_NUM_ACTIVO INT NOT NULL,
    Año_Calculo INT NOT NULL,

    -- Clasificación del activo
    Tipo_Activo NVARCHAR(50) NOT NULL, -- 'Extranjero' o 'Mexicano'
    ID_PAIS INT NOT NULL,

    -- *** RUTA DE CÁLCULO ***
    Ruta_Calculo NVARCHAR(20) NOT NULL, -- Ej: '1.2.3'
    Descripcion_Ruta NVARCHAR(200) NOT NULL, -- Ej: 'Extranjero - Adquirido en año - Antes de junio'

    -- Datos de entrada
    MOI DECIMAL(18,4) NOT NULL,
    Tasa_Mensual DECIMAL(10,6) NOT NULL,
    Dep_Acum_Inicio DECIMAL(18,4) NOT NULL,

    -- Meses calculados
    Meses_Uso_Inicio_Ejercicio INT NOT NULL,
    Meses_Uso_Hasta_Mitad_Periodo INT NOT NULL,
    Meses_Uso_En_Ejercicio INT NOT NULL,

    -- Cálculos intermedios
    Saldo_Inicio_Año DECIMAL(18,4) NOT NULL,
    Dep_Fiscal_Ejercicio DECIMAL(18,4) NOT NULL,
    Monto_Pendiente DECIMAL(18,4) NULL, -- Para extranjeros
    Proporcion DECIMAL(18,4) NULL, -- Para extranjeros

    -- Regla 10% MOI (solo extranjeros)
    Prueba_10_Pct_MOI DECIMAL(18,4) NULL,
    Aplica_10_Pct BIT NULL,

    -- Actualización INPC (solo mexicanos)
    INPC_Adqu DECIMAL(18,6) NULL,
    INPC_Mitad_Ejercicio DECIMAL(18,6) NULL,
    INPC_Mitad_Periodo DECIMAL(18,6) NULL,
    Factor_Actualizacion_Saldo DECIMAL(10,6) NULL,
    Factor_Actualizacion_Dep DECIMAL(10,6) NULL,
    Saldo_Actualizado DECIMAL(18,4) NULL,
    Dep_Actualizada DECIMAL(18,4) NULL,
    Valor_Promedio DECIMAL(18,4) NULL,

    -- Tipo de cambio (solo extranjeros)
    Tipo_Cambio_30_Junio DECIMAL(10,6) NULL,

    -- *** RESULTADO FINAL ***
    Valor_Reportable_MXN DECIMAL(18,4) NOT NULL,

    -- Observaciones
    Observaciones NVARCHAR(500) NULL,

    -- Control
    Fecha_Calculo DATETIME NOT NULL DEFAULT GETDATE(),
    Lote_Calculo UNIQUEIDENTIFIER NOT NULL,
    Version_SP NVARCHAR(20) NOT NULL, -- Versión del stored procedure

    -- FK
    CONSTRAINT FK_Calculo_Staging FOREIGN KEY (ID_Staging)
        REFERENCES dbo.Staging_Activo(ID_Staging)
);
GO

CREATE INDEX IX_Calculo_Compania_Año ON dbo.Calculo_RMF(ID_Compania, Año_Calculo);
CREATE INDEX IX_Calculo_Ruta ON dbo.Calculo_RMF(Ruta_Calculo);
CREATE INDEX IX_Calculo_Lote ON dbo.Calculo_RMF(Lote_Calculo);
CREATE INDEX IX_Calculo_TipoActivo ON dbo.Calculo_RMF(Tipo_Activo);
GO

PRINT 'Tabla Calculo_RMF creada';
GO

-- =============================================
-- 4. TABLA DE CATÁLOGO DE RUTAS DE CÁLCULO
-- =============================================

IF OBJECT_ID('dbo.Catalogo_Rutas_Calculo', 'U') IS NOT NULL
    DROP TABLE dbo.Catalogo_Rutas_Calculo;
GO

CREATE TABLE dbo.Catalogo_Rutas_Calculo (
    Ruta_Calculo NVARCHAR(20) PRIMARY KEY,
    Descripcion_Corta NVARCHAR(100) NOT NULL,
    Descripcion_Larga NVARCHAR(500) NOT NULL,
    Tipo_Activo NVARCHAR(50) NOT NULL, -- 'Extranjero' o 'Mexicano'
    Nivel_1 NVARCHAR(50) NOT NULL, -- Ej: 'Extranjero'
    Nivel_2 NVARCHAR(50) NULL,     -- Ej: 'Existente', 'Nuevo', 'Baja'
    Nivel_3 NVARCHAR(50) NULL,     -- Ej: 'Antes Junio', 'Después Junio'
    Nivel_4 NVARCHAR(50) NULL,     -- Ej: 'Aplica 10% MOI'
    Activo BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME NOT NULL DEFAULT GETDATE()
);
GO

PRINT 'Tabla Catalogo_Rutas_Calculo creada';
GO

-- =============================================
-- 5. TABLA DE LOG DE EJECUCIÓN ETL
-- =============================================

IF OBJECT_ID('dbo.Log_Ejecucion_ETL', 'U') IS NOT NULL
    DROP TABLE dbo.Log_Ejecucion_ETL;
GO

CREATE TABLE dbo.Log_Ejecucion_ETL (
    ID_Log BIGINT IDENTITY(1,1) PRIMARY KEY,
    ID_Compania INT NOT NULL,
    Año_Calculo INT NOT NULL,
    Lote_Importacion UNIQUEIDENTIFIER NOT NULL,

    Tipo_Proceso NVARCHAR(50) NOT NULL, -- 'ETL', 'CALCULO'

    Fecha_Inicio DATETIME NOT NULL,
    Fecha_Fin DATETIME NULL,
    Duracion_Segundos INT NULL,

    Registros_Procesados INT NULL,
    Registros_Exitosos INT NULL,
    Registros_Error INT NULL,

    Estado NVARCHAR(20) NOT NULL, -- 'En Proceso', 'Completado', 'Error'
    Mensaje_Error NVARCHAR(MAX) NULL,

    Usuario NVARCHAR(100) NULL,

    CONSTRAINT CHK_Log_Estado CHECK (Estado IN ('En Proceso', 'Completado', 'Error'))
);
GO

CREATE INDEX IX_Log_Compania_Año ON dbo.Log_Ejecucion_ETL(ID_Compania, Año_Calculo);
CREATE INDEX IX_Log_Lote ON dbo.Log_Ejecucion_ETL(Lote_Importacion);
CREATE INDEX IX_Log_Estado ON dbo.Log_Ejecucion_ETL(Estado);
GO

PRINT 'Tabla Log_Ejecucion_ETL creada';
GO

-- =============================================
-- 6. TABLA DE TIPO DE CAMBIO
-- =============================================

IF OBJECT_ID('dbo.Tipo_Cambio', 'U') IS NOT NULL
    DROP TABLE dbo.Tipo_Cambio;
GO

CREATE TABLE dbo.Tipo_Cambio (
    ID_TipoCambio INT IDENTITY(1,1) PRIMARY KEY,
    Año INT NOT NULL,
    Fecha DATE NOT NULL,
    ID_Moneda INT NOT NULL, -- 2=USD, etc.
    Nombre_Moneda NVARCHAR(50) NOT NULL,
    Tipo_Cambio DECIMAL(10,6) NOT NULL,
    Fuente NVARCHAR(100) NULL, -- 'Banxico', 'Manual', etc.
    FechaRegistro DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT UQ_TipoCambio_Fecha_Moneda UNIQUE (Fecha, ID_Moneda)
);
GO

CREATE INDEX IX_TipoCambio_Año_Moneda ON dbo.Tipo_Cambio(Año, ID_Moneda);
GO

PRINT 'Tabla Tipo_Cambio creada';
GO

PRINT '';
PRINT '===================================';
PRINT 'TODAS LAS TABLAS CREADAS EXITOSAMENTE';
PRINT '===================================';
GO
