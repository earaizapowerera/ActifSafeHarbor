-- =============================================
-- Insertar Query ETL en ConfiguracionCompania
-- =============================================

USE Actif_RMF;
GO

-- Query base para todas las compañías (se puede personalizar por compañía después)
DECLARE @Query_ETL NVARCHAR(MAX) = N'
SELECT
    -- Identificación
    a.ID_COMPANIA,
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,

    -- Datos financieros base
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,
    a.COSTO_REEXPRESADO,
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,

    -- País
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,

    -- Fechas
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC,
    a.FECHA_INIC_DEPREC3,
    a.STATUS,

    -- Ownership
    a.FLG_PROPIO,

    -- Flags de tipo de depreciación
    a.FLG_NOCAPITALIZABLE_2 AS ManejaFiscal,
    a.FLG_NOCAPITALIZABLE_3 AS ManejaUSGAAP,

    -- Tasa de depreciación FISCAL - Desde JOIN vigente
    ISNULL(pd.PORC_SEGUNDO_ANO, 0) AS Tasa_Anual,

    -- Depreciación acumulada FISCAL del año ANTERIOR (Diciembre)
    ISNULL((
        SELECT TOP 1 c.ACUMULADO_HISTORICA
        FROM calculo c
        WHERE c.ID_NUM_ACTIVO = a.ID_NUM_ACTIVO
          AND c.ID_COMPANIA = a.ID_COMPANIA
          AND c.ID_ANO = @Año_Anterior
          AND c.ID_MES = 12
          AND c.ID_TIPO_DEP = 2
        ORDER BY c.ACUMULADO_HISTORICA DESC
    ), 0) AS Dep_Acum_Inicio_Año,

    -- INPC de adquisición (solo para mexicanos)
    inpc_adq.Indice AS INPC_Adquisicion,

    -- INPC de mitad del ejercicio (junio del año de cálculo)
    inpc_mitad.Indice AS INPC_Mitad_Ejercicio

FROM activo a

-- Join con tipo_activo
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

-- Join con país
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS

-- Join con moneda
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA

-- Join con porcentaje_depreciacion VIGENTE
-- Usa vigencia de fechas para evitar duplicados
LEFT JOIN porcentaje_depreciacion pd
    ON pd.ID_TIPO_ACTIVO = a.ID_TIPO_ACTIVO
    AND pd.ID_SUBTIPO_ACTIVO = a.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2  -- 2 = Fiscal
    -- Validar vigencia en el año de cálculo
    AND CAST(@Año_Calculo AS VARCHAR(4)) + ''-01-01'' >= pd.FECHA_INICIO
    AND CAST(@Año_Calculo AS VARCHAR(4)) + ''-01-01'' <= ISNULL(pd.FECHA_FIN, ''2100-12-31'')

-- INPC de adquisición (solo para mexicanos, ID_PAIS = 1)
LEFT JOIN INPC2 inpc_adq
    ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
    AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
    AND inpc_adq.Id_Pais = 1
    AND inpc_adq.Id_Grupo_Simulacion = 8

-- INPC de mitad del ejercicio (junio del año actual)
LEFT JOIN INPC2 inpc_mitad
    ON inpc_mitad.Anio = @Año_Calculo
    AND inpc_mitad.Mes = 6
    AND inpc_mitad.Id_Pais = 1
    AND inpc_mitad.Id_Grupo_Simulacion = 8

WHERE a.ID_COMPANIA = @ID_Compania
  AND (a.STATUS = ''A'' OR (a.STATUS = ''B'' AND YEAR(a.FECHA_BAJA) = @Año_Calculo))
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@Año_Calculo AS VARCHAR(4)) + ''-12-31'')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@Año_Calculo AS VARCHAR(4)) + ''-01-01'')

ORDER BY a.ID_COMPANIA, a.ID_NUM_ACTIVO
';

-- Actualizar ConfiguracionCompania con el query
UPDATE ConfiguracionCompania
SET Query_ETL = @Query_ETL,
    FechaModificacion = GETDATE()
WHERE ID_Compania IN (12, 122, 123, 188);

-- Verificar que se actualizó
SELECT
    ID_Compania,
    Nombre_Compania,
    Nombre_Corto,
    CASE
        WHEN Query_ETL IS NULL THEN 'SIN QUERY'
        WHEN LEN(Query_ETL) > 0 THEN 'QUERY CONFIGURADO (' + CAST(LEN(Query_ETL) AS VARCHAR(10)) + ' chars)'
        ELSE 'VACÍO'
    END AS Estado_Query,
    FechaModificacion
FROM ConfiguracionCompania
ORDER BY ID_Compania;

PRINT '';
PRINT '===================================';
PRINT 'Query ETL insertado en ConfiguracionCompania';
PRINT '===================================';
GO
