-- =============================================
-- Script: Tabla Calculo_Fiscal_Simulado
-- Descripción: Almacena cálculo fiscal simulado para activos que solo tienen USGAAP
-- Relación: 1 a 1 con Staging_Activo
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- 1. TABLA DE CÁLCULO FISCAL SIMULADO
-- =============================================

IF OBJECT_ID('dbo.Calculo_Fiscal_Simulado', 'U') IS NOT NULL
    DROP TABLE dbo.Calculo_Fiscal_Simulado;
GO

CREATE TABLE dbo.Calculo_Fiscal_Simulado (
    -- PK
    ID_Calculo_Fiscal_Simulado BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- FK a Staging_Activo (relación 1 a 1)
    ID_Staging BIGINT NOT NULL UNIQUE,

    -- Identificación del activo
    ID_Compania INT NOT NULL,
    ID_NUM_ACTIVO INT NOT NULL,
    Año_Calculo INT NOT NULL,

    -- Datos base para cálculo
    COSTO_REEXPRESADO DECIMAL(18,4) NOT NULL, -- USGAAP en moneda original
    ID_MONEDA INT NULL,
    Nombre_Moneda NVARCHAR(50) NULL,

    -- Conversión a pesos
    Tipo_Cambio_30_Junio DECIMAL(10,6) NOT NULL, -- Del año de cálculo
    Costo_Fiscal_Simulado_MXN DECIMAL(18,4) NOT NULL, -- COSTO_REEXPRESADO * TC

    -- Fechas de depreciación USGAAP
    FECHA_INIC_DEPREC_3 DATETIME NULL, -- Fecha inicio depreciación USGAAP

    -- Porcentaje fiscal
    ID_TIPO_ACTIVO INT NULL,
    ID_SUBTIPO_ACTIVO INT NULL,
    ID_TIPO_DEP INT NOT NULL DEFAULT 2, -- Siempre fiscal (2)
    Tasa_Anual_Fiscal DECIMAL(10,6) NULL,
    Tasa_Mensual_Fiscal DECIMAL(10,6) NULL,

    -- Cálculo de depreciación acumulada
    Fecha_Corte_Calculo DATE NOT NULL, -- Diciembre 31 del año anterior
    Meses_Depreciados INT NOT NULL, -- Desde FECHA_INIC_DEPREC_3 hasta Dic año anterior

    -- Resultado: Depreciación acumulada simulada
    Dep_Mensual_Simulada DECIMAL(18,4) NOT NULL,
    Dep_Acum_Año_Anterior_Simulada DECIMAL(18,4) NOT NULL, -- Campo objetivo principal

    -- Observaciones
    Observaciones NVARCHAR(500) NULL,

    -- Control
    Fecha_Calculo DATETIME NOT NULL DEFAULT GETDATE(),
    Lote_Calculo UNIQUEIDENTIFIER NOT NULL,
    Version_SP NVARCHAR(20) NOT NULL,

    -- FK
    CONSTRAINT FK_CalcFiscalSim_Staging FOREIGN KEY (ID_Staging)
        REFERENCES dbo.Staging_Activo(ID_Staging) ON DELETE CASCADE
);
GO

CREATE INDEX IX_CalcFiscalSim_Compania_Año ON dbo.Calculo_Fiscal_Simulado(ID_Compania, Año_Calculo);
CREATE INDEX IX_CalcFiscalSim_Activo ON dbo.Calculo_Fiscal_Simulado(ID_NUM_ACTIVO);
CREATE INDEX IX_CalcFiscalSim_Lote ON dbo.Calculo_Fiscal_Simulado(Lote_Calculo);
GO

PRINT 'Tabla Calculo_Fiscal_Simulado creada';
GO

-- =============================================
-- 2. AGREGAR CAMPOS A STAGING_ACTIVO
-- =============================================

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'FLG_NOCAPITALIZABLE_2'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD FLG_NOCAPITALIZABLE_2 NVARCHAR(1) NULL; -- 'S' = tiene fiscal

    PRINT 'Campo FLG_NOCAPITALIZABLE_2 agregado a Staging_Activo';
END
GO

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'FLG_NOCAPITALIZABLE_3'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD FLG_NOCAPITALIZABLE_3 NVARCHAR(1) NULL; -- 'S' = tiene USGAAP

    PRINT 'Campo FLG_NOCAPITALIZABLE_3 agregado a Staging_Activo';
END
GO

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'FECHA_INIC_DEPREC_3'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD FECHA_INIC_DEPREC_3 DATETIME NULL; -- Fecha inicio depreciación USGAAP

    PRINT 'Campo FECHA_INIC_DEPREC_3 agregado a Staging_Activo';
END
GO

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'COSTO_REEXPRESADO'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD COSTO_REEXPRESADO DECIMAL(18,4) NULL; -- Costo USGAAP

    PRINT 'Campo COSTO_REEXPRESADO agregado a Staging_Activo';
END
GO

IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Staging_Activo')
    AND name = 'Costo_Fiscal'
)
BEGIN
    ALTER TABLE dbo.Staging_Activo
    ADD Costo_Fiscal DECIMAL(18,4) NULL; -- COSTO_REVALUADO o COSTO_ADQUISICION

    PRINT 'Campo Costo_Fiscal agregado a Staging_Activo';
END
GO

PRINT '';
PRINT '===================================';
PRINT 'TABLA Y CAMPOS CREADOS EXITOSAMENTE';
PRINT '===================================';
GO
