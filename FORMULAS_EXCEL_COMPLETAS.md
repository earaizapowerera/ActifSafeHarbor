# Fórmulas Exactas del Excel - Análisis Completo

**Fuente:** Propuesta reporte Calculo AF.xlsx
**Hojas analizadas:** Activos Extranjeros, Activos Mexicanos
**Fecha:** 2025-10-12

---

## DIFERENCIAS CLAVE ENTRE ACTIVOS EXTRANJEROS Y MEXICANOS

### Activos Extranjeros (Más Simple)
- **NO usan actualización INPC**
- Se basan en "Monto pendiente por deducir"
- Aplican regla del 10% MOI directamente
- Convierten a PESOS usando TC del 30 de junio

### Activos Mexicanos (Más Complejo)
- **SÍ usan actualización INPC**
- Calculan "Saldo actualizado" con factores INPC
- Usan "Valor Promedio" (saldo - 50% depreciación)
- Ya están en PESOS

---

## PARTE 1: FÓRMULAS PARA ACTIVOS EXTRANJEROS

### Campos Base

```
D = MOI (Monto Original de Inversión)
E = Anual Rate (Tasa anual, ej: 0.08)
F = Month Rate
H = Meses de uso al inicio del ejercicio
I = Meses de uso hasta la ½ del periodo
J = Meses de uso en el ejercicio
```

### Paso 1: Calcular Tasa Mensual

```excel
F = +E/12
```

```csharp
decimal tasaMensual = tasaAnual / 12;
```

### Paso 2: Calcular Depreciación Anual

```excel
G = +D*E
```

```csharp
decimal depreciacionAnual = MOI * tasaAnual;
```

### Paso 3: Calcular Depreciación Acumulada Inicio Año

```excel
K = +D*F*H
```

```csharp
decimal depAcumInicio = MOI * tasaMensual * mesesUsoInicioEjercicio;
```

**Origen del dato `H` (Meses de uso al inicio del ejercicio):**
- Se calcula como: Meses transcurridos desde fecha de adquisición hasta 31-Dic-2023
- Si es activo nuevo en 2024: H = 0

### Paso 4: Calcular Saldo por Deducir ISR al Inicio del Año

```excel
L = +D-K
```

```csharp
decimal saldoInicioAño = MOI - depAcumInicio;
```

### Paso 5: Calcular Depreciación Fiscal del Ejercicio

**IMPORTANTE:** Usa `I` (meses hasta la mitad del período), NO `J` (meses completos del ejercicio)

```excel
M = +D*F*I
```

```csharp
decimal depEjercicio = MOI * tasaMensual * mesesHastaMitadPeriodo;
```

**Cálculo de `I` (Meses de uso hasta la ½ del periodo):**

| Escenario | Fecha Adquisición | I (Meses hasta mitad) | Lógica |
|-----------|-------------------|-----------------------|--------|
| Activo existente | Antes de 2024 | 6 | Desde 01-Ene hasta 30-Jun |
| Adquirido antes junio | Ene - Jun 2024 | Meses desde adquisición hasta 30-Jun | Ejemplo: Si adquirió en Marzo, I = 5 (Mar-Jun) |
| Adquirido después junio | Jul - Dic 2024 | Meses desde adquisición hasta 30-Jun del SIGUIENTE ejercicio / 2 | Ejemplo: Si adquirió en Julio, I = 3 (porque solo usó segunda mitad) |
| Dado de baja | Cualquiera | MIN(meses_desde_inicio_hasta_baja, 6) | Si dio de baja en Abril, I = 4 |

### Paso 6: Calcular Monto Pendiente por Deducir

```excel
N = +L-M
```

```csharp
decimal montoPendiente = saldoInicioAño - depEjercicio;
```

### Paso 7: Calcular Proporción del Monto Pendiente

```excel
O = +N/12*J
```

```csharp
decimal proporcion = (montoPendiente / 12) * mesesUsoEjercicio;
```

**Donde `J` (Meses de uso en el ejercicio):**
- Activo activo todo el año: J = 12
- Activo adquirido en el año: J = meses desde adquisición hasta diciembre
- Activo dado de baja: J = meses desde enero hasta baja

### Paso 8: APLICAR REGLA DEL 10% MOI (Art 182 LISR)

```excel
Q = IF(O>(D*0.1), O, (D*0.1))
```

```csharp
decimal prueba10Pct = MOI * 0.10m;
decimal valorParaCalculo = (proporcion > prueba10Pct) ? proporcion : prueba10Pct;
```

