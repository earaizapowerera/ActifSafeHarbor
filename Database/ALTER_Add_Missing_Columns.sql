-- =============================================
-- Script: Agregar columnas faltantes a Calculo_RMF
-- Descripción: Agregar todas las columnas que tiene el Excel
-- =============================================

USE Actif_RMF;
GO

-- Agregar columnas que faltan para que el reporte tenga TODAS las columnas del Excel

-- Tasa anual (E en Excel)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Calculo_RMF') AND name = 'Tasa_Anual')
BEGIN
    ALTER TABLE dbo.Calculo_RMF
    ADD Tasa_Anual DECIMAL(10,6) NULL;
    PRINT 'Columna Tasa_Anual agregada';
END
GO

-- Depreciación anual (G en Excel = MOI * Tasa Anual)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Calculo_RMF') AND name = 'Dep_Anual')
BEGIN
    ALTER TABLE dbo.Calculo_RMF
    ADD Dep_Anual DECIMAL(18,4) NULL;
    PRINT 'Columna Dep_Anual agregada';
END
GO

-- Valor reportable en USD (Q en Excel, antes de convertir a MXN)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Calculo_RMF') AND name = 'Valor_Reportable_USD')
BEGIN
    ALTER TABLE dbo.Calculo_RMF
    ADD Valor_Reportable_USD DECIMAL(18,4) NULL;
    PRINT 'Columna Valor_Reportable_USD agregada';
END
GO

-- Fechas de adquisición y baja (para no tener que hacer JOIN con Staging en reportes)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Calculo_RMF') AND name = 'Fecha_Adquisicion')
BEGIN
    ALTER TABLE dbo.Calculo_RMF
    ADD Fecha_Adquisicion DATE NULL;
    PRINT 'Columna Fecha_Adquisicion agregada';
END
GO

IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Calculo_RMF') AND name = 'Fecha_Baja')
BEGIN
    ALTER TABLE dbo.Calculo_RMF
    ADD Fecha_Baja DATE NULL;
    PRINT 'Columna Fecha_Baja agregada';
END
GO

PRINT '';
PRINT '===================================';
PRINT 'COLUMNAS AGREGADAS EXITOSAMENTE';
PRINT '===================================';
GO
