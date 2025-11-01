# Cálculo Fiscal Simulado para Activos Extranjeros (Solo USGAAP)

## Propósito

Este módulo calcula la depreciación fiscal **simulada** para activos **extranjeros** que:
- Tienen costo en slot USGAAP: **`COSTO_REEXPRESADO > 0`**
- **NO** tienen costo en slot Fiscal: **`COSTO_REVALUADO = 0 o NULL`**

Estos activos son típicamente **activos de propiedad extranjera** (de otra empresa) que se manejan contablemente en USGAAP pero que requieren un cálculo fiscal simulado para reportes de Safe Harbor.

## Criterios de Clasificación de Activos

El sistema clasifica activos en 3 categorías basándose en los campos de costo:

| Categoría | Criterio | Proceso |
|-----------|----------|---------|
| **Activos Extranjeros (Fiscal Simulado)** | `COSTO_REEXPRESADO > 0` AND `(COSTO_REVALUADO = 0 OR COSTO_REVALUADO IS NULL)` | Calcular fiscal simulado |
| **Activos Nacionales (Fiscal Real)** | `COSTO_REVALUADO > 0` AND `(COSTO_REEXPRESADO = 0 OR COSTO_REEXPRESADO IS NULL)` | Usar cálculo fiscal existente |
| **Activos Ambiguos (Error)** | `COSTO_REEXPRESADO > 0` AND `COSTO_REVALUADO > 0` | **Reportar como conflicto** |

**Importante:** Si un activo tiene ambos costos > 0, se considera un error de configuración y debe reportarse para revisión manual.

---

## Flujo del Sistema

```
┌─────────────────────────────────────────────────────────┐
│ 1. ETL - Importación Completa de Activos               │
│    sp_ETL_Importar_Activos_Completo                    │
│    - Carga TODOS los activos activos (Safe Harbor)     │
│    - Incluye COSTO_REEXPRESADO (slot USGAAP)           │
│    - Incluye COSTO_REVALUADO (slot Fiscal)             │
│    - Incluye FECHA_INIC_DEPREC, FECHA_INIC_DEPREC_3    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Clasificación de Activos                            │
│    - COSTO_REEXPRESADO > 0 y REVALUADO = 0             │
│      → Activo Extranjero (fiscal simulado)             │
│    - COSTO_REVALUADO > 0 y REEXPRESADO = 0             │
│      → Activo Nacional (fiscal real)                   │
│    - Ambos > 0 → Reporte de Ambigüedad                 │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Cálculo Fiscal Simulado (solo extranjeros)          │
│    sp_Calcular_Fiscal_Simulado                         │
│    - Convierte COSTO_REEXPRESADO a pesos               │
│    - Usa porcentaje fiscal de catálogo                 │
│    - Calcula acumulado hasta Dic año anterior          │
│    - Guarda en tabla Calculo_Fiscal_Simulado           │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 4. Cálculo RMF Safe Harbor                             │
│    sp_Calcular_RMF_Safe_Harbor                         │
│    - Nacionales: usa Dep_Acum_Inicio_Año (fiscal real) │
│    - Extranjeros: usa Dep_Acum_Año_Anterior_Simulada   │
│    - Calcula valor reportable según Art 182 LISR       │
└─────────────────────────────────────────────────────────┘
```

---

## Tablas Involucradas

### 1. Staging_Activo (Modificada)

Campos críticos para clasificación:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| **COSTO_REEXPRESADO** | decimal(18,4) | **Slot USGAAP** - Si > 0, activo extranjero |
| **COSTO_REVALUADO** | decimal(18,4) | **Slot Fiscal** - Si > 0, activo nacional |
| **FECHA_INIC_DEPREC** | datetime | Fecha de inicio depreciación fiscal |
| **FECHA_INIC_DEPREC_3** | datetime | Fecha de inicio depreciación USGAAP |
| **ID_MONEDA** | int | Moneda del activo (para conversión) |