**Interpretación:**
- Si la proporción calculada > 10% del MOI → usar la proporción
- Si la proporción calculada ≤ 10% del MOI → usar el 10% del MOI (mínimo)

### Paso 9: Conversión a Pesos Mexicanos

```excel
S = +Q*R
```

```csharp
decimal tipoCambio30Junio = 18.2478m; // Ejemplo para 2024
decimal valorFinalPesos = valorParaCalculo * tipoCambio30Junio;
```

**CRÍTICO:** El tipo de cambio es del **30 de junio del año de cálculo** (no de adquisición, no de diciembre).

---

## PARTE 2: FÓRMULAS PARA ACTIVOS MEXICANOS

### Campos Base (Mismos que extranjeros + INPC)

```
D = MOI
E = Anual Rate
F = Month Rate
H = Meses de uso al ejercicio ant (año anterior)
I = Meses de uso en el ejercicio (año actual)
L = INPC Adqu (INPC del mes de adquisición)
M = INPC ½ del ejercicio (INPC de junio del año actual)
S = INPC ½ del periodo (INPC de mitad del período específico)
```

### Paso 1-4: Igual que Activos Extranjeros

```excel
F = +E/12
G = +D*E
J = +D*F*H
K = +D-J
```

### Paso 5: Calcular Factor de Actualización (Saldo Inicio)

```excel
N = TRUNC(M/L, 4)
```

```csharp
decimal factorActualizacion = Math.Truncate((inpcMitadEjercicio / inpcAdquisicion) * 10000) / 10000;
```

**IMPORTANTE:** Se usa `TRUNC` (no `ROUND`), con 4 decimales.

### Paso 6: Calcular Saldo Actualizado

```excel
O = +K*N
```

```csharp
decimal saldoActualizado = saldoInicioAño * factorActualizacion;
```

### Paso 7: Calcular Depreciación Fiscal del Ejercicio

**NOTA:** A diferencia de activos extranjeros, aquí SÍ se usa `I` (meses completos del ejercicio).

```excel
Q = +D*F*I
```

```csharp
decimal depEjercicio = MOI * tasaMensual * mesesUsoEjercicio;
```

### Paso 8: Obtener INPC para Actualizar Depreciación

Hay **DOS tipos de INPC:**

1. **INPC Adqu (columna R):** Copia del INPC de adquisición
   ```excel
   R = +L
   ```

2. **INPC ½ del periodo (columna S):** INPC específico de mitad del período

**Diferencia entre M y S:**

| Columna | Descripción | Cuándo se usa | Ejemplo 2024 |
|---------|-------------|---------------|--------------|
| **M** (INPC ½ del ejercicio) | INPC de **junio** del año de cálculo | Para actualizar SALDO inicial | 134.594 (jun-2024) |
| **S** (INPC ½ del periodo) | INPC específico según meses de uso | Para actualizar DEPRECIACIÓN | Varía según caso |

**Valores de S según escenario:**

- **Activo existente todo el año:** S = INPC de junio = 134.594
- **Activo adquirido en 2024 antes de junio:** S = INPC de mitad del período entre adquisición y junio
  - Ejemplo: Adquirido en Marzo (10 meses de uso), mitad = 5 meses = Agosto → S = INPC de Agosto (136.003)
- **Activo adquirido después de junio:** S = INPC de mitad entre adquisición y diciembre
  - Ejemplo: Adquirido en Julio (6 meses), mitad = 3 meses = Octubre → S = INPC de Octubre (136.08)

### Paso 9: Calcular Factor de Actualización para Depreciación

```excel
T = TRUNC(S/R, 4)
```

```csharp
decimal factorActDepreciacion = Math.Truncate((inpcMitadPeriodo / inpcAdquisicion) * 10000) / 10000;
```

### Paso 10: Calcular Depreciación Fiscal Actualizada

```excel
U = +Q*T
```

```csharp
decimal depEjercicioActualizada = depEjercicio * factorActDepreciacion;
```

### Paso 11: Calcular 50% de la Depreciación Fiscal

```excel
V = +U*0.5
```

```csharp
decimal mitadDepreciacion = depEjercicioActualizada * 0.50m;
```

### Paso 12: Calcular Valor Promedio

```excel
X = +O-V
```

```csharp
decimal valorPromedio = saldoActualizado - mitadDepreciacion;
```

**INTERPRETACIÓN:** Este es el valor promedio del activo durante el año:
- Empieza con el saldo actualizado al inicio del año
- Le resta la mitad de lo que depreció en el año
- Representa el valor "promedio" que tuvo el activo durante el ejercicio

### Paso 13: Calcular Valor Promedio Proporcional del Año (RESULTADO FINAL)

