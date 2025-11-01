# Clasificación de Activos: Criterios Actualizados

## Resumen Ejecutivo

El sistema **ActifRMF** clasifica activos en 3 categorías basándose en los campos de costo de la tabla `activo`:

1. **Activos Extranjeros** → Fiscal Simulado
2. **Activos Nacionales** → Fiscal Real
3. **Activos Ambiguos** → Reporte de Error

---

## Slots de Costo en Tabla `activo`

| Campo | Tipo | Propósito | Uso |
|-------|------|-----------|-----|
| **COSTO_REEXPRESADO** | decimal(18,4) | **Slot USGAAP** | Activos extranjeros |
| **COSTO_REVALUADO** | decimal(18,4) | **Slot Fiscal** | Activos nacionales |

---

## 1. Activos Extranjeros (Fiscal Simulado)

### Criterio
```sql
COSTO_REEXPRESADO > 0
AND
(COSTO_REVALUADO = 0 OR COSTO_REVALUADO IS NULL)
```

### Características
- Tienen costo en el **slot USGAAP** (`COSTO_REEXPRESADO`)
- **NO** tienen costo en el **slot Fiscal** (`COSTO_REVALUADO`)
- Son típicamente activos de propiedad extranjera (de otra empresa)
- Requieren cálculo fiscal **simulado**

### Proceso
1. ETL importa el activo con `COSTO_REEXPRESADO > 0`
2. Sistema detecta ausencia de `COSTO_REVALUADO`
3. `sp_Calcular_Fiscal_Simulado` calcula depreciación simulada:
   - Convierte `COSTO_REEXPRESADO` a pesos con TC del 30 junio
   - Usa tasa fiscal del catálogo `porcentaje_depreciacion`
   - Calcula acumulado hasta 31/Dic año anterior
4. Guarda resultado en tabla `Calculo_Fiscal_Simulado`
5. Safe Harbor usa `Dep_Acum_Año_Anterior_Simulada`

### Ejemplo
```
Activo: Servidor HP (Propiedad de empresa USA)
COSTO_REEXPRESADO: $10,000 USD
COSTO_REVALUADO: NULL
→ Clasificación: Extranjero - Fiscal Simulado
```

---

## 2. Activos Nacionales (Fiscal Real)

### Criterio
```sql
COSTO_REVALUADO > 0
AND
(COSTO_REEXPRESADO = 0 OR COSTO_REEXPRESADO IS NULL)
```

### Características
- Tienen costo en el **slot Fiscal** (`COSTO_REVALUADO`)
- **NO** tienen costo en el **slot USGAAP** (`COSTO_REEXPRESADO`)
- Son activos nacionales (México) con depreciación fiscal real
- Usan cálculo fiscal **existente** de la tabla `calculo`

### Proceso
1. ETL importa el activo con `COSTO_REVALUADO > 0`
2. Sistema detecta ausencia de `COSTO_REEXPRESADO`
3. Sistema usa depreciación fiscal de tabla `calculo` (ID_TIPO_DEP = 2)
4. Safe Harbor usa `Dep_Acum_Inicio_Año` de staging

### Ejemplo
```
Activo: Maquinaria Industrial (México)
COSTO_REVALUADO: $500,000 MXN
COSTO_REEXPRESADO: NULL
→ Clasificación: Nacional - Fiscal Real
```

---

## 3. Activos Ambiguos (Error)

### Criterio
```sql
COSTO_REEXPRESADO > 0
AND
COSTO_REVALUADO > 0
```

### Características
- Tienen costo en **AMBOS slots**
- Es un **error de configuración** en el sistema origen
- **NO se deben procesar** en cálculos automáticos
- Requieren revisión manual

### Proceso
1. ETL importa el activo con ambos costos > 0
2. Sistema lo marca como **AMBIGUO**
3. **NO** se procesa en cálculo fiscal simulado ni Safe Harbor
4. Va a un **Reporte de Ambigüedad** para revisión manual
5. Usuario debe corregir en sistema origen (Actif)

### Ejemplo
```
Activo: Equipo de Cómputo
COSTO_REVALUADO: $100,000 MXN
COSTO_REEXPRESADO: $5,000 USD
→ Clasificación: AMBIGUO - REQUIERE REVISIÓN
```

### ¿Por qué es un Error?

Un activo no puede tener **dos costos fiscales simultáneamente**:
- Si es extranjero → Solo debe tener `COSTO_REEXPRESADO`
- Si es nacional → Solo debe tener `COSTO_REVALUADO`
- Tener ambos indica configuración incorrecta en Actif

---

## Query de Clasificación

### Resumen por Categoría

```sql
SELECT
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN 'AMBIGUO - REVISAR'
        ELSE 'Sin Costo Definido'
    END AS Clasificacion,
    COUNT(*) AS Cantidad,
    SUM(ISNULL(COSTO_REVALUADO, 0)) AS Total_Costo_Fiscal,
    SUM(ISNULL(COSTO_REEXPRESADO, 0)) AS Total_Costo_USGAAP
FROM Staging_Activo
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
GROUP BY
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN 'AMBIGUO - REVISAR'
        ELSE 'Sin Costo Definido'
    END
ORDER BY Clasificacion;
```

---

## Reporte de Activos Ambiguos

### Crear Vista de Ambigüedad

