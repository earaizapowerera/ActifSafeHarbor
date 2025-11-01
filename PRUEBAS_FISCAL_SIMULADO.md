# Guía de Pruebas: Cálculo Fiscal Simulado

## Objetivo

Validar que el sistema **ActifRMF** clasifica y procesa correctamente los activos según los nuevos criterios basados en slots de costo.

---

## Prerrequisitos

1. Sistema ActifRMF corriendo en puerto **5071**
2. Base de datos `Actif_RMF` con tablas creadas
3. Al menos una compañía configurada con connection string a base Actif
4. Datos de prueba en sistema Actif con:
   - Activos extranjeros (`COSTO_REEXPRESADO > 0`)
   - Activos nacionales (`COSTO_REVALUADO > 0`)
   - (Opcional) Activos ambiguos para probar detección

---

## Escenarios de Prueba

### Escenario 1: Activos Extranjeros (Fiscal Simulado)

#### Datos de Prueba

Crear/verificar en Actif:

```sql
-- Activo extranjero sin fiscal
INSERT INTO activo (
    ID_COMPANIA, ID_ACTIVO, DESCRIPCION,
    COSTO_REEXPRESADO,      -- > 0 (USGAAP)
    COSTO_REVALUADO,        -- = 0 o NULL
    FECHA_INIC_DEPREC_3,    -- Fecha inicio USGAAP
    ID_MONEDA,              -- Moneda (ej: 2 = USD)
    STATUS
) VALUES (
    1, 'EXT-001', 'Servidor HP ProLiant',
    10000.00,               -- $10,000 USD en USGAAP
    NULL,                   -- Sin fiscal
    '2022-01-01',           -- Inicio USGAAP
    2,                      -- USD
    'A'
);
```

#### Pasos de Prueba

1. **Importar datos (ETL)**
   - URL: http://localhost:5071/extraccion.html
   - Seleccionar compañía: 1
   - Año: 2024
   - Click en "Ejecutar ETL"

2. **Verificar clasificación**
   ```sql
   SELECT
       ID_NUM_ACTIVO,
       ID_ACTIVO,
       DESCRIPCION,
       COSTO_REEXPRESADO AS USGAAP,
       COSTO_REVALUADO AS Fiscal,
       CASE
           WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
               THEN 'Extranjero - OK'
           ELSE 'ERROR'
       END AS Clasificacion
   FROM Staging_Activo
   WHERE ID_ACTIVO = 'EXT-001';
   ```

   **Resultado esperado:** Clasificacion = 'Extranjero - OK'

3. **Verificar cálculo fiscal simulado**
   ```sql
   SELECT
       s.ID_NUM_ACTIVO,
       s.ID_ACTIVO,
       fs.Costo_Fiscal_Simulado_MXN,
       fs.Tipo_Cambio_30_Junio,
       fs.Tasa_Anual_Fiscal,
       fs.Meses_Depreciados,
       fs.Dep_Acum_Año_Anterior_Simulada,
       fs.Observaciones
   FROM Staging_Activo s
   INNER JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
   WHERE s.ID_ACTIVO = 'EXT-001';
   ```

   **Resultado esperado:**
   - `Costo_Fiscal_Simulado_MXN` > 0 (COSTO_REEXPRESADO × TC)
   - `Tasa_Anual_Fiscal` > 0 (del catálogo)
   - `Dep_Acum_Año_Anterior_Simulada` > 0

4. **Verificar uso en Safe Harbor**
   ```sql
   SELECT
       s.ID_ACTIVO,
       s.COSTO_REEXPRESADO,
       fs.Dep_Acum_Año_Anterior_Simulada AS Dep_Simulada,
       sh.Dep_Acum_Inicio_Año AS Dep_Usada,
       sh.Valor_Reportable
   FROM Staging_Activo s
   INNER JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
   INNER JOIN Calculo_Safe_Harbor sh ON s.ID_Staging = sh.ID_Staging
   WHERE s.ID_ACTIVO = 'EXT-001';
   ```

   **Resultado esperado:**
   - `Dep_Usada` = `Dep_Simulada` (Safe Harbor usa el cálculo simulado)

