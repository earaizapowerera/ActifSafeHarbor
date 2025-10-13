# Fórmulas Exactas para Cálculo de Activos Fijos - RMF

Basado en análisis del archivo Excel "Propuesta reporte Calculo AF.xlsx"

---

## REGLA FUNDAMENTAL: 10% MOI MÍNIMO

**Artículo de referencia (según Excel):** Art 182, fracción I, inciso a) LISR

**Regla del Residual:**
> Si un activo está completamente depreciado O si el saldo por deducir es menor al 10% del MOI, entonces se toma el 10% del MOI como valor mínimo deducible.

```
IF (Saldo_Por_Deducir < (MOI × 0.10) OR Saldo_Por_Deducir <= 0) THEN
    Valor_Para_Calculo = MOI × 0.10
ELSE
    Valor_Para_Calculo = Saldo_Por_Deducir
END IF
```

---

## PASO A PASO: Cálculo para Activos No Propios

### Campos Base de Datos Origen: actif_web_cima_dev

**Tabla: `activo`**
- `ID_NUM_ACTIVO` - Identificador
- `COSTO_ADQUISICION` → **MOI** (Monto Original de Inversión)
- `FECHA_COMPRA` → Fecha de adquisición
- `ID_TIPO_ACTIVO` → Para obtener tasa de depreciación
- `FLG_PROPIO` → **DEBE SER 0** (No propios)
- `ID_PAIS` → País del activo
- `STATUS` → Debe ser 'A' (Activo) o verificar fecha de baja

**Tabla: `calculo`**
- `ACUMULADO_HISTORICA` → Depreciación fiscal acumulada
- `ID_ANO`, `ID_MES` → Para filtrar período
- `ID_TIPO_DEP` → **DEBE SER 2** (Fiscal)

**Tabla: `INPC2`**
- `Indice` → Valor del INPC
- `Anio`, `Mes` → Para buscar INPC específico
- `Id_Pais` → 1 = México
- `Id_Tipo_Dep` → 2 = Fiscal

---

## FÓRMULAS DE CÁLCULO

### 1. Obtener Datos Básicos del Activo

```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO AS Placa,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION AS MOI,
    a.FECHA_COMPRA AS Fecha_Adquisicion,
    a.FECHA_BAJA,
    a.ID_TIPO_ACTIVO,
    a.ID_PAIS,
    ta.TASA_DEPRECIACION AS Tasa_Anual,
    ta.TASA_DEPRECIACION / 12 AS Tasa_Mensual
FROM activo a
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
WHERE a.FLG_PROPIO = 0  -- Solo activos NO propios
  AND a.ID_COMPANIA = @IdCompania
  AND a.STATUS = 'A'
```

### 2. Calcular Meses de Uso

#### a) Meses de uso al inicio del ejercicio (año anterior completo)

```csharp
DateTime fechaAdquisicion = activo.FechaCompra;
DateTime inicioEjercicio = new DateTime(añoCalculo, 1, 1);

// Meses desde adquisición hasta inicio del ejercicio actual
int mesesUsoInicioEjercicio = CalcularMesesEntre(fechaAdquisicion, inicioEjercicio);
```

#### b) Meses de uso hasta la mitad del período

```csharp
DateTime mitadPeriodo = new DateTime(añoCalculo, 6, 30); // 30 de junio
int mesesUsoMitadPeriodo = CalcularMesesEntre(inicioEjercicio, mitadPeriodo);
// Resultado esperado: 6 meses
```

#### c) Meses de uso en el ejercicio

```csharp
DateTime finEjercicio = new DateTime(añoCalculo, 12, 31);

// Si el activo se dio de baja en el ejercicio, usar fecha de baja
if (activo.FechaBaja != null && activo.FechaBaja.Value.Year == añoCalculo)
{
    int mesesUsoEjercicio = activo.FechaBaja.Value.Month;
}
else
{
    int mesesUsoEjercicio = 12; // Año completo
}
```

### 3. Obtener Depreciación Fiscal Acumulada al Inicio del Año