```sql
CREATE VIEW vw_Activos_Ambiguos AS
SELECT
    s.ID_Staging,
    s.ID_Compania,
    c.NOMBRE AS Compania,
    s.Año_Calculo,
    s.ID_NUM_ACTIVO,
    s.ID_ACTIVO,
    s.DESCRIPCION,
    s.COSTO_REVALUADO AS Costo_Fiscal,
    s.COSTO_REEXPRESADO AS Costo_USGAAP,
    s.ID_MONEDA,
    'AMBIGUO - REQUIERE CORRECCIÓN EN ACTIF' AS Estado,
    GETDATE() AS Fecha_Reporte
FROM Staging_Activo s
INNER JOIN Compania c ON s.ID_Compania = c.ID_Compania
WHERE s.COSTO_REEXPRESADO > 0
  AND s.COSTO_REVALUADO > 0;
```

### Query para Reporte

```sql
-- Listar activos ambiguos
SELECT
    Compania,
    Año_Calculo,
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    Costo_Fiscal,
    Costo_USGAAP,
    Estado
FROM vw_Activos_Ambiguos
ORDER BY Compania, ID_NUM_ACTIVO;
```

### Export a Excel

```sql
-- Resumen para Excel
SELECT
    Compania,
    Año_Calculo,
    COUNT(*) AS Total_Activos_Ambiguos,
    SUM(Costo_Fiscal) AS Total_Fiscal,
    SUM(Costo_USGAAP) AS Total_USGAAP
FROM vw_Activos_Ambiguos
GROUP BY Compania, Año_Calculo;
```

---

## Flujo de Decisión (Diagrama)

```
                        ┌─────────────────┐
                        │  Activo de      │
                        │  Tabla activo   │
                        └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    │ ¿COSTO_REEXPRESADO > 0? │
                    └────────┬────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │ SI                          │ NO
              ▼                             ▼
    ┌──────────────────┐         ┌──────────────────┐
    │ ¿COSTO_REVALUADO │         │ ¿COSTO_REVALUADO │
    │      > 0?        │         │      > 0?        │
    └────────┬─────────┘         └────────┬─────────┘
             │                             │
      ┌──────┴──────┐               ┌─────┴─────┐
      │ SI          │ NO            │ SI        │ NO
      ▼             ▼               ▼           ▼
  ┌────────┐  ┌──────────┐    ┌──────────┐  ┌──────────┐
  │AMBIGUO │  │EXTRANJERO│    │NACIONAL  │  │SIN COSTO │
  │(ERROR) │  │(SIMULADO)│    │(REAL)    │  │          │
  └────────┘  └──────────┘    └──────────┘  └──────────┘
      │             │               │             │
      ▼             ▼               ▼             ▼
  Reporte      Fiscal          Fiscal         No se
  Ambigüedad   Simulado        Real           procesa
```

---

## Stored Procedures Modificados

### 1. sp_ETL_Importar_Activos_Completo

**Debe importar:**
- `COSTO_REEXPRESADO` (slot USGAAP)
- `COSTO_REVALUADO` (slot Fiscal)
- `FECHA_INIC_DEPREC` (fecha inicio fiscal)
- `FECHA_INIC_DEPREC_3` (fecha inicio USGAAP)

**Debe reportar:**
- Total activos extranjeros
- Total activos nacionales
- **Total activos ambiguos** ⚠️

### 2. sp_Calcular_Fiscal_Simulado

**Debe filtrar:**
```sql
WHERE COSTO_REEXPRESADO > 0
  AND ISNULL(COSTO_REVALUADO, 0) = 0
```

**NO debe procesar:**
- Activos con ambos costos > 0

### 3. sp_Calcular_RMF_Safe_Harbor

**Debe usar:**
- `Dep_Acum_Año_Anterior_Simulada` para extranjeros
- `Dep_Acum_Inicio_Año` para nacionales

**Debe saltar:**
- Activos ambiguos (no se deben incluir en Safe Harbor)

---

## Validaciones Recomendadas

### Validación 1: No Activos Ambiguos
```sql
IF EXISTS (
    SELECT 1
    FROM Staging_Activo
    WHERE COSTO_REEXPRESADO > 0
      AND COSTO_REVALUADO > 0
)
BEGIN
    RAISERROR('ADVERTENCIA: Se encontraron activos ambiguos. Revisar reporte.', 16, 1);
END
```

### Validación 2: Todos los Activos Clasificados
```sql
SELECT
    COUNT(*) AS Total_Activos,
    SUM(CASE WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0 THEN 1 ELSE 0 END) AS Extranjeros,
    SUM(CASE WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0 THEN 1 ELSE 0 END) AS Nacionales,
    SUM(CASE WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0 THEN 1 ELSE 0 END) AS Ambiguos,
    SUM(CASE WHEN ISNULL(COSTO_REEXPRESADO, 0) = 0 AND ISNULL(COSTO_REVALUADO, 0) = 0 THEN 1 ELSE 0 END) AS Sin_Costo
FROM Staging_Activo;
```

---

## Documentos Relacionados

- **FISCAL_SIMULADO.md** - Documentación completa del cálculo fiscal simulado
- **RESUMEN_FISCAL_SIMULADO.md** - Resumen de la implementación
- **RMF.md** - Marco legal y reglas fiscales
- **README.md** - Información general del sistema

---

**Versión:** 2.0
**Fecha:** 2025-10-29
**Proyecto:** ActifRMF
**Criterio actualizado:** Clasificación por slots de costo (COSTO_REEXPRESADO vs COSTO_REVALUADO)
