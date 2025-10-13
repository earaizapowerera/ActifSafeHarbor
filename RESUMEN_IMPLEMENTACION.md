# Resumen de Implementación - Sistema ActifRMF

**Fecha:** 2025-10-12
**Base de datos origen:** actif_web_cima_dev
**Base legal:** LISR Artículo 182 (Maquiladoras), Artículos 31-35 (Depreciación)

---

## 1. ALCANCE DEL SISTEMA

### Activos a Calcular

**FILTRO PRINCIPAL:** `FLG_PROPIO = 0` (Activos NO propios)

Esto incluye:
- Activos arrendados
- Activos de terceros
- Activos en comodato
- Activos utilizados en operación de maquila

**Excluye:**
- Activos propios de la empresa (`FLG_PROPIO = 1`)
- Terrenos (tasa de depreciación = 0)

### Clasificación

1. **Activos Extranjeros** (`ID_PAIS > 1`)
   - Cálculo más simple
   - Aplica regla del 10% MOI (Art 182 LISR)
   - Conversión a MXN con TC del 30 de junio

2. **Activos Mexicanos** (`ID_PAIS = 1`)
   - Cálculo con actualización INPC
   - Usa valor promedio anual
   - Ya en pesos mexicanos

---

## 2. DATOS DE LA BASE DE DATOS

### Query Principal

```sql
SELECT
    -- Identificación
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO AS Placa,
    a.DESCRIPCION,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.NOMBRE AS TipoActivo,

    -- Datos financieros
    a.COSTO_ADQUISICION AS MOI,
    a.ID_MONEDA,
    a.ID_PAIS,
    p.NOMBRE AS NombrePais,

    -- Fechas
    a.FECHA_COMPRA AS FechaAdquisicion,
    a.FECHA_BAJA,
    a.STATUS,

    -- *** TASA DE DEPRECIACIÓN ***
    pd.PORCENTAJE AS TasaAnual,
    pd.PORCENTAJE / 12.0 AS TasaMensual,  -- Ya NO se calcula, viene de la tabla

    -- Depreciación acumulada al inicio del año
    COALESCE(c.ACUMULADO_HISTORICA, 0) AS DepAcumInicio,

    -- INPC (solo para activos mexicanos)
    inpc_adq.Indice AS INPC_Adqu,
    inpc_mitad_ej.Indice AS INPC_MitadEjercicio

FROM activo a

-- *** IMPORTANTE: Join con porcentaje_depreciacion ***
INNER JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2  -- Fiscal

INNER JOIN tipo_activo ta
    ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

INNER JOIN pais p
    ON a.ID_PAIS = p.ID_PAIS

-- Depreciación acumulada del año anterior
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_COMPANIA = a.ID_COMPANIA
    AND c.ID_ANO = @AñoAnterior  -- 2023 para ejercicio 2024
    AND c.ID_MES = 12            -- Diciembre
    AND c.ID_TIPO_DEP = 2        -- Fiscal

-- INPC de adquisición (solo para activos mexicanos)
LEFT JOIN INPC2 inpc_adq
    ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
    AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
    AND inpc_adq.Id_Pais = 1     -- México
    AND inpc_adq.Id_Tipo_Dep = 2 -- Fiscal

-- INPC de mitad del ejercicio (junio del año de cálculo)
LEFT JOIN INPC2 inpc_mitad_ej
    ON inpc_mitad_ej.Anio = @AñoCalculo  -- 2024
    AND inpc_mitad_ej.Mes = 6            -- Junio
    AND inpc_mitad_ej.Id_Pais = 1
    AND inpc_mitad_ej.Id_Tipo_Dep = 2

WHERE a.FLG_PROPIO = 0         -- *** FILTRO CRÍTICO: Solo NO propios ***
  AND a.ID_COMPANIA = @IdCompania
  AND a.STATUS = 'A'           -- Solo activos activos

ORDER BY a.ID_PAIS, a.ID_NUM_ACTIVO
```

### Nota Importante sobre porcentaje_depreciacion

**Estructura esperada de la tabla:**

```sql
CREATE TABLE porcentaje_depreciacion (
    ID_TIPO_ACTIVO int,
    ID_SUBTIPO_ACTIVO int,
    ID_TIPO_DEP int,       -- 1=Contable, 2=Fiscal, 3=IFRS
    PORCENTAJE decimal,     -- Tasa anual (ej: 0.08 para 8%)
    PRIMARY KEY (ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO, ID_TIPO_DEP)
);
```

**No se calcula `PORCENTAJE / 12` en código, se obtiene directamente:**

```csharp
// INCORRECTO (método del Excel de ejemplo):
decimal tasaMensual = tasaAnual / 12;

// CORRECTO (en producción, viene de la tabla):
decimal tasaMensual = row.TasaMensual; // Ya viene de porcentaje_depreciacion
```

---

## 3. TIPO DE CAMBIO

### Para Activos Extranjeros

**Fuente:** Tipo de cambio del **30 de junio del año de cálculo**

**Query sugerido:**