```sql
SELECT ACUMULADO_HISTORICA AS Dep_Fiscal_Acumulada_Inicio_Año
FROM calculo
WHERE ID_NUM_ACTIVO = @IdNumActivo
  AND ID_COMPANIA = @IdCompania
  AND ID_ANO = @AñoAnterior  -- 2023 para ejercicio 2024
  AND ID_MES = 12            -- Diciembre del año anterior
  AND ID_TIPO_DEP = 2        -- Fiscal
```

**Si no existe registro (activo nuevo):**
```csharp
decimal depFiscalAcumuladaInicio = registroCalculo?.ACUMULADO_HISTORICA ?? 0;
```

### 4. Calcular Saldo por Deducir ISR al Inicio del Año

```csharp
decimal saldoInicioAño = MOI - depFiscalAcumuladaInicio;

// Validar que no sea negativo
if (saldoInicioAño < 0)
    saldoInicioAño = 0;
```

### 5. Calcular Depreciación Fiscal del Ejercicio

```csharp
// Depreciación anual según tasa
decimal depreciacionAnual = MOI * tasaAnual;

// Proporcional a los meses de uso en el ejercicio
decimal depreciacionEjercicio = depreciacionAnual * (mesesUsoEjercicio / 12.0m);

// NO puede exceder el saldo disponible
if (depreciacionEjercicio > saldoInicioAño)
    depreciacionEjercicio = saldoInicioAño;
```

### 6. Calcular Monto Pendiente por Deducir

```csharp
decimal montoPendiente = saldoInicioAño - depreciacionEjercicio;

// Validar no negativo
if (montoPendiente < 0)
    montoPendiente = 0;
```

### 7. **APLICAR REGLA DEL 10% MOI (CRÍTICO)**

```csharp
decimal prueba10PorMOI = MOI * 0.10m;

decimal valorParaCalculo;

if (montoPendiente < prueba10PorMOI || montoPendiente <= 0)
{
    // Usar el 10% del MOI como mínimo
    valorParaCalculo = prueba10PorMOI;
    observacion = "Activo en uso prueba 10% MOI";
}
else
{
    // Usar el monto pendiente normal
    valorParaCalculo = montoPendiente;
}
```

### 8. Calcular Proporción del Monto Pendiente

```csharp
// Proporción basada en meses de uso hasta mitad del período
decimal proporcion = (decimal)mesesUsoMitadPeriodo / (decimal)mesesUsoEjercicio;

decimal montoProporcional = valorParaCalculo * proporcion;
```

### 9. Obtener Tipo de Cambio (Solo para Activos Extranjeros)

**Si ID_PAIS > 1 (activo extranjero):**

```sql
-- Tipo de cambio al 30 de junio del ejercicio
SELECT TipoCambio
FROM tipo_cambio  -- O tabla correspondiente
WHERE Fecha = '2024-06-30'
  AND ID_MONEDA = @IdMonedaUSD
```

```csharp
decimal tipoCambio30Junio = ObtenerTipoCambio(new DateTime(añoCalculo, 6, 30), idMonedaUSD);

// Si el activo está en moneda extranjera
if (activo.ID_PAIS > 1)
{
    // El MOI ya debería estar en moneda extranjera en la BD
    // Convertir a pesos mexicanos
    valorEnPesos = valorParaCalculo * tipoCambio30Junio;
}
```

### 10. **Valor Promedio Proporcional del Año en PESOS** (Resultado Final)

Este es el valor que se reporta (columna amarilla en el Excel):

```csharp
decimal valorPromedioProporcionalPesos;

if (activo.ID_PAIS == 1) // México
{
    valorPromedioProporcionalPesos = montoProporcional;
}
else // Extranjero
{
    valorPromedioProporcionalPesos = montoProporcional * tipoCambio30Junio;
}
```

---

## CASOS ESPECIALES

### Caso 1: Activo Adquirido en 2024 Antes de Junio

**Observación:** "Activo adquirido en 2024 antes junio"

