-- =============================================
-- Insertar Compañías con IDs Reales
-- Coincide con IDs de la base origen (actif_web_cima_dev)
-- ELIMINA las compañías con IDs incorrectos (1, 2, 3)
-- CREA las compañías con IDs correctos (123, 188)
-- =============================================

PRINT '=============================================';
PRINT 'Configurando Compañías con IDs Reales';
PRINT '=============================================';
GO

-- =============================================
-- PASO 1: INSERTAR COMPAÑÍAS CON IDS CORRECTOS
-- =============================================

PRINT '';
PRINT 'Insertando compañías con IDs correctos (123, 188)...';
GO

-- Eliminar compañías si ya existen
DELETE FROM dbo.ConfiguracionCompania WHERE ID_Compania IN (123, 188);

-- Query ETL estándar para compañías Actif
-- Calcula tasa desde NUM_ANOS_DEPRECIAR
-- Incluye JOINs a calculo e INPC2
-- Sin filtrar por FLG_PROPIO
DECLARE @QueryETL NVARCHAR(MAX) = N'
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    a.Costo_Fiscal,
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC,
    a.STATUS,
    a.FLG_PROPIO,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR)
         ELSE 0
    END AS Tasa_Anual,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR / 12.0)
         ELSE 0
    END AS Tasa_Mensual,
    ISNULL(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año,
    inpc_adq.Indice AS INPC_Adquisicion,
    inpc_mitad.Indice AS INPC_Mitad_Ejercicio
FROM activo a
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA
INNER JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_COMPANIA = @ID_COMPANIA
    AND c.ID_ANO = @AÑO_ANTERIOR
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
LEFT JOIN INPC2 inpc_adq
    ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
    AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
    AND inpc_adq.Id_Pais = 1
LEFT JOIN INPC2 inpc_mitad
    ON inpc_mitad.Anio = @AÑO_CALCULO
    AND inpc_mitad.Mes = 6
    AND inpc_mitad.Id_Pais = 1
WHERE a.ID_COMPANIA = @ID_COMPANIA
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@AÑO_CALCULO AS VARCHAR) + ''-12-31'')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@AÑO_CALCULO AS VARCHAR) + ''-01-01'')
  AND ISNULL(pd.NUM_ANOS_DEPRECIAR, 0) > 0
ORDER BY a.ID_NUM_ACTIVO';

-- Insertar Compañía 123 (CIMA)
-- Nota: ID_Compania NO es identity, solo ID_Configuracion lo es
INSERT INTO dbo.ConfiguracionCompania (
    ID_Compania,
    Nombre_Compania,
    Nombre_Corto,
    ConnectionString_Actif,
    Query_ETL,
    Activo,
    UsuarioCreacion
)
VALUES (
    123,
    'CIMA',
    'CIMA',
    'Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;',
    @QueryETL,
    1,
    'Sistema'
);

-- Insertar Compañía 188
INSERT INTO dbo.ConfiguracionCompania (
    ID_Compania,
    Nombre_Compania,
    Nombre_Corto,
    ConnectionString_Actif,
    Query_ETL,
    Activo,
    UsuarioCreacion
)
VALUES (
    188,
    'Compañia Prueba 188',
    'CP188',
    'Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;',
    @QueryETL,
    1,
    'Sistema'
);
GO

PRINT '✅ Compañías 123 y 188 insertadas correctamente';
GO

-- =============================================
-- PASO 3: VERIFICAR COMPAÑÍAS INSERTADAS
-- =============================================

PRINT '';
PRINT '=============================================';
PRINT 'Verificando compañías configuradas';
PRINT '=============================================';

SELECT
    ID_Compania,
    Nombre_Compania,
    Nombre_Corto,
    Activo,
    FechaCreacion
FROM dbo.ConfiguracionCompania
ORDER BY ID_Compania;
GO

PRINT '';
PRINT '=============================================';
PRINT 'Configuración completada';
PRINT 'Compañías creadas: 123 (CIMA), 188 (CP188)';
PRINT '=============================================';
GO
