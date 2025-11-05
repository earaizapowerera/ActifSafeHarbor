# Casos de Uso para Testing Exhaustivo

## Casos de Uso EXTRANJEROS (ManejaUSGAAP='S')

Compañías objetivo: **122, 188**

### 1. EXT-BAJA: Activo dado de baja en 2024
**Criterio:**
```sql
FECHA_BAJA IS NOT NULL
AND YEAR(FECHA_BAJA) = 2024
AND ManejaUSGAAP = 'S'
AND CostoUSD > 0
```

### 2. EXT-ANTES-JUN: Adquirido entre Ene-Jun 2024
**Criterio:**
```sql
FECHA_COMPRA >= '2024-01-01'
AND FECHA_COMPRA <= '2024-06-30'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaUSGAAP = 'S'
AND CostoUSD > 0
```

### 3. EXT-DESP-JUN: Adquirido después de Jun 2024
**Criterio:**
```sql
FECHA_COMPRA > '2024-06-30'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaUSGAAP = 'S'
AND CostoUSD > 0
```

### 4. EXT-10PCT: Aplica regla 10% MOI
**Criterio:**
```sql
FECHA_COMPRA < '2024-01-01'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaUSGAAP = 'S'
AND CostoUSD > 0
-- Y donde Proporcion <= (MOI * 0.10)
```

### 5. EXT-NORMAL: En uso normal
**Criterio:**
```sql
FECHA_COMPRA < '2024-01-01'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaUSGAAP = 'S'
AND CostoUSD > 0
-- Y donde Proporcion > (MOI * 0.10)
```

---

## Casos de Uso NACIONALES (ManejaFiscal='S')

Compañías objetivo: **123, 188**

### 1. NAC-BAJA: Activo dado de baja en 2024
**Criterio:**
```sql
FECHA_BAJA IS NOT NULL
AND YEAR(FECHA_BAJA) = 2024
AND ManejaFiscal = 'S'
AND CostoMXN > 0
```

### 2. NAC-ANTES-JUN: Adquirido entre Ene-Jun 2024
**Criterio:**
```sql
FECHA_COMPRA >= '2024-01-01'
AND FECHA_COMPRA <= '2024-06-30'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaFiscal = 'S'
AND CostoMXN > 0
```

### 3. NAC-DESP-JUN: Adquirido después de Jun 2024
**Criterio:**
```sql
FECHA_COMPRA > '2024-06-30'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaFiscal = 'S'
AND CostoMXN > 0
```

### 4. NAC-10PCT: Aplica regla 10% MOI
**Criterio:**
```sql
FECHA_COMPRA < '2024-01-01'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaFiscal = 'S'
AND CostoMXN > 0
-- Y donde Proporcion <= (MOI * 0.10)
```

### 5. NAC-NORMAL: En uso normal
**Criterio:**
```sql
FECHA_COMPRA < '2024-01-01'
AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)
AND ManejaFiscal = 'S'
AND CostoMXN > 0
-- Y donde Proporcion > (MOI * 0.10)
```

---

## Queries de Búsqueda

### Extranjeros - Compañía 122
```sql
-- Buscar casos de uso extranjeros
SELECT
    'EXT-BAJA' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REEXPRESADO,
    FLG_NOCAPITALIZABLE_3 as ManejaUSGAAP
FROM activo
WHERE ID_COMPANIA = 122
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_3 = 'S'
  AND COSTO_REEXPRESADO > 0
  AND FECHA_BAJA IS NOT NULL
  AND YEAR(FECHA_BAJA) = 2024

UNION ALL

SELECT
    'EXT-ANTES-JUN' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REEXPRESADO,
    FLG_NOCAPITALIZABLE_3
FROM activo
WHERE ID_COMPANIA = 122
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_3 = 'S'
  AND COSTO_REEXPRESADO > 0
  AND FECHA_COMPRA >= '2024-01-01'
  AND FECHA_COMPRA <= '2024-06-30'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

UNION ALL

SELECT
    'EXT-DESP-JUN' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REEXPRESADO,
    FLG_NOCAPITALIZABLE_3
FROM activo
WHERE ID_COMPANIA = 122
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_3 = 'S'
  AND COSTO_REEXPRESADO > 0
  AND FECHA_COMPRA > '2024-06-30'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

UNION ALL

SELECT
    'EXT-NORMAL-O-10PCT' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REEXPRESADO,
    FLG_NOCAPITALIZABLE_3
FROM activo
WHERE ID_COMPANIA = 122
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_3 = 'S'
  AND COSTO_REEXPRESADO > 0
  AND FECHA_COMPRA < '2024-01-01'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

ORDER BY Caso_Uso, ID_NUM_ACTIVO;
```

