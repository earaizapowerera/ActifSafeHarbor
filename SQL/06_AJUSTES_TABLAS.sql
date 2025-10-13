-- =============================================
-- Script: Ajustes a las Tablas
-- Descripción: Renombrar y ajustar estructura según requerimientos
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- 1. RENOMBRAR TABLA DE CÁLCULO
-- =============================================

IF OBJECT_ID('dbo.Calculo_RMF', 'U') IS NOT NULL
BEGIN
    EXEC sp_rename 'dbo.Calculo_RMF', 'CalculoActivosNoPropios';
    PRINT 'Tabla renombrada: Calculo_RMF -> CalculoActivosNoPropios';
END
GO

-- =============================================
-- 2. AGREGAR CAMPO DE CONTROL EN STAGING
-- =============================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'ETL_Completado'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD ETL_Completado BIT NOT NULL DEFAULT 0;

    PRINT 'Campo ETL_Completado agregado a Staging_Activo';
END
GO

-- =============================================
-- 3. AGREGAR ÍNDICE PARA REPORTES
-- =============================================

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_CalculoActivosNoPropios_Staging'
    AND object_id = OBJECT_ID('dbo.CalculoActivosNoPropios')
)
BEGIN
    CREATE INDEX IX_CalculoActivosNoPropios_Staging
    ON dbo.CalculoActivosNoPropios(ID_Staging, Lote_Calculo);

    PRINT 'Índice IX_CalculoActivosNoPropios_Staging creado';
END
GO

-- =============================================
-- 4. CREAR TABLA DE CONTROL DE ETL POR COMPAÑÍA
-- =============================================

IF OBJECT_ID('dbo.Control_ETL_Compania', 'U') IS NOT NULL
    DROP TABLE dbo.Control_ETL_Compania;
GO

CREATE TABLE dbo.Control_ETL_Compania (
    ID_Control INT IDENTITY(1,1) PRIMARY KEY,
    ID_Compania INT NOT NULL,
    Año_Calculo INT NOT NULL,
    Lote_Importacion UNIQUEIDENTIFIER NOT NULL,

    Fecha_Inicio_ETL DATETIME NOT NULL,
    Fecha_Fin_ETL DATETIME NULL,
    Estado_ETL NVARCHAR(20) NOT NULL DEFAULT 'En Proceso',
    -- Estados: 'En Proceso', 'Completado', 'Error'

    Registros_Importados INT NULL,
    Duracion_Segundos INT NULL,
    Mensaje_Error NVARCHAR(MAX) NULL,

    Usuario NVARCHAR(100) NULL,

    -- Indicador de que este lote está "activo" para cálculos
    Es_Lote_Activo BIT NOT NULL DEFAULT 1,

    CONSTRAINT CHK_Control_Estado CHECK (Estado_ETL IN ('En Proceso', 'Completado', 'Error'))
);
GO

CREATE INDEX IX_Control_Compania_Año ON dbo.Control_ETL_Compania(ID_Compania, Año_Calculo);
CREATE INDEX IX_Control_Lote ON dbo.Control_ETL_Compania(Lote_Importacion);
GO

PRINT 'Tabla Control_ETL_Compania creada';
GO

PRINT '';
PRINT '===================================';
PRINT 'AJUSTES COMPLETADOS';
PRINT '===================================';
GO
