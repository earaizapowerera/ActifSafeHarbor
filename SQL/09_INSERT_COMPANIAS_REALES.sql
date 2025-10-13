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
DECLARE @QueryETL NVARCHAR(MAX) = N'
SELECT
    af.ID_NUM_ACTIVO,
    af.ID_ACTIVO,
    af.ID_TIPO_ACTIVO,
    af.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    af.DESCRIPCION,
    af.COSTO_ADQUISICION,
    af.Costo_Fiscal,
    af.ID_MONEDA,
    m.DESCRIPCION AS Nombre_Moneda,
    COALESCE(af.ID_PAIS, 1) AS ID_PAIS,
    COALESCE(p.DESCRIPCION, ''México'') AS Nombre_Pais,
    af.FECHA_COMPRA,
    af.FECHA_BAJA,
    af.FECHA_INIC_DEPREC,
    af.STATUS,
    af.FLG_PROPIO,
    td.TASA_ANUAL AS Tasa_Anual,
    td.TASA_MENSUAL AS Tasa_Mensual,
    COALESCE(dbo.fn_DepAcumInicio(@ID_COMPANIA, af.ID_NUM_ACTIVO, @AÑO_ANTERIOR), 0) AS Dep_Acum_Inicio_Año
FROM dbo.activo af
INNER JOIN dbo.tipo_activo ta ON af.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
LEFT JOIN dbo.moneda m ON af.ID_MONEDA = m.ID_MONEDA
LEFT JOIN dbo.pais p ON af.ID_PAIS = p.ID_PAIS
LEFT JOIN dbo.tasa_deprec td ON af.ID_TIPO_ACTIVO = td.ID_TIPO_ACTIVO
WHERE af.ID_COMPANIA = @ID_COMPANIA
  AND af.FLG_PROPIO = 0
  AND (af.FECHA_COMPRA < DATEADD(YEAR, 1, DATEFROMPARTS(@AÑO_CALCULO, 1, 1))
       OR af.FECHA_COMPRA IS NULL)
  AND (af.FECHA_BAJA >= DATEFROMPARTS(@AÑO_CALCULO, 1, 1)
       OR af.FECHA_BAJA IS NULL)
ORDER BY af.ID_NUM_ACTIVO';

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