```excel
Y = +X/12*I
```

```csharp
decimal valorFinalReportable = (valorPromedio / 12) * mesesUsoEjercicio;
```

**IMPORTANTE:** Si el activo solo se usó parte del año, se prorratea.

### Paso 14: Saldo Fiscal por Deducir (Para referencia futura)

```excel
AA = +D-J-Q
AB = +AA*T
```

```csharp
decimal saldoFiscalHistorico = MOI - depAcumInicio - depEjercicio;
decimal saldoFiscalActualizado = saldoFiscalHistorico * factorActDepreciacion;
```

Este es el saldo que quedará para el siguiente ejercicio fiscal.

---

## PARTE 3: COMPARACIÓN DE FÓRMULAS

### Activos Extranjeros (Columna S - Resultado Final)

```
S = IF(((L-M)/12*J) > (D*0.1), ((L-M)/12*J), (D*0.1)) * TC_30_Junio

Donde:
  L = Saldo por deducir ISR al inicio año = MOI - DepAcumInicio
  M = Depreciación fiscal del ejercicio = MOI * (Anual Rate / 12) * Meses hasta ½ periodo
  J = Meses de uso en el ejercicio
  D = MOI
  TC_30_Junio = Tipo de cambio del 30 de junio
```

### Activos Mexicanos (Columna Y - Resultado Final)

```
Y = ((SaldoInicio * FactorINPC_Saldo) - (Depreciacion * FactorINPC_Dep * 0.5)) / 12 * MesesUso

Donde:
  SaldoInicio = MOI - DepAcumInicio
  FactorINPC_Saldo = TRUNC(INPC_Jun_Actual / INPC_Adqu, 4)
  Depreciacion = MOI * (Anual Rate / 12) * MesesUsoEjercicio
  FactorINPC_Dep = TRUNC(INPC_MitadPeriodo / INPC_Adqu, 4)
```

---

## PARTE 4: CASOS ESPECIALES DOCUMENTADOS

### Caso 1: Activo en Uso en 2024 (Fila 6 Extranjeros)

```
Fecha Adquisición: 20/01/2019
MOI: 100,000 USD
H (Meses inicio): 60
I (Meses hasta ½): 6
J (Meses ejercicio): 12

Cálculos:
  K = 100000 * 0.00667 * 60 = 40,000 (Dep acumulada)
  L = 100000 - 40000 = 60,000 (Saldo inicio)
  M = 100000 * 0.00667 * 6 = 4,000 (Dep ejercicio)
  N = 60000 - 4000 = 56,000 (Monto pendiente)
  O = 56000/12*12 = 56,000 (Proporción)
  Q = IF(56000 > 10000, 56000, 10000) = 56,000 (> 10% MOI)
  S = 56000 * 18.2478 = 1,021,876.80 PESOS

Observación: "Activo en uso en 2024"
```

### Caso 2: Activo Adquirido en 2024 Antes de Junio (Fila 7 Extranjeros)

```
Fecha Adquisición: 20/03/2024
MOI: 60,000 USD
H = 0 (nuevo)
I = 5 (Marzo a Junio: 5 meses)
J = 10 (Marzo a Diciembre)

Cálculos:
  K = 60000 * 0.00667 * 0 = 0
  L = 60000 - 0 = 60,000
  M = 60000 * 0.00667 * 5 = 2,000
  N = 60000 - 2000 = 58,000
  O = 58000/12*10 = 48,333.33
  Q = IF(48333 > 6000, 48333, 6000) = 48,333.33
  S = 48333.33 * 18.2478 = 881,977 PESOS

Observación: "Activo adquirido en 2024 antes junio"
```

### Caso 3: Activo Adquirido Después de Junio (Fila 8 Extranjeros)

```
Fecha Adquisición: 20/07/2024
MOI: 550,000 USD
H = 0
I = 3 (Julio a Diciembre = 6 meses / 2 = 3 meses)
J = 6

Cálculos:
  M = 550000 * 0.00667 * 3 = 11,000
  N = 550000 - 11000 = 539,000
  O = 539000/12*6 = 269,500
  Q = IF(269500 > 55000, 269500, 55000) = 269,500
  S = 269500 * 18.2478 = 4,917,782.10 PESOS

Observación: "Activo adquirido en 2024 después junio"
Nota: "Se adquirió en el año y se utilizó 6 meses pero la deducción es a la mitad del período de 6 meses (3)"
```

### Caso 4: Activo Dado de Baja (Fila 9 Extranjeros)

