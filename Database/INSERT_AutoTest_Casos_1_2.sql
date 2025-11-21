-- =============================================
-- Insertar casos de prueba validados
-- Caso 1: Edificio totalmente depreciado
-- Caso 2: Vehículo totalmente depreciado
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- CASO 1: Edificio Totalmente Depreciado
-- Folio: 50847
-- Status: ✅ RevisadoOK
-- =============================================
INSERT INTO AutoTest (
    Numero_Caso, Nombre_Caso, ID_NUM_ACTIVO, ID_Compania, Año_Calculo,
    -- Datos básicos
    MOI_Esperado, Tasa_Anual_Esperada, Tasa_Mensual_Esperada,
    -- Fechas
    Fecha_Adquisicion_Esperada, Fecha_Inicio_Depreciacion_Esperada,
    Fecha_Fin_Depreciacion_Esperada, Fecha_Baja_Esperada,
    -- Meses
    Meses_Uso_Inicio_Ejercicio_Esperado, Meses_Uso_En_Ejercicio_Esperado,
    -- Depreciación
    Dep_Acum_Inicio_Esperada, Saldo_Inicio_Año_Esperado, Dep_Fiscal_Ejercicio_Esperada,
    -- INPC
    INPCCompra_Esperado, INPC_Mitad_Ejercicio_Esperado, INPC_Mitad_Periodo_Esperado,
    -- Factores Fiscales
    Factor_Actualizacion_Saldo_Esperado, Factor_Actualizacion_Dep_Esperado,
    Saldo_Actualizado_Esperado, Dep_Actualizada_Esperada,
    Valor_Promedio_Esperado, Proporcion_Esperada,
    -- Safe Harbor
    INPC_SH_Junio_Esperado, Factor_SH_Esperado,
    Saldo_SH_Actualizado_Esperado, Dep_SH_Actualizada_Esperada,
    Valor_SH_Promedio_Esperado, Proporcion_SH_Esperada,
    -- Valores Finales
    Prueba_10_Pct_MOI_Esperada, Valor_Reportable_MXN_Esperado,
    Valor_SH_Reportable_Esperado, Aplica_10_Pct_Esperado,
    -- Control
    Observaciones
)
VALUES (
    1, 'Edificio totalmente depreciado (Tasa 5%)', 50847, 188, 2025,
    -- Datos básicos
    59804.00, 5.000000, 0.004167,
    -- Fechas
    '1996-12-01', '1996-12-01', '2016-10-01', NULL,
    -- Meses
    337, 12,
    -- Depreciación
    83974.78, 0.00, 0.00,
    -- INPC
    28.759336, 140.405000, 140.405000,
    -- Factores Fiscales
    4.882000, 4.882000,
    0.00, 0.00,
    0.00, 0.00,
    -- Safe Harbor
    140.405000, 4.8820668182,
    0.00, 0.00,
    0.00, 0.00,
    -- Valores Finales
    5980.40, 5980.40,
    5980.40, 1,
    -- Control
    'Activo totalmente depreciado desde oct-2016. Aplica regla 10% MOI mínimo.'
);

-- =============================================
-- CASO 2: Vehículo Totalmente Depreciado
-- Folio: 50909
-- Status: ✅ RevisadoOK
-- =============================================
INSERT INTO AutoTest (
    Numero_Caso, Nombre_Caso, ID_NUM_ACTIVO, ID_Compania, Año_Calculo,
    -- Datos básicos
    MOI_Esperado, Tasa_Anual_Esperada, Tasa_Mensual_Esperada,
    -- Fechas
    Fecha_Adquisicion_Esperada, Fecha_Inicio_Depreciacion_Esperada,
    Fecha_Fin_Depreciacion_Esperada, Fecha_Baja_Esperada,
    -- Meses
    Meses_Uso_Inicio_Ejercicio_Esperado, Meses_Uso_En_Ejercicio_Esperado,
    -- Depreciación
    Dep_Acum_Inicio_Esperada, Saldo_Inicio_Año_Esperado, Dep_Fiscal_Ejercicio_Esperada,
    -- INPC
    INPCCompra_Esperado, INPC_Mitad_Ejercicio_Esperado, INPC_Mitad_Periodo_Esperado,
    -- Factores Fiscales
    Factor_Actualizacion_Saldo_Esperado, Factor_Actualizacion_Dep_Esperado,
    Saldo_Actualizado_Esperado, Dep_Actualizada_Esperada,
    Valor_Promedio_Esperado, Proporcion_Esperada,
    -- Safe Harbor
    INPC_SH_Junio_Esperado, Factor_SH_Esperado,
    Saldo_SH_Actualizado_Esperado, Dep_SH_Actualizada_Esperada,
    Valor_SH_Promedio_Esperado, Proporcion_SH_Esperada,
    -- Valores Finales
    Prueba_10_Pct_MOI_Esperada, Valor_Reportable_MXN_Esperado,
    Valor_SH_Reportable_Esperado, Aplica_10_Pct_Esperado,
    -- Control
    Observaciones
)
VALUES (
    2, 'Vehículo totalmente depreciado (Tasa 25%)', 50909, 188, 2025,
    -- Datos básicos
    335652.00, 25.000000, 0.020833,
    -- Fechas
    '2000-11-01', '2000-11-01', '2004-10-01', NULL,
    -- Meses
    290, 12,
    -- Depreciación
    2027897.50, 0.00, 0.00,
    -- INPC
    65.380000, 140.405000, 140.405000,
    -- Factores Fiscales
    2.937900, 2.937900,
    0.00, 0.00,
    0.00, 0.00,
    -- Safe Harbor
    140.405000, 2.9379400266,
    0.00, 0.00,
    0.00, 0.00,
    -- Valores Finales
    33565.20, 33565.20,
    33565.20, 1,
    -- Control
    'Vehículo nuevo totalmente depreciado desde oct-2004. Tasa máxima 25%. Aplica 10% MOI.'
);

GO

PRINT '✅ Caso 1 insertado: Folio 50847';
PRINT '✅ Caso 2 insertado: Folio 50909';
PRINT '';
PRINT 'Total casos en AutoTest: 2';
GO

-- Mostrar casos insertados
SELECT
    Numero_Caso,
    Nombre_Caso,
    ID_NUM_ACTIVO AS Folio,
    MOI_Esperado AS MOI,
    Tasa_Anual_Esperada AS [Tasa%],
    Valor_Reportable_MXN_Esperado AS [Valor Reportable],
    Aplica_10_Pct_Esperado AS [Aplica 10%]
FROM AutoTest
ORDER BY Numero_Caso;
GO