---

### Escenario 2: Activos Nacionales (Fiscal Real)

#### Datos de Prueba

```sql
-- Activo nacional con fiscal
INSERT INTO activo (
    ID_COMPANIA, ID_ACTIVO, DESCRIPCION,
    COSTO_REVALUADO,        -- > 0 (Fiscal)
    COSTO_REEXPRESADO,      -- = 0 o NULL
    FECHA_INIC_DEPREC,      -- Fecha inicio fiscal
    ID_MONEDA,
    STATUS
) VALUES (
    1, 'NAC-001', 'Maquinaria Industrial',
    500000.00,              -- $500,000 MXN fiscal
    NULL,                   -- Sin USGAAP
    '2020-06-01',           -- Inicio fiscal
    1,                      -- MXN
    'A'
);
```

#### Pasos de Prueba

1. **Ejecutar ETL** (igual que escenario 1)

2. **Verificar clasificación**
   ```sql
   SELECT
       ID_NUM_ACTIVO,
       ID_ACTIVO,
       DESCRIPCION,
       COSTO_REVALUADO AS Fiscal,
       COSTO_REEXPRESADO AS USGAAP,
       CASE
           WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
               THEN 'Nacional - OK'
           ELSE 'ERROR'
       END AS Clasificacion
   FROM Staging_Activo
   WHERE ID_ACTIVO = 'NAC-001';
   ```

   **Resultado esperado:** Clasificacion = 'Nacional - OK'

3. **Verificar que NO tiene fiscal simulado**
   ```sql
   SELECT
       s.ID_ACTIVO,
       fs.ID_Calculo_Fiscal_Simulado
   FROM Staging_Activo s
   LEFT JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging
   WHERE s.ID_ACTIVO = 'NAC-001';
   ```

   **Resultado esperado:**
   - `ID_Calculo_Fiscal_Simulado` = NULL (no tiene cálculo simulado)

4. **Verificar uso de fiscal real en Safe Harbor**
   ```sql
   SELECT
       s.ID_ACTIVO,
       s.COSTO_REVALUADO,
       s.Dep_Acum_Inicio_Año AS Dep_Real,
       sh.Dep_Acum_Inicio_Año AS Dep_Usada
   FROM Staging_Activo s
   INNER JOIN Calculo_Safe_Harbor sh ON s.ID_Staging = sh.ID_Staging
   WHERE s.ID_ACTIVO = 'NAC-001';
   ```

   **Resultado esperado:**
   - `Dep_Usada` = `Dep_Real` (Safe Harbor usa fiscal real)

---

### Escenario 3: Activos Ambiguos (Error)

#### Datos de Prueba

```sql
-- Activo con AMBOS costos (ERROR)
INSERT INTO activo (
    ID_COMPANIA, ID_ACTIVO, DESCRIPCION,
    COSTO_REVALUADO,        -- > 0
    COSTO_REEXPRESADO,      -- > 0 (ERROR!)
    FECHA_INIC_DEPREC,
    FECHA_INIC_DEPREC_3,
    STATUS
) VALUES (
    1, 'AMB-001', 'Equipo Mal Configurado',
    100000.00,              -- Tiene fiscal
    5000.00,                -- Y también USGAAP (ERROR)
    '2021-01-01',
    '2021-01-01',
    'A'
);
```

#### Pasos de Prueba

1. **Ejecutar ETL** (igual que escenarios anteriores)

2. **Verificar detección de ambigüedad**
   ```sql
   SELECT
       ID_NUM_ACTIVO,
       ID_ACTIVO,
       DESCRIPCION,
       COSTO_REVALUADO AS Fiscal,
       COSTO_REEXPRESADO AS USGAAP,
       CASE
           WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
               THEN 'AMBIGUO - DETECTADO'
           ELSE 'OK'
       END AS Estado
   FROM Staging_Activo
   WHERE ID_ACTIVO = 'AMB-001';
   ```

   **Resultado esperado:** Estado = 'AMBIGUO - DETECTADO'

