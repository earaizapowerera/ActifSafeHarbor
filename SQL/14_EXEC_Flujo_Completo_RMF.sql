-- =============================================
-- Script: Flujo Completo de Cálculo RMF
-- Descripción: Ejecuta el proceso completo de ETL + Fiscal Simulado + Safe Harbor
-- Uso: Modificar parámetros y ejecutar
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- PARÁMETROS DE EJECUCIÓN
-- =============================================

DECLARE @ID_Compania INT = 1;  -- Cambiar según compañía a procesar
DECLARE @Año_Calculo INT = 2024;  -- Cambiar según año fiscal

DECLARE @Lote_Importacion UNIQUEIDENTIFIER;
DECLARE @ConnectionString NVARCHAR(500);

PRINT '';
PRINT '##############################################';
PRINT '# FLUJO COMPLETO DE CÁLCULO RMF';
PRINT '##############################################';
PRINT 'Compañía ID: ' + CAST(@ID_Compania AS VARCHAR);
PRINT 'Año Fiscal: ' + CAST(@Año_Calculo AS VARCHAR);
PRINT 'Fecha: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '';

-- =============================================
-- PASO 1: ETL - IMPORTAR ACTIVOS
-- =============================================

PRINT '';
PRINT '===========================================';
PRINT 'PASO 1: ETL - IMPORTACIÓN DE ACTIVOS';
PRINT '===========================================';
PRINT '';

EXEC dbo.sp_ETL_Importar_Activos_Completo
    @ID_Compania = @ID_Compania,
    @Año_Calculo = @Año_Calculo,
    @Usuario = 'Sistema';

-- Obtener el lote de importación recién creado
SELECT TOP 1
    @Lote_Importacion = Lote_Importacion
FROM dbo.Staging_Activo
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
ORDER BY Fecha_Importacion DESC;

PRINT 'Lote de importación: ' + CAST(@Lote_Importacion AS VARCHAR(50));
PRINT '';

-- =============================================
-- PASO 2: CÁLCULO FISCAL SIMULADO
-- =============================================

PRINT '';
PRINT '===========================================';
PRINT 'PASO 2: CÁLCULO FISCAL SIMULADO';
PRINT '===========================================';
PRINT 'Para activos con FLG_NOCAPITALIZABLE_3=''S'' y sin fiscal';
PRINT '';

-- Obtener connection string
SELECT @ConnectionString = ConnectionString_Actif
FROM dbo.ConfiguracionCompania
WHERE ID_Compania = @ID_Compania;

EXEC dbo.sp_Calcular_Fiscal_Simulado
    @ID_Compania = @ID_Compania,
    @Año_Calculo = @Año_Calculo,
    @Lote_Importacion = @Lote_Importacion,
    @ConnectionString_Actif = @ConnectionString;

-- =============================================
-- PASO 3: CÁLCULO RMF SAFE HARBOR
-- =============================================

PRINT '';
PRINT '===========================================';
PRINT 'PASO 3: CÁLCULO RMF SAFE HARBOR';
PRINT '===========================================';
PRINT 'Cálculo del valor reportable para todos los activos';
PRINT '';

EXEC dbo.sp_Calcular_RMF_Safe_Harbor
    @ID_Compania = @ID_Compania,
    @Año_Calculo = @Año_Calculo,
    @Lote_Importacion = @Lote_Importacion;

-- =============================================
-- PASO 4: RESUMEN FINAL
-- =============================================

PRINT '';
PRINT '===========================================';
PRINT 'RESUMEN FINAL';
PRINT '===========================================';
PRINT '';

-- Estadísticas de Staging
SELECT
    'STAGING' AS Tabla,
    COUNT(*) AS Total_Registros,
    COUNT(CASE WHEN FLG_NOCAPITALIZABLE_2 = 'S' THEN 1 END) AS Con_Fiscal,
    COUNT(CASE WHEN FLG_NOCAPITALIZABLE_3 = 'S' THEN 1 END) AS Con_USGAAP,
    COUNT(CASE WHEN FLG_NOCAPITALIZABLE_3 = 'S' AND ISNULL(FLG_NOCAPITALIZABLE_2, 'N') <> 'S' THEN 1 END) AS Solo_USGAAP_Sin_Fiscal,
    COUNT(CASE WHEN ID_PAIS > 1 THEN 1 END) AS Extranjeros,
    COUNT(CASE WHEN ID_PAIS = 1 THEN 1 END) AS Mexicanos
FROM dbo.Staging_Activo
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
  AND Lote_Importacion = @Lote_Importacion;

-- Estadísticas de Fiscal Simulado
SELECT
    'FISCAL SIMULADO' AS Tabla,
    COUNT(*) AS Total_Calculados,
    SUM(Dep_Acum_Año_Anterior_Simulada) AS Total_Dep_Acum_Simulada,
    AVG(Tasa_Anual_Fiscal) AS Tasa_Promedio,
    MIN(Meses_Depreciados) AS Min_Meses,
    MAX(Meses_Depreciados) AS Max_Meses
FROM dbo.Calculo_Fiscal_Simulado
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo;

-- Estadísticas de Cálculo RMF
SELECT
    'CALCULO RMF' AS Tabla,
    Tipo_Activo,
    COUNT(*) AS Total_Activos,
    SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable,
    COUNT(CASE WHEN Aplica_10_Pct = 1 THEN 1 END) AS Con_Regla_10_Pct,
    AVG(Valor_Reportable_MXN) AS Promedio_Valor
FROM dbo.Calculo_RMF
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
GROUP BY Tipo_Activo;

-- Vista combinada: Activos con fiscal simulado vs fiscal real
SELECT
    'COMPARACION FISCAL' AS Reporte,
    s.ID_NUM_ACTIVO,
    s.ID_ACTIVO,
    s.DESCRIPCION,
    s.FLG_NOCAPITALIZABLE_2 AS Tiene_Fiscal,
    s.FLG_NOCAPITALIZABLE_3 AS Tiene_USGAAP,
    s.Dep_Acum_Inicio_Año AS Dep_Fiscal_Real,
    fs.Dep_Acum_Año_Anterior_Simulada AS Dep_Fiscal_Simulado,
    CASE
        WHEN s.FLG_NOCAPITALIZABLE_2 = 'S' THEN 'Usa Fiscal Real'
        WHEN fs.ID_Calculo_Fiscal_Simulado IS NOT NULL THEN 'Usa Fiscal Simulado'
        ELSE 'Sin Fiscal'
    END AS Tipo_Fiscal_Usado
FROM dbo.Staging_Activo s
LEFT JOIN dbo.Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
WHERE s.ID_Compania = @ID_Compania
  AND s.Año_Calculo = @Año_Calculo
  AND s.Lote_Importacion = @Lote_Importacion
  AND (s.FLG_NOCAPITALIZABLE_2 = 'S' OR s.FLG_NOCAPITALIZABLE_3 = 'S')
ORDER BY s.ID_NUM_ACTIVO;

PRINT '';
PRINT '##############################################';
PRINT '# FLUJO COMPLETO TERMINADO';
PRINT '##############################################';
PRINT '';

GO