### Nacionales - Compañía 123
```sql
-- Buscar casos de uso nacionales
SELECT
    'NAC-BAJA' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REVALUADO,
    FLG_NOCAPITALIZABLE_2 as ManejaFiscal
FROM activo
WHERE ID_COMPANIA = 123
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_2 = 'S'
  AND COSTO_REVALUADO > 0
  AND FECHA_BAJA IS NOT NULL
  AND YEAR(FECHA_BAJA) = 2024

UNION ALL

SELECT
    'NAC-ANTES-JUN' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REVALUADO,
    FLG_NOCAPITALIZABLE_2
FROM activo
WHERE ID_COMPANIA = 123
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_2 = 'S'
  AND COSTO_REVALUADO > 0
  AND FECHA_COMPRA >= '2024-01-01'
  AND FECHA_COMPRA <= '2024-06-30'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

UNION ALL

SELECT
    'NAC-DESP-JUN' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REVALUADO,
    FLG_NOCAPITALIZABLE_2
FROM activo
WHERE ID_COMPANIA = 123
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_2 = 'S'
  AND COSTO_REVALUADO > 0
  AND FECHA_COMPRA > '2024-06-30'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

UNION ALL

SELECT
    'NAC-NORMAL-O-10PCT' as Caso_Uso,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    FECHA_COMPRA,
    FECHA_BAJA,
    COSTO_REVALUADO,
    FLG_NOCAPITALIZABLE_2
FROM activo
WHERE ID_COMPANIA = 123
  AND STATUS = 'A'
  AND FLG_NOCAPITALIZABLE_2 = 'S'
  AND COSTO_REVALUADO > 0
  AND FECHA_COMPRA < '2024-01-01'
  AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) != 2024)

ORDER BY Caso_Uso, ID_NUM_ACTIVO;
```

---

## Lista de Activos para Testing

### ✅ Extranjeros - ENCONTRADOS

#### Compañía 122 (Toluca)
- [x] **EXT-BAJA**: NO DISPONIBLE (usar compañía 188)
- [x] **EXT-ANTES-JUN**: ID_NUM_ACTIVO = **2962147** (Conveyor, Feb 2024, $80,773)
- [x] **EXT-DESP-JUN**: NO DISPONIBLE (no hay activos después de jun 2024)
- [x] **EXT-NORMAL-1**: ID_NUM_ACTIVO = **117930** (Building, Nov 2009, $9,248,494)
- [x] **EXT-NORMAL-2**: ID_NUM_ACTIVO = **117933** (Building, Nov 2009, $5,152,752)
- [x] **EXT-NORMAL-3**: ID_NUM_ACTIVO = **117757** (Site Improvements, Nov 2009, $4,404,217)

#### Compañía 188 (Juarez)
- [x] **EXT-BAJA**: ID_NUM_ACTIVO = **45308** (Tape Machine, baja Jul 2024, $311.89)

### ✅ Nacionales - ENCONTRADOS

#### Compañía 123 (Zacatecas)
- [x] **NAC-BAJA**: NO DISPONIBLE
- [x] **NAC-ANTES-JUN**: ID_NUM_ACTIVO = **2962402** (PC Desktop, Jun 2024, $10,510)
- [x] **NAC-DESP-JUN**: ID_NUM_ACTIVO = **2962404** (Desktop Lenovo, Jul 2024, $12,010)
- [x] **NAC-NORMAL-1**: ID_NUM_ACTIVO = **126259** (Edificio Zacatecas, May 2017, $198,599,473)
- [x] **NAC-NORMAL-2**: ID_NUM_ACTIVO = **192055** (Ampliación Edificio, Ago 2021, $50,515,430)
- [x] **NAC-NORMAL-3**: ID_NUM_ACTIVO = **133852** (Terreno Fideicomiso, Ago 2017, $33,488,284)

### 📊 Resumen
- **Total activos seleccionados**: 10
- **Extranjeros**: 4 activos (122: 3, 188: 1)
- **Nacionales**: 6 activos (123: 6)
- **Casos cubiertos**: 7 de 10 posibles
  - ✅ EXT-BAJA (188)
  - ✅ EXT-ANTES-JUN (122)
  - ❌ EXT-DESP-JUN (no disponible)
  - ✅ EXT-NORMAL × 3 (122)
  - ❌ NAC-BAJA (no disponible)
  - ✅ NAC-ANTES-JUN (123)
  - ✅ NAC-DESP-JUN (123)
  - ✅ NAC-NORMAL × 3 (123)

**Nota:** Los casos EXT-DESP-JUN y NAC-BAJA no están disponibles en estas compañías para 2024.

---

## Query ETL Modificado para Testing

### Filtro para Activos de Prueba

Reemplazar la condición `WHERE` del ETL con:

```sql
WHERE a.ID_COMPANIA IN (122, 123, 188)
  AND a.STATUS = 'A'
  AND a.ID_NUM_ACTIVO IN (
      -- ======================================
      -- EXTRANJEROS (ManejaUSGAAP='S')
      -- ======================================

      -- Compañía 188
      45308,      -- EXT-BAJA: Tape Machine (baja Jul 2024)

      -- Compañía 122
      2962147,    -- EXT-ANTES-JUN: Conveyor (Feb 2024)
      117930,     -- EXT-NORMAL: Building $9M (Nov 2009)
      117933,     -- EXT-NORMAL: Building $5M (Nov 2009)
      117757,     -- EXT-NORMAL: Site Improvements $4M (Nov 2009)

      -- ======================================
      -- NACIONALES (ManejaFiscal='S')
      -- ======================================

      -- Compañía 123
      2962402,    -- NAC-ANTES-JUN: PC Desktop (Jun 2024)
      2962404,    -- NAC-DESP-JUN: Desktop Lenovo (Jul 2024)
      126259,     -- NAC-NORMAL: Edificio $198M (May 2017)
      192055,     -- NAC-NORMAL: Ampliación Edificio $50M (Ago 2021)
      133852      -- NAC-NORMAL: Terreno $33M (Ago 2017)
  )
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST('2024-12-31' AS DATE))
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST('2024-01-01' AS DATE))
```

### Implementación en Program.cs

Ubicación: `/Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL/Program.cs`

Línea aproximada: 339-343

**Cambiar de:**
```csharp
WHERE a.ID_COMPANIA = @ID_Compania
  AND a.STATUS = 'A'
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST('{añoCalculo}-12-31' AS DATE))
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST('{añoCalculo}-01-01' AS DATE))
```

**A:**
```csharp
WHERE a.ID_COMPANIA IN (122, 123, 188)
  AND a.STATUS = 'A'
  AND a.ID_NUM_ACTIVO IN (
      -- EXTRANJEROS
      45308, 2962147, 117930, 117933, 117757,
      -- NACIONALES
      2962402, 2962404, 126259, 192055, 133852
  )
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST('{añoCalculo}-12-31' AS DATE))
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST('{añoCalculo}-01-01' AS DATE))
```

### Ejecución del Testing

```bash
# 1. Ejecutar ETL con filtro de testing
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{
    "idCompania": 122,
    "añoCalculo": 2024,
    "usuario": "Testing"
  }'

# 2. Obtener lote_importacion del response

# 3. Ejecutar cálculo
curl -X POST http://localhost:5071/api/calculo/ejecutar \
  -H "Content-Type: application/json" \
  -d '{
    "idCompania": 122,
    "añoCalculo": 2024,
    "usuario": "Testing",
    "loteImportacion": "<LOTE_ID>"
  }'

# 4. Verificar resultados
curl http://localhost:5071/api/reporte/1001/2024
```

### Resultados Esperados

#### Extranjeros (4 activos)
| ID_NUM_ACTIVO | Caso de Uso | Ruta Esperada | Validación |
|---------------|-------------|---------------|------------|
| 45308 | EXT-BAJA | `EXT-BAJA` | FECHA_BAJA = 2024-07-15 |
| 2962147 | EXT-ANTES-JUN | `EXT-ANTES-JUN` | FECHA_COMPRA = 2024-02-02 |
| 117930 | EXT-NORMAL | `EXT-NORMAL` o `EXT-10PCT` | FECHA_COMPRA = 2009-11-09 |
| 117933 | EXT-NORMAL | `EXT-NORMAL` o `EXT-10PCT` | FECHA_COMPRA = 2009-11-09 |
| 117757 | EXT-NORMAL | `EXT-NORMAL` o `EXT-10PCT` | FECHA_COMPRA = 2009-11-09 |

#### Nacionales (6 activos)
| ID_NUM_ACTIVO | Caso de Uso | Ruta Esperada | Validación |
|---------------|-------------|---------------|------------|
| 2962402 | NAC-ANTES-JUN | `NAC-ANTES-JUN` | FECHA_COMPRA = 2024-06-13 |
| 2962404 | NAC-DESP-JUN | `NAC-DESP-JUN` | FECHA_COMPRA = 2024-07-17 |
| 126259 | NAC-NORMAL | `NAC-NORMAL` o `NAC-10PCT` | FECHA_COMPRA = 2017-05-09 |
| 192055 | NAC-NORMAL | `NAC-NORMAL` o `NAC-10PCT` | FECHA_COMPRA = 2021-08-20 |
| 133852 | NAC-NORMAL | `NAC-NORMAL` o `NAC-10PCT` | FECHA_COMPRA = 2017-08-18 |
