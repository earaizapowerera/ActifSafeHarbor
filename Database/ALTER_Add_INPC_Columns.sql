-- =============================================
-- Agregar columnas INPC Mitad Ejercicio e INPC Mitad Periodo
-- Para mostrar en reporte Excel
-- =============================================

USE Actif_RMF;
GO

-- Verificar si las columnas ya existen antes de agregarlas
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'Calculo_RMF'
    AND COLUMN_NAME = 'INPC_Mitad_Ejercicio'
)
BEGIN
    ALTER TABLE Calculo_RMF
    ADD INPC_Mitad_Ejercicio DECIMAL(18,6) NULL;

    PRINT 'Columna INPC_Mitad_Ejercicio agregada exitosamente';
END
ELSE
BEGIN
    PRINT 'Columna INPC_Mitad_Ejercicio ya existe';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'Calculo_RMF'
    AND COLUMN_NAME = 'INPC_Mitad_Periodo'
)
BEGIN
    ALTER TABLE Calculo_RMF
    ADD INPC_Mitad_Periodo DECIMAL(18,6) NULL;

    PRINT 'Columna INPC_Mitad_Periodo agregada exitosamente';
END
ELSE
BEGIN
    PRINT 'Columna INPC_Mitad_Periodo ya existe';
END
GO

PRINT '';
PRINT '========================================';
PRINT 'Campos INPC agregados exitosamente';
PRINT '========================================';
PRINT 'Nuevos campos:';
PRINT '  - INPC_Mitad_Ejercicio: INPC del 30 de junio del año de cálculo';
PRINT '  - INPC_Mitad_Periodo: INPC de la mitad del periodo de uso';
GO
