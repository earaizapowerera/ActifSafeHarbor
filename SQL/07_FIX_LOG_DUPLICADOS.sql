-- =============================================
-- Script: Fix para prevenir duplicados en Log_Ejecucion_ETL
-- Descripción: Agrega unique constraint para Lote_Importacion + Tipo_Proceso
-- =============================================

USE Actif_RMF;
GO

PRINT 'Iniciando fix de duplicados en Log_Ejecucion_ETL...';
GO

-- =============================================
-- 1. LIMPIAR DUPLICADOS EXISTENTES
-- =============================================

-- Identificar y eliminar duplicados, manteniendo solo el registro más reciente
PRINT 'Limpiando duplicados existentes...';
GO

WITH DuplicadosCTE AS (
    SELECT
        ID_Log,
        ROW_NUMBER() OVER (
            PARTITION BY Lote_Importacion, Tipo_Proceso
            ORDER BY Fecha_Inicio DESC, ID_Log DESC
        ) AS RowNum
    FROM dbo.Log_Ejecucion_ETL
)
DELETE FROM DuplicadosCTE WHERE RowNum > 1;
GO

DECLARE @DeletedRows INT = @@ROWCOUNT;
PRINT 'Registros duplicados eliminados: ' + CAST(@DeletedRows AS VARCHAR(10));
GO

-- =============================================
-- 2. AGREGAR UNIQUE CONSTRAINT
-- =============================================

PRINT 'Agregando unique constraint...';
GO

-- Verificar si ya existe el constraint
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UQ_Log_Lote_TipoProceso'
    AND object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL')
)
BEGIN
    ALTER TABLE dbo.Log_Ejecucion_ETL
    ADD CONSTRAINT UQ_Log_Lote_TipoProceso
    UNIQUE (Lote_Importacion, Tipo_Proceso);

    PRINT 'Constraint UQ_Log_Lote_TipoProceso creado exitosamente';
END
ELSE
BEGIN
    PRINT 'Constraint UQ_Log_Lote_TipoProceso ya existe';
END
GO

-- =============================================
-- 3. VERIFICAR RESULTADO
-- =============================================

PRINT '';
PRINT 'Verificando resultado...';
GO

SELECT
    Tipo_Proceso,
    COUNT(*) AS Total_Registros,
    COUNT(DISTINCT Lote_Importacion) AS Lotes_Unicos
FROM dbo.Log_Ejecucion_ETL
GROUP BY Tipo_Proceso;
GO

PRINT '';
PRINT '===================================';
PRINT 'FIX COMPLETADO EXITOSAMENTE';
PRINT '===================================';
PRINT '';
PRINT 'NOTA: Ahora cada combinación de (Lote_Importacion, Tipo_Proceso) es única.';
PRINT 'No se podrán insertar duplicados en la tabla Log_Ejecucion_ETL.';
GO