```
Fecha Adquisición: 20/08/2018
Fecha Baja: 20/08/2024
MOI: 200,000 USD
H = 65 meses
I = 4 (se dio de baja en agosto, mitad = 4 meses)
J = 8 (enero a agosto)

Cálculos:
  K = 200000 * 0.00667 * 65 = 86,666.67
  L = 200000 - 86667 = 113,333.33
  M = 200000 * 0.00667 * 4 = 5,333.33
  N = 113333 - 5333 = 108,000
  O = 108000/12*8 = 72,000
  Q = IF(72000 > 20000, 72000, 20000) = 72,000
  S = 72000 * 18.2478 = 1,313,841.60 PESOS

Observación: "Activo dado de baja en 2024"
```

### Caso 5: Activo con Prueba 10% MOI (Fila 10 Extranjeros)

```
Fecha Adquisición: 20/01/2012
MOI: 800,000 USD
H = 132 meses (11 años)
Tasa: 0.08 (8% anual)

Cálculos:
  K = 800000 * 0.00667 * 132 = 704,000 (88% depreciado!)
  L = 800000 - 704000 = 96,000 (solo 12% restante)
  M = 800000 * 0.00667 * 6 = 32,000
  N = 96000 - 32000 = 64,000 (8% del MOI)
  O = 64000/12*12 = 64,000
  Prueba: 800000 * 0.10 = 80,000
  Q = IF(64000 > 80000, 64000, 80000) = 80,000 ← SE USA EL 10%!
  S = 80000 * 18.2478 = 1,459,824 PESOS

Observación: "Activo en uso prueba 10% MOI"
Nota: "Prueba de los activos totalmente depreciados o si el saldo por deducir es menor al 10% del MOI"
```

---

## PARTE 5: IMPLEMENTACIÓN EN C#

### Clase para Cálculo de Activos Extranjeros

```csharp
public class CalculadorActivosExtranjeros
{
    public decimal CalcularValorReportable(
        decimal moi,
        decimal tasaAnual,
        DateTime fechaAdquisicion,
        DateTime? fechaBaja,
        int añoCalculo,
        decimal depAcumInicioAño,
        decimal tipoCambio30Junio)
    {
        // 1. Tasa mensual
        decimal tasaMensual = tasaAnual / 12;

        // 2. Meses de uso al inicio del ejercicio (hasta 31-Dic del año anterior)
        DateTime inicioEjercicio = new DateTime(añoCalculo, 1, 1);
        int mesesUsoInicioEjercicio = CalcularMeses(fechaAdquisicion, inicioEjercicio);

        // 3. Meses hasta la mitad del periodo
        int mesesHastaMitad = CalcularMesesHastaMitadPeriodo(
            fechaAdquisicion, fechaBaja, añoCalculo);

        // 4. Meses de uso en el ejercicio
        int mesesUsoEjercicio = CalcularMesesEnEjercicio(
            fechaAdquisicion, fechaBaja, añoCalculo);

        // 5. Saldo por deducir ISR al inicio del año
        decimal saldoInicioAño = moi - depAcumInicioAño;

        // 6. Depreciación fiscal del ejercicio (hasta mitad del periodo)
        decimal depEjercicio = moi * tasaMensual * mesesHastaMitad;

        // 7. Monto pendiente por deducir
        decimal montoPendiente = saldoInicioAño - depEjercicio;
        if (montoPendiente < 0) montoPendiente = 0;

        // 8. Proporción del monto pendiente
        decimal proporcion = (montoPendiente / 12) * mesesUsoEjercicio;

        // 9. APLICAR REGLA DEL 10% MOI (Art 182 LISR)
        decimal prueba10Pct = moi * 0.10m;
        decimal valorParaCalculo = proporcion > prueba10Pct ? proporcion : prueba10Pct;

        // 10. Conversión a pesos
        decimal valorFinalPesos = valorParaCalculo * tipoCambio30Junio;

        return valorFinalPesos;
    }

    private int CalcularMesesHastaMitadPeriodo(
        DateTime fechaAdquisicion,
        DateTime? fechaBaja,
        int añoCalculo)
    {
        DateTime mitadAño = new DateTime(añoCalculo, 6, 30);
        DateTime inicioAño = new DateTime(añoCalculo, 1, 1);

        // Caso: Activo dado de baja
        if (fechaBaja.HasValue && fechaBaja.Value.Year == añoCalculo)
        {
            int mesesHastaBaja = fechaBaja.Value.Month;
            return Math.Min(mesesHastaBaja, 6);
        }

        // Caso: Activo adquirido antes del año
        if (fechaAdquisicion.Year < añoCalculo)
        {
            return 6; // Enero a Junio
        }

        // Caso: Activo adquirido en el año antes de junio
        if (fechaAdquisicion <= mitadAño)
        {
            return CalcularMeses(fechaAdquisicion, mitadAño);
        }

        // Caso: Activo adquirido después de junio
        // Usa la mitad del periodo desde adquisición hasta diciembre
        DateTime finAño = new DateTime(añoCalculo, 12, 31);
        int mesesDesdeAdqHastaFin = CalcularMeses(fechaAdquisicion, finAño);
        return mesesDesdeAdqHastaFin / 2;
    }

    private int CalcularMesesEnEjercicio(
        DateTime fechaAdquisicion,
        DateTime? fechaBaja,
        int añoCalculo)
    {
        DateTime inicioAño = new DateTime(añoCalculo, 1, 1);
        DateTime finAño = new DateTime(añoCalculo, 12, 31);

        DateTime fechaInicio = fechaAdquisicion.Year < añoCalculo
            ? inicioAño
            : fechaAdquisicion;

        DateTime fechaFin = fechaBaja.HasValue && fechaBaja.Value.Year == añoCalculo
            ? fechaBaja.Value
            : finAño;

        return CalcularMeses(fechaInicio, fechaFin);
    }

    private int CalcularMeses(DateTime desde, DateTime hasta)
    {
        if (hasta < desde) return 0;

        int meses = ((hasta.Year - desde.Year) * 12) + hasta.Month - desde.Month;

        // Ajustar si el día del mes final es menor que el inicial
        if (hasta.Day < desde.Day)
            meses--;

        return Math.Max(meses, 0);
    }
}
```

