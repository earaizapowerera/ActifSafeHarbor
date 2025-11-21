-- =============================================
-- Insertar caso de prueba 3 validado
-- Caso 3: Activo en depreciación activa (Compañía 12)
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- CASO 3: Activo en Depreciación Activa
-- Folio: 206122
-- Status: ✅ RevisadoOK
-- Nota: Activo adquirido en dic-2022, en depreciación activa
--       SÍ tiene saldo por deducir ($15,663.93)
--       NO aplica regla 10% MOI (saldo > 10% MOI)
--       Factor fiscal normal (no especial)
-- =============================================

-- Primero eliminar el caso 3 anterior si existe
DELETE FROM AutoTest WHERE Numero_Caso = 3;

-- Insertar el caso 3 actualizado
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
    3, 'Activo en depreciación activa (Tasa 10%)', 206122, 12, 2025,
    -- Datos básicos
    19580.01, 10.000000, 0.008333,
    -- Fechas
    '2022-12-22', '2023-01-22', '2032-12-01', NULL,
    -- Meses
    24, 12,
    -- Depreciación
    3916.08, 15663.93, 1958.00,
    -- INPC
    126.478000, 140.405000, 140.405000,
    -- Factores Fiscales
    1.1101, 1.1101,
    17388.5287, 2173.5769,
    16301.7402, 16301.7402,
    -- Safe Harbor
    140.405000, 1.1101140119,
    17388.7482, 2173.6043,
    16301.9461, 16301.9461,
    -- Valores Finales
    1958.001, 16301.7402,
    16301.9461, 0,
    -- Control
    'Activo en depreciación activa. Adquirido dic-2022. SÍ tiene saldo por deducir ($15,663.93). NO aplica regla 10% MOI porque saldo > 10% MOI. Factor fiscal normal 1.1101.'
);

GO

PRINT '✅ Caso 3 insertado: Folio 206122 (Compañía 12 - PIEDRAS NEGRAS)';
PRINT '   Activo en depreciación activa - Tasa 10%';
PRINT '';
PRINT 'Total casos en AutoTest: 3';
GO

-- Mostrar casos insertados
SELECT
    Numero_Caso,
    Nombre_Caso,
    ID_NUM_ACTIVO AS Folio,
    ID_Compania AS Compañía,
    MOI_Esperado AS MOI,
    Tasa_Anual_Esperada AS [Tasa%],
    Saldo_Inicio_Año_Esperado AS [Saldo Inicio],
    Dep_Fiscal_Ejercicio_Esperada AS [Dep Ejercicio],
    Factor_Actualizacion_Saldo_Esperado AS [Factor Fiscal],
    Factor_SH_Esperado AS [Factor SH],
    Valor_Reportable_MXN_Esperado AS [Valor Reportable],
    Aplica_10_Pct_Esperado AS [Aplica 10%]
FROM AutoTest
WHERE Activo = 1
ORDER BY Numero_Caso;
GO

-- =============================================
-- COMPARACIÓN DE LOS 3 CASOS
-- =============================================

PRINT '';
PRINT '================================================================================';
PRINT 'RESUMEN DE LOS 3 CASOS VALIDADOS';
PRINT '================================================================================';
PRINT '';
PRINT 'CASO 1 (Folio 50847): Edificio totalmente depreciado - Tasa 5%';
PRINT '  - Saldo: $0.00 | Aplica 10% MOI: SÍ | Valor: $5,980.40';
PRINT '';
PRINT 'CASO 2 (Folio 50909): Vehículo totalmente depreciado - Tasa 25%';
PRINT '  - Saldo: $0.00 | Aplica 10% MOI: SÍ | Valor: $33,565.20';
PRINT '';
PRINT 'CASO 3 (Folio 206122): Activo en depreciación activa - Tasa 10%';
PRINT '  - Saldo: $15,663.93 | Aplica 10% MOI: NO | Valor: $16,301.74';
PRINT '';
PRINT '================================================================================';
PRINT 'ESCENARIOS CUBIERTOS:';
PRINT '================================================================================';
PRINT '✅ Activos totalmente depreciados (Casos 1 y 2)';
PRINT '✅ Activos en depreciación activa (Caso 3)';
PRINT '✅ Regla 10% MOI aplicada (Casos 1 y 2)';
PRINT '✅ Regla 10% MOI NO aplicada (Caso 3)';
PRINT '✅ Diferentes tasas: 5%, 10%, 25%';
PRINT '✅ Diferentes compañías: 188 (Prueba), 12 (PIEDRAS NEGRAS)';
PRINT '================================================================================';
GO
