-- =============================================
-- Insertar 4 casos nuevos de AutoTest
-- Basados en ciclo de vida del activo
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- CASO 2: Extranjero Totalmente Depreciado + 10% MOI
-- Folio: 51484
-- Status: ✅ Calculado
-- Nota: Edificio totalmente depreciado desde 2003
--       Aplica regla 10% MOI
--       Factor SH muy alto (448.97) por antigüedad
-- =============================================

DELETE FROM AutoTest WHERE Numero_Caso = 2;

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
    2, 'Extranjero: Totalmente depreciado + 10% MOI (Edificio 1984)', 51484, 188, 2025,
    -- Datos básicos
    471835.0000, 5.000000, 0.004167,
    -- Fechas
    '1984-01-01', '1984-01-01', '2003-11-01', NULL,
    -- Meses
    492, 12,
    -- Depreciación
    967261.7485, 0.0000, 0.0000,
    -- INPC
    0.312728, 140.405000, 140.405000,
    -- Factores Fiscales
    1.000000, 1.000000,
    0.0000, 0.0000,
    0.0000, 0.0000,
    -- Safe Harbor
    140.405000, 448.9684326316,
    0.0000, 0.0000,
    0.0000, 0.0000,
    -- Valores Finales
    47183.5000, 47183.5000,
    47183.5000, 1,
    -- Control
    'Extranjero totalmente depreciado desde 2003. Aplica regla 10% MOI. Factor SH muy alto (448.97) por antigüedad del activo (1984). Vida útil 20 años, terminó deprec en nov-2003.'
);

GO

PRINT '✅ Caso 2 insertado: Folio 51484 (Extranjero totalmente depreciado)';
PRINT '';

-- =============================================
-- CASO 4: Nacional Depreciación Activa (Troquel Tasa 35%)
-- Folio: 208312
-- Status: ✅ Calculado
-- Nota: Troquel adquirido abr-2023, tasa 35%
--       En depreciación activa (termina feb-2026)
--       NO aplica regla 10% MOI (saldo > 10% MOI)
-- =============================================

DELETE FROM AutoTest WHERE Numero_Caso = 4;

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
    4, 'Nacional: Depreciación activa Tasa 35% (Troquel 2023)', 208312, 188, 2025,
    -- Datos básicos
    22854.5200, 35.000000, 0.029167,
    -- Fechas
    '2023-04-25', '2023-05-01', '2026-02-01', NULL,
    -- Meses
    20, 12,
    -- Depreciación
    13331.8033, 9522.7167, 7999.0820,
    -- INPC
    128.363000, 140.405000, 140.405000,
    -- Factores Fiscales
    1.000000, 1.000000,
    9522.7167, 7999.0820,
    5523.1757, 5523.1757,
    -- Safe Harbor
    140.405000, 1.0938120798,
    10416.0626, 8749.4925,
    6041.3164, 6041.3164,
    -- Valores Finales
    2285.4520, 5523.1757,
    6041.3164, 0,
    -- Control
    'Nacional en depreciación activa. Adquirido abr-2023, tasa 35% (troqueles). Termina deprec feb-2026. Tiene saldo significativo ($9,522.72), NO aplica 10% MOI. Factor fiscal 1.0 (año reciente). Factor SH 1.094.'
);

GO

PRINT '✅ Caso 4 insertado: Folio 208312 (Nacional depreciación activa)';
PRINT '';

-- =============================================
-- CASO 5: Nacional Alta Antes Junio (Troquel Tasa 35%)
-- Folio: 208313
-- Status: ✅ Calculado
-- Nota: Mismo troquel que caso 4, para variedad
--       Representa escenario "Alta antes de junio"
-- =============================================

DELETE FROM AutoTest WHERE Numero_Caso = 5;

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
    5, 'Nacional: Alta antes junio (Troquel abr-2023)', 208313, 188, 2025,
    -- Datos básicos
    22854.5200, 35.000000, 0.029167,
    -- Fechas
    '2023-04-25', '2023-05-01', '2026-02-01', NULL,
    -- Meses
    20, 12,
    -- Depreciación
    13331.8033, 9522.7167, 7999.0820,
    -- INPC
    128.363000, 140.405000, 140.405000,
    -- Factores Fiscales
    1.000000, 1.000000,
    9522.7167, 7999.0820,
    5523.1757, 5523.1757,
    -- Safe Harbor
    140.405000, 1.0938120798,
    10416.0626, 8749.4925,
    6041.3164, 6041.3164,
    -- Valores Finales
    2285.4520, 5523.1757,
    6041.3164, 0,
    -- Control
    'Nacional alta abr-2023 (antes de junio). Tasa 35% (troqueles). Mismo comportamiento que caso 4 (mismo lote de troqueles). Sirve para validar consistencia de cálculos entre activos idénticos.'
);