**Regla de Clasificación:**
```sql
CASE
    WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
        THEN 'Extranjero - Fiscal Simulado'
    WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
        THEN 'Nacional - Fiscal Real'
    WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
        THEN 'AMBIGUO - REQUIERE REVISIÓN'
    ELSE 'Sin Costo Definido'
END
```

### 2. Calculo_Fiscal_Simulado (Nueva)

Tabla con relación 1 a 1 con Staging_Activo.

| Campo | Tipo | Descripción |
|-------|------|-------------|
| ID_Calculo_Fiscal_Simulado | bigint | PK |
| **ID_Staging** | bigint | FK a Staging_Activo (UNIQUE) |
| ID_Compania | int | Compañía |
| ID_NUM_ACTIVO | int | Activo |
| Año_Calculo | int | Año fiscal |
| COSTO_REEXPRESADO | decimal(18,4) | Costo USGAAP original |
| ID_MONEDA | int | Moneda del costo USGAAP |
| **Tipo_Cambio_30_Junio** | decimal(10,6) | TC del 30 junio del año de cálculo |
| **Costo_Fiscal_Simulado_MXN** | decimal(18,4) | COSTO_REEXPRESADO × TC |
| FECHA_INIC_DEPREC_3 | datetime | Fecha inicio USGAAP |
| Tasa_Anual_Fiscal | decimal(10,6) | De porcentaje_depreciacion |
| Tasa_Mensual_Fiscal | decimal(10,6) | Tasa_Anual / 12 |
| Fecha_Corte_Calculo | date | 31/Dic del año anterior |
| Meses_Depreciados | int | Desde FECHA_INIC_DEPREC_3 hasta corte |
| Dep_Mensual_Simulada | decimal(18,4) | Costo_MXN × Tasa_Mensual |
| **Dep_Acum_Año_Anterior_Simulada** | decimal(18,4) | **CAMPO OBJETIVO** |
| Observaciones | nvarchar(500) | Detalles del cálculo |

---

## Lógica de Cálculo Fiscal Simulado

### Paso 1: Identificar Activos Elegibles

**Criterio:** Activos extranjeros con COSTO_REEXPRESADO pero sin COSTO_REVALUADO

```sql
SELECT *
FROM Staging_Activo
WHERE COSTO_REEXPRESADO IS NOT NULL
  AND COSTO_REEXPRESADO > 0                      -- Tiene costo USGAAP
  AND ISNULL(COSTO_REVALUADO, 0) = 0             -- NO tiene costo fiscal
  AND FECHA_INIC_DEPREC_3 IS NOT NULL            -- Tiene fecha de inicio USGAAP
```

### Paso 1.1: Detectar Activos Ambiguos

**Activos con ambos costos deben reportarse como error:**

```sql
SELECT *
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0
-- Estos activos van a un reporte de ambigüedad para revisión manual
```

### Paso 2: Convertir Costo USGAAP a Pesos

```
Costo_Fiscal_Simulado_MXN = COSTO_REEXPRESADO × Tipo_Cambio_30_Junio
```

**Tipo de cambio**: Del 30 de junio **del año de cálculo** (no del año anterior).

### Paso 3: Obtener Porcentaje Fiscal

Buscar en la base de datos origen (Actif):

```sql
SELECT PORC_SEGUNDO_ANO
FROM porcentaje_depreciacion
WHERE ID_TIPO_DEP = 2  -- Fiscal
  AND ID_TIPO_ACTIVO = @ID_TIPO_ACTIVO
  AND ID_SUBTIPO_ACTIVO = @ID_SUBTIPO_ACTIVO
```

Convertir a tasa mensual:

```
Tasa_Mensual_Fiscal = Tasa_Anual_Fiscal / 12.0
```

### Paso 4: Calcular Meses Depreciados

Desde `FECHA_INIC_DEPREC_3` hasta **31 de diciembre del año anterior**:

