-- =============================================
-- ALTER TABLE: Agregar Columnas Safe Harbor
-- Tabla: Calculo_RMF
-- NO EJECUTAR hasta confirmar con usuario
-- =============================================

USE Actif_RMF;
GO

PRINT '========================================';
PRINT 'Agregando columnas SAFE HARBOR a Calculo_RMF';
PRINT '========================================';

-- 1. INPC de Junio (fijo para Safe Harbor)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'INPC_SH_Junio')
BEGIN
    ALTER TABLE Calculo_RMF ADD INPC_SH_Junio DECIMAL(18,6) NULL;
    PRINT 'Columna INPC_SH_Junio agregada';
END
ELSE
    PRINT 'Columna INPC_SH_Junio ya existe';

-- 2. Factor Safe Harbor (INPC Junio / INPC Compra)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Factor_SH')
BEGIN
    ALTER TABLE Calculo_RMF ADD Factor_SH DECIMAL(18,10) NULL;
    PRINT 'Columna Factor_SH agregada';
END
ELSE
    PRINT 'Columna Factor_SH ya existe';

-- 3. Saldo Safe Harbor Actualizado
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Actualizado')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Actualizado DECIMAL(18,4) NULL;
    PRINT 'Columna Saldo_SH_Actualizado agregada';
END
ELSE
    PRINT 'Columna Saldo_SH_Actualizado ya existe';

-- 4. Depreciación Safe Harbor Actualizada
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Dep_SH_Actualizada')
BEGIN
    ALTER TABLE Calculo_RMF ADD Dep_SH_Actualizada DECIMAL(18,4) NULL;
    PRINT 'Columna Dep_SH_Actualizada agregada';
END
ELSE
    PRINT 'Columna Dep_SH_Actualizada ya existe';

-- 5. Valor Promedio Safe Harbor
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Valor_SH_Promedio')
BEGIN
    ALTER TABLE Calculo_RMF ADD Valor_SH_Promedio DECIMAL(18,4) NULL;
    PRINT 'Columna Valor_SH_Promedio agregada';
END
ELSE
    PRINT 'Columna Valor_SH_Promedio ya existe';

-- 6. Proporción Safe Harbor
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Proporcion_SH')
BEGIN
    ALTER TABLE Calculo_RMF ADD Proporcion_SH DECIMAL(18,4) NULL;
    PRINT 'Columna Proporcion_SH agregada';
END
ELSE
    PRINT 'Columna Proporcion_SH ya existe';

-- 7. Saldo Fiscal por Deducir Histórico (sin actualizar)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Fiscal_Hist')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Fiscal_Hist DECIMAL(18,4) NULL;
    PRINT 'Columna Saldo_SH_Fiscal_Hist agregada';
END
ELSE
    PRINT 'Columna Saldo_SH_Fiscal_Hist ya existe';

-- 8. Saldo Fiscal por Deducir Actualizado
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Saldo_SH_Fiscal_Act')
BEGIN
    ALTER TABLE Calculo_RMF ADD Saldo_SH_Fiscal_Act DECIMAL(18,4) NULL;
    PRINT 'Columna Saldo_SH_Fiscal_Act agregada';
END
ELSE
    PRINT 'Columna Saldo_SH_Fiscal_Act ya existe';

-- 9. Valor Reportable Safe Harbor (resultado final)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Calculo_RMF') AND name = 'Valor_SH_Reportable')
BEGIN
    ALTER TABLE Calculo_RMF ADD Valor_SH_Reportable DECIMAL(18,4) NULL;
    PRINT 'Columna Valor_SH_Reportable agregada';
END
ELSE
    PRINT 'Columna Valor_SH_Reportable ya existe';

PRINT '';
PRINT '========================================';
PRINT 'Columnas Safe Harbor agregadas exitosamente';
PRINT '========================================';
PRINT '';
PRINT 'COLUMNAS AGREGADAS:';
PRINT '1. INPC_SH_Junio         - INPC de junio (fijo)';
PRINT '2. Factor_SH             - INPC Junio / INPC Compra';
PRINT '3. Saldo_SH_Actualizado  - Saldo × Factor SH';
PRINT '4. Dep_SH_Actualizada    - Depreciación × Factor SH';
PRINT '5. Valor_SH_Promedio     - Saldo - 50% Dep (SH)';
PRINT '6. Proporcion_SH         - Valor Prom × Meses/12';
PRINT '7. Saldo_SH_Fiscal_Hist  - Saldo fiscal histórico';
PRINT '8. Saldo_SH_Fiscal_Act   - Saldo fiscal actualizado';
PRINT '9. Valor_SH_Reportable   - Resultado final SH';
PRINT '';

GO