---

## PARTE 6: DATOS NECESARIOS DE LA BASE DE DATOS

### Para Activos Extranjeros:

```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO AS Placa,
    a.COSTO_ADQUISICION AS MOI,
    a.FECHA_COMPRA AS FechaAdquisicion,
    a.FECHA_BAJA,
    a.ID_TIPO_ACTIVO,
    pd.PORCENTAJE AS TasaAnual,
    COALESCE(c.ACUMULADO_HISTORICA, 0) AS DepAcumInicio,
    a.ID_MONEDA,
    a.ID_PAIS,
    p.NOMBRE AS NombrePais
FROM activo a
INNER JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2  -- Fiscal
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_ANO = @AñoAnterior  -- 2023 para ejercicio 2024
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
WHERE a.FLG_PROPIO = 0  -- Solo NO propios
  AND a.ID_PAIS > 1     -- Solo extranjeros
  AND a.ID_COMPANIA = @IdCompania
```

### Para Activos Mexicanos (Adicional: INPC):

```sql
-- Mismo query base + INPC
SELECT ...,
    inpc_adq.Indice AS INPC_Adqu,
    inpc_mitad.Indice AS INPC_MitadEjercicio
FROM activo a
...
LEFT JOIN INPC2 inpc_adq
    ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
    AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
    AND inpc_adq.Id_Pais = 1
    AND inpc_adq.Id_Tipo_Dep = 2
LEFT JOIN INPC2 inpc_mitad
    ON inpc_mitad.Anio = @AñoCalculo
    AND inpc_mitad.Mes = 6  -- Junio
    AND inpc_mitad.Id_Pais = 1
    AND inpc_mitad.Id_Tipo_Dep = 2
WHERE a.ID_PAIS = 1  -- Solo mexicanos
  AND a.FLG_PROPIO = 0
```

---

## RESUMEN EJECUTIVO

| Aspecto | Activos Extranjeros | Activos Mexicanos |
|---------|---------------------|-------------------|
| **Complejidad** | Menor | Mayor |
| **Actualización INPC** | ❌ NO | ✅ SÍ |
| **Conversión moneda** | ✅ SÍ (TC 30-Jun) | ❌ NO (ya en MXN) |
| **Regla 10% MOI** | ✅ Aplica (Art 182) | ❌ NO aplica |
| **Meses para depreciación** | Hasta ½ del periodo (`I`) | Completos del ejercicio (`I`) |
| **Cálculo depreciación** | Simple | Con factor INPC |
| **Valor reportable** | Monto pendiente proporcional × TC | Valor promedio anual actualizado |
| **Fórmula final** | `IF(proporción>10%MOI, proporción, 10%MOI) × TC` | `(SaldoActualizado - 50%DepActualizada) / 12 × Meses` |

---

**CRÍTICO:** La diferencia principal es que los activos extranjeros usan un cálculo más simple enfocado en el monto pendiente y aplican la regla del 10% MOI, mientras que los mexicanos usan actualización INPC completa y calculan un "valor promedio" del activo durante el año.