```sql
DECLARE @Fecha_Corte DATE = CAST((@Año_Calculo - 1) + '-12-31' AS DATE);

IF @FECHA_INIC_DEPREC_3 > @Fecha_Corte
    SET @Meses_Depreciados = 0;  -- Activo inicia después del corte
ELSE
    SET @Meses_Depreciados = DATEDIFF(MONTH, @FECHA_INIC_DEPREC_3, @Fecha_Corte) + 1;
```

### Paso 5: Calcular Depreciación Acumulada Simulada

```
Dep_Mensual_Simulada = Costo_Fiscal_Simulado_MXN × (Tasa_Mensual_Fiscal / 100)

Dep_Acum_Año_Anterior_Simulada = Dep_Mensual_Simulada × Meses_Depreciados
```

Validación: No puede exceder el 100%:

```sql
IF @Dep_Acum_Simulada > @Costo_Fiscal_Simulado_MXN
    SET @Dep_Acum_Simulada = @Costo_Fiscal_Simulado_MXN;
```

---

## Ejemplo Numérico

### Datos del Activo

- **Activo**: Equipo de Cómputo HP (ID_NUM_ACTIVO = 5000)
- **Propiedad**: No propia (de otra empresa)
- **FLG_NOCAPITALIZABLE_2**: NULL (no tiene fiscal)
- **FLG_NOCAPITALIZABLE_3**: 'S' (tiene USGAAP)
- **COSTO_REEXPRESADO**: $10,000 USD
- **FECHA_INIC_DEPREC_3**: 01/01/2022
- **ID_TIPO_ACTIVO**: 2813 (Equipo de Cómputo)
- **ID_SUBTIPO_ACTIVO**: 2813
- **Año de Cálculo**: 2024

### Cálculo

#### 1. Tipo de Cambio
```
Tipo_Cambio_30_Junio_2024 = 18.50 MXN/USD
```

#### 2. Convertir a Pesos
```
Costo_Fiscal_Simulado_MXN = $10,000 USD × 18.50 = $185,000 MXN
```

#### 3. Porcentaje Fiscal
De `porcentaje_depreciacion` con ID_TIPO_DEP=2, Tipo=2813, Subtipo=2813:
```
Tasa_Anual_Fiscal = 30%
Tasa_Mensual_Fiscal = 30% / 12 = 2.5%
```

#### 4. Meses Depreciados
```
Desde: 01/01/2022
Hasta: 31/12/2023 (año anterior a 2024)
Meses = DATEDIFF(MONTH, '2022-01-01', '2023-12-31') + 1 = 24 meses
```

#### 5. Depreciación Acumulada Simulada
```
Dep_Mensual_Simulada = $185,000 × (2.5% / 100) = $185,000 × 0.025 = $4,625 MXN

Dep_Acum_Año_Anterior_Simulada = $4,625 × 24 = $111,000 MXN
```

#### 6. Validación
```
$111,000 < $185,000 ✓ (no excede el 100%)
```

### Resultado

El activo tendrá en `Calculo_Fiscal_Simulado`:

| Campo | Valor |
|-------|-------|
| Costo_Fiscal_Simulado_MXN | $185,000 |
| Tasa_Anual_Fiscal | 30% |
| Meses_Depreciados | 24 |
| Dep_Mensual_Simulada | $4,625 |
| **Dep_Acum_Año_Anterior_Simulada** | **$111,000** |

Este valor se usará en el cálculo Safe Harbor en lugar de `Dep_Acum_Inicio_Año`.

---

## Integración con Safe Harbor

En el cálculo Safe Harbor (`sp_Calcular_RMF_Safe_Harbor`), se debe modificar para usar:

```sql
-- Lógica de depreciación acumulada
DECLARE @Dep_Acum_Inicio DECIMAL(18,4);

-- Verificar si tiene fiscal simulado
SELECT @Dep_Acum_Inicio = Dep_Acum_Año_Anterior_Simulada
FROM Calculo_Fiscal_Simulado
WHERE ID_Staging = @ID_Staging;

-- Si no tiene fiscal simulado, usar fiscal real
IF @Dep_Acum_Inicio IS NULL
    SET @Dep_Acum_Inicio = @Dep_Acum_Inicio_Año_Staging;
```

---

## Casos Especiales

### 1. Activo sin Porcentaje Fiscal en Catálogo

Si no se encuentra en `porcentaje_depreciacion`:

```
Tasa_Anual_Fiscal = 0
Dep_Acum_Año_Anterior_Simulada = 0
Observaciones = "No se encontró porcentaje fiscal para Tipo=X, Subtipo=Y"
```

### 2. Activo que Inicia Depreciación Después del Corte

Si `FECHA_INIC_DEPREC_3 > 31/Dic/AñoAnterior`:

```
Meses_Depreciados = 0
Dep_Acum_Año_Anterior_Simulada = 0
Observaciones = "Activo inicia depreciación después del 31/12/2023"
```

### 3. Activo con Depreciación > 100%

```
IF Dep_Acum_Simulada > Costo_Fiscal_Simulado_MXN:
    Dep_Acum_Simulada = Costo_Fiscal_Simulado_MXN
    Observaciones += " Depreciación limitada al 100% del costo."
```

---

## Stored Procedures

### 1. sp_ETL_Importar_Activos_Completo

**Archivo**: `13_SP_ETL_Importar_Activos_Completo.sql`

**Parámetros**:
- `@ID_Compania INT`
- `@Año_Calculo INT`
- `@Usuario NVARCHAR(100)` (opcional)

**Función**: Importa todos los activos activos incluyendo campos para fiscal simulado.

### 2. sp_Calcular_Fiscal_Simulado

**Archivo**: `12_SP_Calcular_Fiscal_Simulado.sql`

**Parámetros**:
- `@ID_Compania INT`
- `@Año_Calculo INT`
- `@Lote_Importacion UNIQUEIDENTIFIER`
- `@ConnectionString_Actif NVARCHAR(500)`

**Función**: Calcula depreciación fiscal simulada para activos con solo USGAAP.

**Resultado**: Registros en tabla `Calculo_Fiscal_Simulado`.

### 3. sp_Calcular_RMF_Safe_Harbor (Modificado)

**Archivo**: `06_SP_Calcular_RMF_Safe_Harbor.sql`

**Modificación necesaria**: Integrar lógica para usar fiscal simulado cuando aplique.

---

## Ejecución Completa

**Archivo**: `14_EXEC_Flujo_Completo_RMF.sql`

```sql
-- Paso 1: ETL
EXEC sp_ETL_Importar_Activos_Completo
    @ID_Compania = 1,
    @Año_Calculo = 2024;

-- Paso 2: Fiscal Simulado
EXEC sp_Calcular_Fiscal_Simulado
    @ID_Compania = 1,
    @Año_Calculo = 2024,
    @Lote_Importacion = @Lote,
    @ConnectionString_Actif = @ConnStr;

-- Paso 3: Safe Harbor
EXEC sp_Calcular_RMF_Safe_Harbor
    @ID_Compania = 1,
    @Año_Calculo = 2024,
    @Lote_Importacion = @Lote;
```

---

## Queries Útiles

### Ver Activos que Requieren Fiscal Simulado

```sql
-- Activos extranjeros (fiscal simulado)
SELECT
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    COSTO_REEXPRESADO AS Costo_USGAAP,
    COSTO_REVALUADO AS Costo_Fiscal,
    FECHA_INIC_DEPREC_3,
    'Extranjero - Requiere Fiscal Simulado' AS Tipo
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND ISNULL(COSTO_REVALUADO, 0) = 0
ORDER BY ID_NUM_ACTIVO;
```

### Ver Activos Ambiguos (Requieren Revisión)