```sql
SELECT TipoCambio
FROM tipo_cambio  -- O tabla correspondiente en Actif
WHERE Fecha = CAST(@AñoCalculo + '-06-30' AS DATE)
  AND ID_MONEDA = 2  -- USD (o la moneda correspondiente)
```

**Alternativa si no existe tabla de tipo_cambio:**
- Consultar API externa (Banxico, etc.)
- Configurar manualmente en `appsettings.json`
- Registrar en tabla de configuración

**Ejemplo para 2024:**
- TC del 30 de junio de 2024: **18.2478 MXN/USD**

---

## 4. INPC (Solo para Activos Mexicanos)

### INPC Necesarios

1. **INPC de Adquisición** (columna L)
   - Año y mes de `FECHA_COMPRA` del activo

2. **INPC de Mitad del Ejercicio** (columna M)
   - Junio del año de cálculo (ej: junio 2024)

3. **INPC de Mitad del Periodo** (columna S)
   - Varía según el escenario del activo
   - Se calcula dinámicamente

### Query INPC de Mitad del Periodo

```csharp
// Determinar qué mes de INPC usar
int mesINPC;
if (activo.FechaAdquisicion.Year < añoCalculo)
{
    // Activo existente: junio
    mesINPC = 6;
}
else if (activo.FechaAdquisicion.Month <= 6)
{
    // Adquirido antes de junio: mitad del periodo de uso
    int mesesUso = 10; // Ejemplo: marzo a diciembre
    mesINPC = activo.FechaAdquisicion.Month + (mesesUso / 2);
}
else
{
    // Adquirido después de junio
    int mesesDesdeAdq = 12 - activo.FechaAdquisicion.Month + 1;
    mesINPC = activo.FechaAdquisicion.Month + (mesesDesdeAdq / 2);
}

// Query el INPC
SELECT Indice
FROM INPC2
WHERE Anio = @AñoCalculo
  AND Mes = @MesINPC
  AND Id_Pais = 1
  AND Id_Tipo_Dep = 2
```

---

## 5. FÓRMULAS RESUMIDAS

### Activos Extranjeros

```csharp
// 1. Datos base
decimal tasaMensual = row.TasaMensual;  // De porcentaje_depreciacion
decimal depAcumInicio = row.DepAcumInicio;  // De calculo año anterior

// 2. Calcular meses
int mesesHastaMitadPeriodo = CalcularMesesHastaMitad(...);
int mesesUsoEjercicio = CalcularMesesEnEjercicio(...);

// 3. Saldo y depreciación
decimal saldoInicio = MOI - depAcumInicio;
decimal depEjercicio = MOI * tasaMensual * mesesHastaMitadPeriodo;

// 4. Monto pendiente
decimal montoPendiente = saldoInicio - depEjercicio;
decimal proporcion = (montoPendiente / 12) * mesesUsoEjercicio;

// 5. Aplicar regla 10% MOI
decimal prueba10Pct = MOI * 0.10m;
decimal valorUSD = proporcion > prueba10Pct ? proporcion : prueba10Pct;

// 6. Convertir a MXN
decimal valorFinal = valorUSD * tipoCambio30Junio;
```

### Activos Mexicanos

```csharp
// 1-3. Igual que extranjeros

// 4. Factores INPC
decimal factorSaldo = Math.Truncate((inpcJunio / inpcAdqu) * 10000) / 10000;
decimal saldoActualizado = saldoInicio * factorSaldo;

// 5. Depreciación actualizada
decimal depEjercicio = MOI * tasaMensual * mesesUsoEjercicio;
decimal factorDep = Math.Truncate((inpcMitadPeriodo / inpcAdqu) * 10000) / 10000;
decimal depActualizada = depEjercicio * factorDep;

// 6. Valor promedio
decimal mitadDep = depActualizada * 0.50m;
decimal valorPromedio = saldoActualizado - mitadDep;

// 7. Valor final proporcional
decimal valorFinal = (valorPromedio / 12) * mesesUsoEjercicio;
```

---

## 6. ESTRUCTURA DE LA SOLUCIÓN

### Proyecto .NET 9

```
ActifRMF/
├── ActifRMF.csproj
├── Program.cs
├── appsettings.json
├── Services/
│   ├── ActivoExtranjeroService.cs
│   ├── ActivoMexicanoService.cs
│   ├── INPCService.cs
│   ├── TipoCambioService.cs
│   └── ReporteService.cs
├── Models/
│   ├── ActivoDto.cs
│   ├── CalculoResultado.cs
│   └── ConfiguracionCompania.cs
├── Repositories/
│   ├── ActivoRepository.cs
│   ├── CalculoRepository.cs
│   └── INPCRepository.cs
└── Utils/
    └── FechasHelper.cs
```

### Endpoints Propuestos

```csharp
// Calcular para una compañía y año específico
POST /api/calculo/ejecutar
{
    "idCompania": 1,
    "añoCalculo": 2024
}

// Obtener reporte
GET /api/reporte/{idCompania}/{añoCalculo}/activos-extranjeros
GET /api/reporte/{idCompania}/{añoCalculo}/activos-mexicanos

// Obtener detalle de un activo
GET /api/calculo/activo/{idNumActivo}/{añoCalculo}
```