3. **Verificar que NO se procesó**
   ```sql
   -- No debe tener fiscal simulado
   SELECT COUNT(*) AS Debe_Ser_Cero
   FROM Calculo_Fiscal_Simulado fs
   INNER JOIN Staging_Activo s ON fs.ID_Staging = s.ID_Staging
   WHERE s.ID_ACTIVO = 'AMB-001';

   -- No debe estar en Safe Harbor
   SELECT COUNT(*) AS Debe_Ser_Cero
   FROM Calculo_Safe_Harbor sh
   INNER JOIN Staging_Activo s ON sh.ID_Staging = s.ID_Staging
   WHERE s.ID_ACTIVO = 'AMB-001';
   ```

   **Resultado esperado:** Ambos conteos = 0

4. **Verificar reporte de ambigüedad**
   ```sql
   SELECT *
   FROM vw_Activos_Ambiguos
   WHERE ID_ACTIVO = 'AMB-001';
   ```

   **Resultado esperado:** Activo listado con estado 'AMBIGUO'

---

## Pruebas de Interfaz Web

### Página: Extracción ETL

**URL:** http://localhost:5071/extraccion.html

#### Test 1: Ejecución Exitosa
1. Seleccionar compañía
2. Ingresar año (ej: 2024)
3. Click "Ejecutar ETL"
4. **Verificar:**
   - Mensaje de éxito
   - Estadísticas mostradas:
     - Total activos importados
     - Total extranjeros
     - Total nacionales
     - **Total ambiguos (si hay)**

#### Test 2: Advertencia de Ambigüedad
1. Si existen activos ambiguos
2. **Verificar:**
   - Mensaje de advertencia en color naranja/rojo
   - Enlace a reporte de ambigüedad
   - Cantidad de activos ambiguos

### Página: Cálculo RMF

**URL:** http://localhost:5071/calculo.html

#### Test 1: Cálculo Completo
1. Seleccionar compañía
2. Ingresar año
3. Click "Ejecutar Cálculo"
4. **Verificar:**
   - Mensaje de éxito
   - Resumen de activos procesados
   - Separación clara entre extranjeros y nacionales

#### Test 2: Excluir Ambiguos
1. Verificar que activos ambiguos NO aparecen en resultados
2. **Verificar:**
   - Conteo de activos procesados = extranjeros + nacionales
   - NO incluye ambiguos

---

## Queries de Validación Global

### Validación 1: Todos los Activos Clasificados

```sql
SELECT
    'Total Activos' AS Categoria,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1 AND Año_Calculo = 2024

UNION ALL

SELECT
    'Extranjeros (Fiscal Simulado)' AS Categoria,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1 AND Año_Calculo = 2024
  AND COSTO_REEXPRESADO > 0
  AND ISNULL(COSTO_REVALUADO, 0) = 0

UNION ALL

SELECT
    'Nacionales (Fiscal Real)' AS Categoria,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1 AND Año_Calculo = 2024
  AND COSTO_REVALUADO > 0
  AND ISNULL(COSTO_REEXPRESADO, 0) = 0

UNION ALL

SELECT
    'Ambiguos (ERROR)' AS Categoria,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1 AND Año_Calculo = 2024
  AND COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0

UNION ALL

SELECT
    'Sin Costo' AS Categoria,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1 AND Año_Calculo = 2024
  AND ISNULL(COSTO_REEXPRESADO, 0) = 0
  AND ISNULL(COSTO_REVALUADO, 0) = 0;
```

**Resultado esperado:**
- Total = Extranjeros + Nacionales + Ambiguos + Sin Costo

### Validación 2: Fiscal Simulado Solo para Extranjeros

```sql
-- Todos los registros en Calculo_Fiscal_Simulado deben ser extranjeros
SELECT
    COUNT(*) AS Total_Fiscal_Simulado,
    SUM(CASE
        WHEN s.COSTO_REEXPRESADO > 0 AND ISNULL(s.COSTO_REVALUADO, 0) = 0
        THEN 1 ELSE 0
    END) AS Correctos,
    SUM(CASE
        WHEN s.COSTO_REEXPRESADO > 0 AND ISNULL(s.COSTO_REVALUADO, 0) = 0
        THEN 0 ELSE 1
    END) AS Incorrectos
FROM Calculo_Fiscal_Simulado fs
INNER JOIN Staging_Activo s ON fs.ID_Staging = s.ID_Staging
WHERE s.ID_Compania = 1 AND s.Año_Calculo = 2024;
```