```sql
-- Activos con ambos costos - ERROR
SELECT
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    COSTO_REEXPRESADO AS Costo_USGAAP,
    COSTO_REVALUADO AS Costo_Fiscal,
    'AMBIGUO - REVISAR' AS Estado
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0
ORDER BY ID_NUM_ACTIVO;
```

### Ver Resultados de Fiscal Simulado

```sql
SELECT
    s.ID_NUM_ACTIVO,
    s.ID_ACTIVO,
    s.DESCRIPCION,
    fs.COSTO_REEXPRESADO,
    fs.Tipo_Cambio_30_Junio,
    fs.Costo_Fiscal_Simulado_MXN,
    fs.Tasa_Anual_Fiscal,
    fs.Meses_Depreciados,
    fs.Dep_Acum_Año_Anterior_Simulada,
    fs.Observaciones
FROM Staging_Activo s
INNER JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
WHERE s.ID_Compania = 1
  AND s.Año_Calculo = 2024
ORDER BY s.ID_NUM_ACTIVO;
```

### Comparar Fiscal Real vs Simulado

```sql
SELECT
    s.ID_NUM_ACTIVO,
    s.DESCRIPCION,
    s.COSTO_REVALUADO,
    s.COSTO_REEXPRESADO,
    s.Dep_Acum_Inicio_Año AS Fiscal_Real,
    fs.Dep_Acum_Año_Anterior_Simulada AS Fiscal_Simulado,
    CASE
        WHEN s.COSTO_REVALUADO > 0 AND ISNULL(s.COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Usa Fiscal Real'
        WHEN s.COSTO_REEXPRESADO > 0 AND ISNULL(s.COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Usa Fiscal Simulado'
        WHEN s.COSTO_REEXPRESADO > 0 AND s.COSTO_REVALUADO > 0
            THEN 'AMBIGUO - ERROR'
        ELSE 'Sin Costo Definido'
    END AS Tipo_Activo
FROM Staging_Activo s
LEFT JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
WHERE s.ID_Compania = 1
  AND s.Año_Calculo = 2024
ORDER BY Tipo_Activo, s.ID_NUM_ACTIVO;
```

### Resumen de Clasificación

```sql
SELECT
    CASE
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN 'AMBIGUO - REVISAR'
        ELSE 'Sin Costo'
    END AS Tipo_Activo,
    COUNT(*) AS Cantidad,
    SUM(ISNULL(COSTO_REVALUADO, 0)) AS Total_Costo_Fiscal,
    SUM(ISNULL(COSTO_REEXPRESADO, 0)) AS Total_Costo_USGAAP
FROM Staging_Activo
WHERE ID_Compania = 1
  AND Año_Calculo = 2024
GROUP BY
    CASE
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN 'AMBIGUO - REVISAR'
        ELSE 'Sin Costo'
    END
ORDER BY Tipo_Activo;
```

---

## Archivos SQL Creados

| # | Archivo | Descripción |
|---|---------|-------------|
| 11 | `11_CREATE_Calculo_Fiscal_Simulado.sql` | Crea tabla y agrega campos a Staging |
| 12 | `12_SP_Calcular_Fiscal_Simulado.sql` | Stored procedure de cálculo |
| 13 | `13_SP_ETL_Importar_Activos_Completo.sql` | ETL completo con nuevos campos |
| 14 | `14_EXEC_Flujo_Completo_RMF.sql` | Script de ejecución completa |

---

## Versión

- **Versión**: 1.0.0
- **Fecha**: 2025-10-18
- **Proyecto**: ActifRMF
- **Base de Datos**: Actif_RMF

---

## Pendientes

- [ ] Modificar `sp_Calcular_RMF_Safe_Harbor` para integrar fiscal simulado
- [ ] Pruebas con datos reales
- [ ] Validar tipo de cambio del 30 junio
- [ ] Documentar casos edge adicionales