---

## 7. VALIDACIONES REQUERIDAS

### Antes del Cálculo

```csharp
// 1. Verificar que existe porcentaje de depreciación
if (tasaAnual == null || tasaMensual == null)
    throw new Exception($"No existe tasa de depreciación fiscal para " +
        $"Tipo={idTipoActivo}, Subtipo={idSubtipoActivo}");

// 2. Verificar INPC (solo mexicanos)
if (idPais == 1 && (inpcAdqu == null || inpcMitadEj == null))
    throw new Exception($"No existe INPC para la fecha de adquisición " +
        $"o junio de {añoCalculo}");

// 3. Verificar tipo de cambio (solo extranjeros)
if (idPais > 1 && tipoCambio30Junio == null)
    throw new Exception($"No existe tipo de cambio para el 30 de junio de {añoCalculo}");

// 4. Verificar fecha de adquisición
if (fechaAdquisicion > new DateTime(añoCalculo, 12, 31))
    continue; // Activo adquirido después del año de cálculo, saltar

// 5. Terrenos
if (tasaAnual == 0)
    continue; // Los terrenos no se deprecian, saltar
```

### Durante el Cálculo

```csharp
// 1. Validar que saldos no sean negativos
if (saldoInicio < 0) saldoInicio = 0;
if (montoPendiente < 0) montoPendiente = 0;

// 2. Validar que la depreciación no exceda el saldo
if (depEjercicio > saldoInicio)
    depEjercicio = saldoInicio;

// 3. Validar factores INPC
if (factorActualizacion <= 0)
    throw new Exception("Factor INPC inválido");

// 4. Validar meses
if (mesesUsoEjercicio < 0 || mesesUsoEjercicio > 12)
    throw new Exception($"Meses de uso inválidos: {mesesUsoEjercicio}");
```

---

## 8. CONFIGURACIÓN

### appsettings.json

```json
{
  "ConnectionStrings": {
    "ActifSourceDefault": "Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=***;TrustServerCertificate=True;",
    "ActifRMF": "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=***;TrustServerCertificate=True;"
  },
  "CalculoRMF": {
    "AñoCalculo": 2024,
    "TipoCambio30Junio": 18.2478,
    "AplicarRegla10PorMOI": true,
    "SoloActivosNoPropio": true
  }
}
```

---

## 9. ORDEN DE IMPLEMENTACIÓN SUGERIDO

### Fase 1: Infraestructura (1-2 días)
1. ✅ Crear proyecto .NET 9
2. ✅ Configurar conexión a BD
3. ✅ Crear modelos y DTOs
4. ✅ Implementar repositorios base

### Fase 2: Servicios de Datos (2-3 días)
5. Query principal de activos
6. Servicio INPC
7. Servicio Tipo de Cambio
8. Helper de cálculo de fechas

### Fase 3: Lógica de Cálculo (3-4 días)
9. Servicio Activos Extranjeros
10. Servicio Activos Mexicanos
11. Pruebas unitarias con datos del Excel

### Fase 4: Reportes (2-3 días)
12. Servicio de generación de reportes
13. Endpoints API
14. Exportación a Excel

### Fase 5: Pruebas y Ajustes (2-3 días)
15. Pruebas con datos reales
16. Validación con contador/auditor
17. Documentación final

**TOTAL ESTIMADO:** 10-15 días hábiles

---

## 10. PREGUNTAS PENDIENTES

1. ✅ **¿Solo activos NO propios?** → **SÍ, confirmado `FLG_PROPIO = 0`**
2. ✅ **¿Dónde está el 10% MOI en la ley?** → **Art 182 LISR (Maquiladoras)**
3. ✅ **¿Cómo obtener depreciación acumulada?** → **Tabla `calculo`, campo `ACUMULADO_HISTORICA`, Dic año anterior**
4. ✅ **¿Tasa mensual calculada o de tabla?** → **De tabla `porcentaje_depreciacion`**
5. ❓ **¿Dónde obtener tipo de cambio?** → Pendiente confirmar fuente
6. ❓ **¿Guardar resultados en Actif_RMF?** → Pendiente diseñar esquema
7. ❓ **¿Formato de reportes?** → Excel, PDF, o ambos?

---

## 11. DOCUMENTOS DE REFERENCIA

1. **README.md** - Visión general del sistema
2. **DICCIONARIO_DATOS.md** - Estructura de tablas Actif
3. **RMF.md** - Marco legal LISR Artículos 31-35
4. **ARTICULO_182_LISR.md** - Regla del 10% MOI para maquiladoras
5. **FORMULAS_EXCEL_COMPLETAS.md** - Fórmulas detalladas con ejemplos
6. **HALLAZGOS_EXCEL.md** - Análisis inicial del Excel
7. **FORMULAS_EXACTAS.md** - Primera versión de fórmulas
8. **Este documento** - Guía de implementación

---

**Siguiente paso sugerido:** Implementar el `ActivoRepository` con el query principal y comenzar con el servicio de cálculo para activos extranjeros (más simple).
