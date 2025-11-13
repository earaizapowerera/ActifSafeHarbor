-- =============================================
-- SCRIPT DE ACTUALIZACIÓN A v5.0 - SAFE HARBOR
-- Base de Datos: Actif_RMF
-- Fecha: 2025-11-13
-- Versión: v5.0-SafeHarbor
-- =============================================

USE Actif_RMF;
GO

PRINT '========================================';
PRINT 'INICIANDO ACTUALIZACIÓN A v5.0 - SAFE HARBOR';
PRINT '========================================';
PRINT '';

-- =============================================
-- PASO 1: AGREGAR COLUMNAS SAFE HARBOR
-- =============================================

PRINT 'PASO 1/2: Agregando columnas Safe Harbor a tabla Calculo_RMF';
PRINT '';

-- 1. INPC de Junio (fijo para Safe Harbor)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'INPC_SH_Junio')
BEGIN
    ALTER TABLE Calculo_RMF ADD INPC_SH_Junio DECIMAL(18,6) NULL;
    PRINT '✓ Columna INPC_SH_Junio agregada';
END
ELSE
    PRINT '- Columna INPC_SH_Junio ya existe (omitiendo)';

-- 2. Factor Safe Harbor (INPC Junio / INPC Compra)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Factor_SH')
BEGIN
    ALTER TABLE Calculo_RMF ADD Factor_SH DECIMAL(18,10) NULL;
    PRINT '✓ Columna Factor_SH agregada';
END
ELSE
    PRINT '- Columna Factor_SH ya existe (omitiendo)';

-- 3. Saldo Safe Harbor Actualizado
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Actualizado')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Actualizado DECIMAL(18,4) NULL;
    PRINT '✓ Columna Saldo_SH_Actualizado agregada';
END
ELSE
    PRINT '- Columna Saldo_SH_Actualizado ya existe (omitiendo)';

-- 4. Depreciación Safe Harbor Actualizada
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Dep_SH_Actualizada')
BEGIN
    ALTER TABLE Calculo_RMF ADD Dep_SH_Actualizada DECIMAL(18,4) NULL;
    PRINT '✓ Columna Dep_SH_Actualizada agregada';
END
ELSE
    PRINT '- Columna Dep_SH_Actualizada ya existe (omitiendo)';

-- 5. Valor Promedio Safe Harbor
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Valor_SH_Promedio')
BEGIN
    ALTER TABLE Calculo_RMF ADD Valor_SH_Promedio DECIMAL(18,4) NULL;
    PRINT '✓ Columna Valor_SH_Promedio agregada';
END
ELSE
    PRINT '- Columna Valor_SH_Promedio ya existe (omitiendo)';

-- 6. Proporción Safe Harbor
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Proporcion_SH')
BEGIN
    ALTER TABLE Calculo_RMF ADD Proporcion_SH DECIMAL(18,4) NULL;
    PRINT '✓ Columna Proporcion_SH agregada';
END
ELSE
    PRINT '- Columna Proporcion_SH ya existe (omitiendo)';

-- 7. Saldo Fiscal por Deducir Histórico (sin actualizar)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Fiscal_Hist')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Fiscal_Hist DECIMAL(18,4) NULL;
    PRINT '✓ Columna Saldo_SH_Fiscal_Hist agregada';
END
ELSE
    PRINT '- Columna Saldo_SH_Fiscal_Hist ya existe (omitiendo)';

-- 8. Saldo Fiscal por Deducir Actualizado
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Fiscal_Act')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Fiscal_Act DECIMAL(18,4) NULL;
    PRINT '✓ Columna Saldo_SH_Fiscal_Act agregada';
END
ELSE
    PRINT '- Columna Saldo_SH_Fiscal_Act ya existe (omitiendo)';

-- 9. Valor Reportable Safe Harbor (resultado final)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Valor_SH_Reportable')
BEGIN
    ALTER TABLE Calculo_RMF ADD Valor_SH_Reportable DECIMAL(18,4) NULL;
    PRINT '✓ Columna Valor_SH_Reportable agregada';
END
ELSE
    PRINT '- Columna Valor_SH_Reportable ya existe (omitiendo)';

PRINT '';
PRINT 'Columnas Safe Harbor verificadas/agregadas exitosamente';
PRINT '';

-- =============================================
-- PASO 2: ACTUALIZAR STORED PROCEDURE
-- =============================================

PRINT 'PASO 2/2: Actualizando Stored Procedure sp_Calcular_RMF_Activos_Nacionales';
PRINT '';

-- El SP se actualizará con el archivo separado sp_Calcular_RMF_Activos_Nacionales.sql
-- Este archivo solo verifica que exista

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Nacionales', 'P') IS NOT NULL
BEGIN
    PRINT '✓ Stored Procedure sp_Calcular_RMF_Activos_Nacionales existe';
    PRINT '  IMPORTANTE: Ejecutar archivo sp_Calcular_RMF_Activos_Nacionales.sql';
    PRINT '  para actualizar a v5.0';
END
ELSE
BEGIN
    PRINT '✗ ERROR: Stored Procedure sp_Calcular_RMF_Activos_Nacionales NO existe';
    PRINT '  Ejecutar archivo sp_Calcular_RMF_Activos_Nacionales.sql';
END

PRINT '';
PRINT '========================================';
PRINT 'ACTUALIZACIÓN DE BASE DE DATOS COMPLETADA';
PRINT '========================================';
PRINT '';
PRINT 'PRÓXIMOS PASOS:';
PRINT '1. Ejecutar: sp_Calcular_RMF_Activos_Nacionales.sql (actualizar SP a v5.0)';
PRINT '2. Desplegar aplicación web ActifRMF';
PRINT '3. Verificar: SELECT TOP 5 * FROM Calculo_RMF WHERE Valor_SH_Reportable IS NOT NULL';
PRINT '';
GO