```csharp
if (fechaAdquisicion.Year == añoCalculo && fechaAdquisicion.Month <= 6)
{
    // Meses de uso hasta mitad = meses desde adquisición hasta junio
    mesesUsoMitadPeriodo = CalcularMesesEntre(fechaAdquisicion, new DateTime(añoCalculo, 6, 30));

    // Depreciación acumulada inicio = 0 (es nuevo)
    depFiscalAcumuladaInicio = 0;

    // Meses en el ejercicio = meses desde adquisición hasta diciembre
    mesesUsoEjercicio = 13 - fechaAdquisicion.Month; // ej: si es marzo = 10 meses
}
```

### Caso 2: Activo Adquirido en 2024 Después de Junio

**Observación:** "Activo adquirido en 2024 después junio"

```csharp
if (fechaAdquisicion.Year == añoCalculo && fechaAdquisicion.Month > 6)
{
    // NO se incluye en el cálculo de la mitad del período
    mesesUsoMitadPeriodo = 0;

    // Depreciación acumulada inicio = 0
    depFiscalAcumuladaInicio = 0;

    // Meses en el ejercicio = desde adquisición hasta diciembre
    mesesUsoEjercicio = 13 - fechaAdquisicion.Month;

    // Proporción = 0 para el reporte de mitad de año
    montoProporcional = 0;
}
```

### Caso 3: Activo Dado de Baja en 2024

**Observación:** "Activo dado de baja en 2024"

```csharp
if (fechaBaja != null && fechaBaja.Value.Year == añoCalculo)
{
    // Meses de uso en el ejercicio = hasta el mes de baja
    mesesUsoEjercicio = fechaBaja.Value.Month;

    // Si la baja es antes de junio
    if (fechaBaja.Value.Month <= 6)
    {
        mesesUsoMitadPeriodo = fechaBaja.Value.Month;
    }
    else
    {
        mesesUsoMitadPeriodo = 6; // Máximo hasta junio
    }

    // Aplicar depreciación proporcional
    depreciacionEjercicio = (MOI * tasaAnual) * (mesesUsoEjercicio / 12.0m);
}
```

### Caso 4: Activo en Uso Desde Años Anteriores

**Observación:** "Activo en uso en 2024"

```csharp
if (fechaAdquisicion.Year < añoCalculo)
{
    // Caso normal, todos los cálculos estándar
    mesesUsoMitadPeriodo = 6;
    mesesUsoEjercicio = 12;

    // Obtener depreciación acumulada del año anterior
    depFiscalAcumuladaInicio = ObtenerDepAcumuladaDic(añoCalculo - 1);
}
```

### Caso 5: Activo Totalmente Depreciado

**Observación:** "Activo en uso prueba 10% MOI"

```csharp
if (saldoInicioAño <= 0)
{
    // Aunque esté totalmente depreciado, se usa el 10% del MOI
    valorParaCalculo = MOI * 0.10m;
    montoPendiente = 0;
    depreciacionEjercicio = 0;

    observacion = "Activo totalmente depreciado - aplica 10% MOI mínimo";
}
```

---

## RESUMEN DEL FLUJO COMPLETO

```csharp
public decimal CalcularValorReportable(Activo activo, int añoCalculo)
{
    // 1. Datos básicos
    decimal MOI = activo.COSTO_ADQUISICION;
    decimal tasaAnual = activo.TasaDepreciacion;

    // 2. Calcular meses
    int mesesUsoInicioEjercicio = CalcularMesesHastaInicioEjercicio(activo.FechaCompra, añoCalculo);
    int mesesUsoMitadPeriodo = CalcularMesesHastaMitadPeriodo(activo, añoCalculo);
    int mesesUsoEjercicio = CalcularMesesEnEjercicio(activo, añoCalculo);

    // 3. Depreciación acumulada al inicio
    decimal depAcumInicio = ObtenerDepAcumuladaInicio(activo.ID_NUM_ACTIVO, añoCalculo - 1);

    // 4. Saldo al inicio
    decimal saldoInicio = MOI - depAcumInicio;
    if (saldoInicio < 0) saldoInicio = 0;

    // 5. Depreciación del ejercicio
    decimal depEjercicio = (MOI * tasaAnual) * (mesesUsoEjercicio / 12.0m);
    if (depEjercicio > saldoInicio) depEjercicio = saldoInicio;

    // 6. Monto pendiente
    decimal montoPendiente = saldoInicio - depEjercicio;
    if (montoPendiente < 0) montoPendiente = 0;

    // 7. *** REGLA DEL 10% MOI ***
    decimal prueba10Pct = MOI * 0.10m;
    decimal valorParaCalculo = (montoPendiente < prueba10Pct || montoPendiente == 0)
        ? prueba10Pct
        : montoPendiente;

    // 8. Proporción
    decimal proporcion = mesesUsoEjercicio > 0
        ? (decimal)mesesUsoMitadPeriodo / (decimal)mesesUsoEjercicio
        : 0;

    decimal montoProporcional = valorParaCalculo * proporcion;

    // 9. Conversión a pesos (si es extranjero)
    decimal valorFinalPesos;
    if (activo.ID_PAIS > 1)
    {
        decimal tc30Junio = ObtenerTipoCambio(new DateTime(añoCalculo, 6, 30));
        valorFinalPesos = montoProporcional * tc30Junio;
    }
    else
    {
        valorFinalPesos = montoProporcional;
    }

    return valorFinalPesos;
}
```

