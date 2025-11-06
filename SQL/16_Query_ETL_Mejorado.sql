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
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' >= pd.FECHA_INICIO
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' <= ISNULL(pd.FECHA_FIN, '2100-12-31')

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
  AND (a.STATUS = 'A' OR (a.STATUS = 'B' AND YEAR(a.FECHA_BAJA) = @Año_Calculo))

  -- ⚠️ FILTRO DE PRUEBA - 86 activos hardcodeados para testing
  AND a.ID_NUM_ACTIVO IN (
      -- Compañía 188 - EXTRANJEROS ACTIVOS (10)
      44073, 44117, 44128, 44130, 44156,
      44159, 44161, 44169, 44172, 44402,

      -- Compañía 188 - EXTRANJEROS BAJA 2024 (2)
      160761,  -- Baja ene-2024
      204091,  -- Baja jul-2024

      -- Compañía 188 - EXTRANJEROS ALTA 2024 (2)
      2528041,  -- Alta ene-2024
      2532774,  -- Alta jul-2024

      -- Compañía 188 - EXTRANJEROS INICIO DEP 2023 (2)
      204304,  -- Inicio deprec 2023
      204220,  -- Inicio deprec 2023

      -- Compañía 188 - NACIONALES ACTIVOS (10)
      50847, 50855, 50893, 50894, 50899,
      50909, 50912, 50927, 50967, 50974,

      -- Compañía 188 - NACIONALES BAJA 2024 (2)
      192430,  -- Baja feb-2024
      201213,  -- Baja jul-2024

      -- Compañía 188 - NACIONALES ALTA 2024 (2)
      2530616,  -- Alta ene-2024
      2532664,  -- Alta jul-2024

      -- Compañía 188 - NACIONALES INICIO DEP 2023 (2)
      205229,  -- Inicio deprec 2023
      522282,  -- Inicio deprec 2023

      -- Compañía 122 - EXTRANJEROS ACTIVOS (10)
      107002, 107009, 107012, 107014, 107028,
      107036, 107045, 107055, 107057, 107069,

      -- Compañía 122 - EXTRANJEROS BAJA 2024 (2)
      122234,  -- Baja ene-2024
      122331,  -- Baja jul-2024

      -- Compañía 122 - EXTRANJEROS ALTA 2024 (2)
      2529304,  -- Alta ene-2024
      2543405,  -- Alta jul-2024

      -- Compañía 122 - EXTRANJEROS INICIO DEP 2023 (2)
      204411,  -- Inicio deprec 2023
      2537437,  -- Inicio deprec 2023

      -- Compañía 123 - NACIONALES ACTIVOS (10)
      110380, 110387, 110390, 110392, 110406,
      110414, 110423, 110433, 110435, 110447,

      -- Compañía 123 - NACIONALES BAJA 2024 (2)
      158224,  -- Baja ene-2024
      158456,  -- Baja ago-2024

      -- Compañía 123 - NACIONALES ALTA 2024 (2)
      2537738,  -- Alta ene-2024
      2543813,  -- Alta jul-2024

      -- Compañía 123 - NACIONALES INICIO DEP 2023 (2)
      204697,  -- Inicio deprec 2023
      204965,  -- Inicio deprec 2023

      -- Compañía 12 - EXTRANJEROS ACTIVOS (5)
      70590, 70600, 70616, 70620, 70640,

      -- Compañía 12 - EXTRANJEROS BAJA 2024 (2)
      93551,  -- Baja abr-2024
      83687,  -- Baja jul-2024

      -- Compañía 12 - EXTRANJEROS ALTA 2024 (2)
      216310,  -- Alta ene-2024
      218365,  -- Alta jul-2024

      -- Compañía 12 - EXTRANJEROS INICIO DEP 2023 (2)
      223318,  -- Inicio deprec 2023
      215903,  -- Inicio deprec 2023

      -- Compañía 12 - NACIONALES ACTIVOS (5)
      70001, 70002, 70003, 70004, 70005,

      -- Compañía 12 - NACIONALES BAJA 2024 (2)
      70157,   -- Baja mar-2024
      128908,  -- Baja jul-2024

      -- Compañía 12 - NACIONALES ALTA 2024 (2)
      223339,  -- Alta mar-2024
      220403,  -- Alta jul-2024

      -- Compañía 12 - NACIONALES INICIO DEP 2023 (2)
      206122,  -- Inicio deprec 2023
      206121   -- Inicio deprec 2023
  )

  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01')

ORDER BY a.ID_COMPANIA, a.ID_NUM_ACTIVO