**Resultado esperado:**
- `Total_Fiscal_Simulado` = `Correctos`
- `Incorrectos` = 0

### Validación 3: Safe Harbor NO Incluye Ambiguos

```sql
-- Ningún activo ambiguo debe estar en Safe Harbor
SELECT
    s.ID_ACTIVO,
    s.COSTO_REVALUADO,
    s.COSTO_REEXPRESADO,
    'ERROR - Ambiguo en Safe Harbor' AS Estado
FROM Calculo_Safe_Harbor sh
INNER JOIN Staging_Activo s ON sh.ID_Staging = s.ID_Staging
WHERE s.COSTO_REEXPRESADO > 0
  AND s.COSTO_REVALUADO > 0;
```

**Resultado esperado:**
- 0 filas (ningún activo ambiguo debe estar en Safe Harbor)

---

## Checklist de Pruebas

### Funcionalidad

- [ ] ETL importa correctamente COSTO_REEXPRESADO y COSTO_REVALUADO
- [ ] Activos extranjeros se clasifican correctamente
- [ ] Activos nacionales se clasifican correctamente
- [ ] Activos ambiguos se detectan correctamente
- [ ] Fiscal simulado se calcula solo para extranjeros
- [ ] Fiscal simulado NO se calcula para nacionales
- [ ] Fiscal simulado NO se calcula para ambiguos
- [ ] Safe Harbor usa fiscal simulado para extranjeros
- [ ] Safe Harbor usa fiscal real para nacionales
- [ ] Safe Harbor NO incluye activos ambiguos

### Interfaz Web

- [ ] Página de extracción muestra estadísticas
- [ ] Página de extracción advierte sobre ambiguos
- [ ] Página de cálculo funciona correctamente
- [ ] Resultados separan extranjeros y nacionales
- [ ] Reportes no incluyen ambiguos

### Reportes

- [ ] Reporte de ambigüedad existe y funciona
- [ ] Vista vw_Activos_Ambiguos lista correctamente
- [ ] Reportes finales excluyen ambiguos

---

## Solución de Problemas

### Problema: Activo extranjero no tiene fiscal simulado

**Causa posible:**
- `FECHA_INIC_DEPREC_3` es NULL
- `COSTO_REEXPRESADO` es NULL o 0
- `COSTO_REVALUADO` > 0 (entonces es nacional)

**Solución:**
```sql
SELECT
    ID_ACTIVO,
    COSTO_REEXPRESADO,
    COSTO_REVALUADO,
    FECHA_INIC_DEPREC_3
FROM Staging_Activo
WHERE ID_ACTIVO = 'XXX';
```

### Problema: Activo clasificado incorrectamente

**Verificar:**
```sql
SELECT
    ID_ACTIVO,
    COSTO_REEXPRESADO AS USGAAP,
    COSTO_REVALUADO AS Fiscal,
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0 THEN 'Extranjero'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0 THEN 'Nacional'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0 THEN 'Ambiguo'
        ELSE 'Sin Costo'
    END AS Debe_Ser
FROM Staging_Activo
WHERE ID_ACTIVO = 'XXX';
```

### Problema: Activo ambiguo no detectado

**Verificar:**
```sql
SELECT COUNT(*)
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0;
```

Si hay registros pero no aparecen en vw_Activos_Ambiguos, recrear la vista.

---

## Conclusión

Estas pruebas validan que:

1. ✅ Activos se clasifican correctamente por slots de costo
2. ✅ Fiscal simulado se calcula solo para extranjeros
3. ✅ Activos ambiguos se detectan y reportan
4. ✅ Safe Harbor usa la depreciación correcta según tipo
5. ✅ Sistema excluye activos ambiguos de procesamiento

---

**Versión:** 1.0
**Fecha:** 2025-10-29
**Proyecto:** ActifRMF - Pruebas Fiscal Simulado