GO

PRINT '✅ Caso 5 insertado: Folio 208313 (Nacional alta antes junio)';
PRINT '';

-- =============================================
-- CASO 6: Nacional Depreciación Activa Variante (Troquel)
-- Folio: 208314
-- Status: ✅ Calculado
-- Nota: Tercer troquel del mismo lote
--       Sirve para validar consistencia de cálculos
-- =============================================

DELETE FROM AutoTest WHERE Numero_Caso = 6;

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
    6, 'Nacional: Depreciación activa (Troquel variante)', 208314, 188, 2025,
    -- Datos básicos
    22854.5200, 35.000000, 0.029167,
    -- Fechas
    '2023-04-25', '2023-05-01', '2026-02-01', NULL,
    -- Meses
    20, 12,
    -- Depreciación
    13331.8033, 9522.7167, 7999.0820,
    -- INPC
    128.363000, 140.405000, 140.405000,
    -- Factores Fiscales
    1.000000, 1.000000,
    9522.7167, 7999.0820,
    5523.1757, 5523.1757,
    -- Safe Harbor
    140.405000, 1.0938120798,
    10416.0626, 8749.4925,
    6041.3164, 6041.3164,
    -- Valores Finales
    2285.4520, 5523.1757,
    6041.3164, 0,
    -- Control
    'Nacional depreciación activa. Troquel 3 del lote abr-2023. Valida consistencia: mismo MOI, tasa, fechas y resultados que casos 4 y 5. Útil para probar que activos idénticos producen cálculos idénticos.'
);

GO

PRINT '✅ Caso 6 insertado: Folio 208314 (Nacional depreciación activa variante)';
PRINT '';
PRINT '================================================================================';
PRINT 'RESUMEN DE CASOS INSERTADOS';
PRINT '================================================================================';
PRINT '';
PRINT 'Caso 2 (Folio 51484):  Extranjero totalmente depreciado + 10% MOI';
PRINT '  - MOI: $471,835 | Tasa: 5% | Valor: $47,183.50 | Aplica 10%: SÍ';
PRINT '';
PRINT 'Caso 4 (Folio 208312): Nacional depreciación activa Tasa 35%';
PRINT '  - MOI: $22,854.52 | Tasa: 35% | Saldo: $9,522.72 | Aplica 10%: NO';
PRINT '';
PRINT 'Caso 5 (Folio 208313): Nacional alta antes junio (abr-2023)';
PRINT '  - MOI: $22,854.52 | Tasa: 35% | Saldo: $9,522.72 | Aplica 10%: NO';
PRINT '';
PRINT 'Caso 6 (Folio 208314): Nacional depreciación activa (variante)';
PRINT '  - MOI: $22,854.52 | Tasa: 35% | Saldo: $9,522.72 | Aplica 10%: NO';
PRINT '';
PRINT '================================================================================';
PRINT 'ESCENARIOS CUBIERTOS';
PRINT '================================================================================';
PRINT '✅ Extranjero totalmente depreciado con 10% MOI';
PRINT '✅ Nacional depreciación activa tasa alta (35%)';
PRINT '✅ Nacional alta antes de junio';
PRINT '✅ Validación de consistencia (3 troqueles idénticos)';
PRINT '✅ Factor SH alto por antigüedad (caso 2: 448.97)';
PRINT '✅ Factor SH bajo por reciente (casos 4-6: 1.094)';
PRINT '================================================================================';
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
    Valor_Reportable_MXN_Esperado AS [Valor Reportable],
    Aplica_10_Pct_Esperado AS [Aplica 10%]
FROM AutoTest
WHERE Numero_Caso IN (2, 4, 5, 6)
  AND Activo = 1
ORDER BY Numero_Caso;
GO
