-- =============================================
-- Query ETL Mejorado con JOIN a porcentaje_depreciacion
-- Usa vigencia de fechas (FECHA_INICIO, FECHA_FIN)
-- Incluye activos con tasa 0% para nacionales
-- =============================================

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
    a.FECHA_INIC_DEPREC2 AS FECHA_INIC_DEPREC,  -- Usar Fiscal (Tipo 2) como default
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
    ISNULL(c_hist.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año

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
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' >= pd.FECHA_INICIO
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' <= ISNULL(pd.FECHA_FIN, '2100-12-31')

-- Join con depreciación histórica (Diciembre año anterior, Fiscal)
LEFT JOIN calculo c_hist
    ON c_hist.ID_NUM_ACTIVO = a.ID_NUM_ACTIVO
    AND c_hist.ID_COMPANIA = a.ID_COMPANIA
    AND c_hist.ID_ANO = @Año_Anterior
    AND c_hist.ID_MES = 12
    AND c_hist.ID_TIPO_DEP = 2

WHERE a.ID_COMPANIA = @ID_Compania
  AND (a.STATUS = 'A' OR (a.STATUS = 'B' AND YEAR(a.FECHA_BAJA) = @Año_Calculo))

  -- ⚠️ FILTRO DE PRUEBA - Activos hardcodeados para testing
  AND a.ID_NUM_ACTIVO IN (2963243,1040520,
      44073, 44117, 44128, 44130, 44156, 44159, 44161, 44169, 44172, 44402,
      160761, 204091, 2528041, 2532774, 204304, 204220,
      51484, 2963156, 205811, 43668,
      50847, 50855, 50893, 50894, 50899, 50909, 50912, 50927, 50967, 50974,
      192430, 201213, 2530616, 2532664, 205229, 522282,
      208312, 208313, 208314, 2963160, 85177,
      107002, 107009, 107012, 107014, 107028, 107036, 107045, 107055, 107057, 107069,
      122234, 122331, 2529304, 2543405, 204411, 2537437,
      110380, 110387, 110390, 110392, 110406, 110414, 110423, 110433, 110435, 110447,
      158224, 158456, 2537738, 2543813, 204697, 204965,
      70590, 70600, 70616, 70620, 70640, 93551, 83687, 216310, 218365, 223318, 215903,
      70001, 70002, 70003, 70004, 70005, 70157, 128908, 223339, 220403, 206122, 206121
  )

  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01')

ORDER BY a.ID_COMPANIA, a.ID_NUM_ACTIVO