---

## QUERY SQL COMPLETO PARA REPORTE

```sql
-- Activos No Propios para Reporte RMF
WITH ActivosBase AS (
    SELECT
        a.ID_NUM_ACTIVO,
        a.ID_ACTIVO AS Placa,
        a.DESCRIPCION,
        a.ID_TIPO_ACTIVO,
        ta.NOMBRE AS TipoActivo,
        a.FECHA_COMPRA AS FechaAdquisicion,
        a.FECHA_BAJA AS FechaBaja,
        a.COSTO_ADQUISICION AS MOI,
        pd.PORCENTAJE AS TasaAnual,
        pd.PORCENTAJE / 12.0 AS TasaMensual,
        a.ID_PAIS,
        p.NOMBRE AS Pais,
        a.ID_MONEDA
    FROM activo a
    INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
    INNER JOIN porcentaje_depreciacion pd ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
        AND pd.ID_TIPO_DEP = 2  -- Fiscal
    INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
    WHERE a.FLG_PROPIO = 0  -- Solo NO propios
      AND a.ID_COMPANIA = @IdCompania
      AND a.STATUS = 'A'
),
DepreciacionAcumulada AS (
    SELECT
        c.ID_NUM_ACTIVO,
        c.ACUMULADO_HISTORICA AS DepAcumInicio
    FROM calculo c
    WHERE c.ID_COMPANIA = @IdCompania
      AND c.ID_ANO = @AñoCalculo - 1  -- Año anterior
      AND c.ID_MES = 12               -- Diciembre
      AND c.ID_TIPO_DEP = 2           -- Fiscal
)
SELECT
    ab.*,
    COALESCE(da.DepAcumInicio, 0) AS DepFiscalAcumuladaInicioAño,
    ab.MOI - COALESCE(da.DepAcumInicio, 0) AS SaldoPorDeducirInicioAño,
    ab.MOI * 0.10 AS Prueba10PorMOI
FROM ActivosBase ab
LEFT JOIN DepreciacionAcumulada da ON ab.ID_NUM_ACTIVO = da.ID_NUM_ACTIVO
ORDER BY ab.ID_PAIS, ab.ID_NUM_ACTIVO
```

---

## VALIDACIONES IMPORTANTES

1. ✅ Verificar que `ID_TIPO_DEP = 2` (Fiscal) en todas las consultas
2. ✅ Usar depreciación acumulada de **Diciembre del año anterior**
3. ✅ Tipo de cambio del **30 de junio del año de cálculo**
4. ✅ Aplicar regla del **10% MOI mínimo** SIEMPRE
5. ✅ Filtrar solo activos con `FLG_PROPIO = 0`
6. ✅ Manejar casos especiales de adquisición/baja en el año
7. ✅ Proporcionar observaciones descriptivas por caso

---

**Documento basado en:** Propuesta reporte Calculo AF.xlsx (hojas: Activos Extranjeros y Activos Mexicanos)
**Fecha:** 2025-10-12
**Base de datos origen:** actif_web_cima_dev
