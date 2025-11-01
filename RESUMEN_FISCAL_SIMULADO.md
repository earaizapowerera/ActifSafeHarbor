# Resumen: Implementación de Cálculo Fiscal Simulado

## Objetivo

✅ Crear cálculo fiscal simulado para activos **extranjeros** que solo tienen USGAAP y no tienen fiscal.

## Criterios de Clasificación de Activos

El sistema clasifica activos en 3 categorías:

### 1. Activos Extranjeros (Fiscal Simulado)
```sql
COSTO_REEXPRESADO > 0 AND (COSTO_REVALUADO = 0 OR COSTO_REVALUADO IS NULL)
```
→ Requieren cálculo fiscal simulado

### 2. Activos Nacionales (Fiscal Real)
```sql
COSTO_REVALUADO > 0 AND (COSTO_REEXPRESADO = 0 OR COSTO_REEXPRESADO IS NULL)
```
→ Usan cálculo fiscal existente

### 3. Activos Ambiguos (Error)
```sql
COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
```
→ **No se procesan, van a reporte de ambigüedad**

**Importante:** Los activos se clasifican por los campos de costo (slots), NO por flags ni ID_PAIS.

---

## Archivos Creados

### 1. `11_CREATE_Calculo_Fiscal_Simulado.sql`

**Función**: Crear infraestructura de base de datos

**Contenido**:
- Tabla `Calculo_Fiscal_Simulado` (relación 1 a 1 con `Staging_Activo`)
- Agrega campos a `Staging_Activo`:
  - `FLG_NOCAPITALIZABLE_2` (tiene fiscal)
  - `FLG_NOCAPITALIZABLE_3` (tiene USGAAP)
  - `FECHA_INIC_DEPREC_3` (fecha inicio USGAAP)
  - `COSTO_REEXPRESADO` (costo USGAAP)
  - `Costo_Fiscal` (COSTO_REVALUADO o COSTO_ADQUISICION)

### 2. `12_SP_Calcular_Fiscal_Simulado.sql`

**Función**: Stored procedure que calcula depreciación fiscal simulada

**Proceso**:
1. Filtra activos con `FLG_NOCAPITALIZABLE_3='S'` y sin fiscal
2. Convierte `COSTO_REEXPRESADO` a pesos con TC del 30 junio
3. Obtiene porcentaje fiscal de `porcentaje_depreciacion` (ID_TIPO_DEP=2)
4. Calcula meses desde `FECHA_INIC_DEPREC_3` hasta 31 Dic año anterior
5. Calcula depreciación acumulada simulada
6. Guarda en tabla `Calculo_Fiscal_Simulado`

**Output principal**: `Dep_Acum_Año_Anterior_Simulada`

### 3. `13_SP_ETL_Importar_Activos_Completo.sql`

**Función**: ETL modificado que carga todos los campos necesarios

**Diferencias vs ETL original**:
- Carga **TODOS los activos activos** (no solo `FLG_PROPIO = 0`)
- Incluye `FLG_NOCAPITALIZABLE_2` y `FLG_NOCAPITALIZABLE_3`
- Incluye `FECHA_INIC_DEPREC_3`, `COSTO_REEXPRESADO`
- Calcula `Costo_Fiscal` (REVALUADO o ADQUISICION)
- Muestra resumen de cuántos requieren fiscal simulado

### 4. `14_EXEC_Flujo_Completo_RMF.sql`

**Función**: Script de ejecución completa

**Pasos**:
1. ETL Completo
2. Cálculo Fiscal Simulado
3. Cálculo RMF Safe Harbor
4. Resúmenes y estadísticas

### 5. `FISCAL_SIMULADO.md`

**Función**: Documentación completa del sistema

**Contenido**:
- Flujo del sistema
- Descripción de tablas
- Lógica de cálculo detallada
- Ejemplo numérico completo
- Queries útiles
- Casos especiales

---

## Fórmula de Cálculo

### Paso 1: Convertir a Pesos
```
Costo_Fiscal_Simulado_MXN = COSTO_REEXPRESADO × Tipo_Cambio_30_Junio
```

### Paso 2: Obtener Tasa
```
Tasa_Mensual_Fiscal = (Tasa_Anual_Fiscal / 12) / 100
```

### Paso 3: Calcular Meses
```
Meses_Depreciados = DATEDIFF(MONTH, FECHA_INIC_DEPREC_3, '31-Dic-AñoAnterior') + 1
```

### Paso 4: Depreciación Acumulada
```
Dep_Mensual = Costo_Fiscal_Simulado_MXN × Tasa_Mensual_Fiscal
Dep_Acum_Año_Anterior_Simulada = Dep_Mensual × Meses_Depreciados
```

---

## Tabla Principal: Calculo_Fiscal_Simulado

| Campo Clave | Descripción |
|-------------|-------------|
| `ID_Staging` | FK a Staging_Activo (UNIQUE, 1 a 1) |
| `COSTO_REEXPRESADO` | Costo USGAAP en moneda original |
| `Tipo_Cambio_30_Junio` | TC del 30 junio del **año de cálculo** |
| `Costo_Fiscal_Simulado_MXN` | COSTO_REEXPRESADO × TC |
| `Tasa_Anual_Fiscal` | De `porcentaje_depreciacion` |
| `Meses_Depreciados` | Desde inicio USGAAP hasta Dic año anterior |
| **`Dep_Acum_Año_Anterior_Simulada`** | **RESULTADO PRINCIPAL** |

---

## Integración con Safe Harbor

El SP `sp_Calcular_RMF_Safe_Harbor` debe modificarse para:

```sql
-- Obtener depreciación acumulada
DECLARE @Dep_Acum DECIMAL(18,4);

-- 1. Intentar obtener de fiscal simulado
SELECT @Dep_Acum = Dep_Acum_Año_Anterior_Simulada
FROM Calculo_Fiscal_Simulado
WHERE ID_Staging = @ID_Staging;

-- 2. Si no existe, usar fiscal real
IF @Dep_Acum IS NULL
    SET @Dep_Acum = @Dep_Acum_Inicio_Año_Staging;
```

---

## Ejecución

### Orden de Ejecución (Primera Vez)

```sql
-- 1. Crear tablas y agregar campos
:r 11_CREATE_Calculo_Fiscal_Simulado.sql

-- 2. Crear SP de fiscal simulado
:r 12_SP_Calcular_Fiscal_Simulado.sql

-- 3. Crear ETL completo
:r 13_SP_ETL_Importar_Activos_Completo.sql

-- 4. Ejecutar flujo completo
:r 14_EXEC_Flujo_Completo_RMF.sql
```

### Ejecución Mensual

```sql
EXEC sp_ETL_Importar_Activos_Completo @ID_Compania = 1, @Año_Calculo = 2024;
-- Guardar @Lote_Importacion

EXEC sp_Calcular_Fiscal_Simulado
    @ID_Compania = 1,
    @Año_Calculo = 2024,
    @Lote_Importacion = @Lote,
    @ConnectionString_Actif = @ConnStr;

EXEC sp_Calcular_RMF_Safe_Harbor
    @ID_Compania = 1,
    @Año_Calculo = 2024,
    @Lote_Importacion = @Lote;
```

---

## Ejemplo Práctico

### Activo de Ejemplo

```
ID_NUM_ACTIVO: 5000
Descripción: Servidor HP ProLiant
Propiedad: Otra empresa (leasing)
FLG_NOCAPITALIZABLE_2: NULL (no tiene fiscal)
FLG_NOCAPITALIZABLE_3: 'S' (tiene USGAAP)
COSTO_REEXPRESADO: $15,000 USD
FECHA_INIC_DEPREC_3: 01/06/2022
Año de Cálculo: 2024
```

### Cálculo

```
TC 30-Jun-2024: 18.20 MXN/USD
Costo en MXN: $15,000 × 18.20 = $273,000

Tasa Fiscal: 30% anual = 2.5% mensual
Meses: Jun/2022 a Dic/2023 = 19 meses

Dep. Mensual: $273,000 × 0.025 = $6,825
Dep. Acum: $6,825 × 19 = $129,675
```

### Resultado en BD

```sql
INSERT INTO Calculo_Fiscal_Simulado (...)
VALUES (
    ...,
    Costo_Fiscal_Simulado_MXN = 273000.00,
    Tasa_Anual_Fiscal = 30.00,
    Meses_Depreciados = 19,
    Dep_Mensual_Simulada = 6825.00,
    Dep_Acum_Año_Anterior_Simulada = 129675.00,  -- ← ESTE VALOR
    ...
);
```

---

## Queries de Verificación

### Ver activos que requieren fiscal simulado
```sql
-- Activos extranjeros
SELECT COUNT(*) AS Total_Extranjeros_Fiscal_Simulado
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND ISNULL(COSTO_REVALUADO, 0) = 0;

-- Activos nacionales
SELECT COUNT(*) AS Total_Nacionales_Fiscal_Real
FROM Staging_Activo
WHERE COSTO_REVALUADO > 0
  AND ISNULL(COSTO_REEXPRESADO, 0) = 0;

-- Activos ambiguos (ERROR)
SELECT COUNT(*) AS Total_Ambiguos_REVISAR
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0;
```

### Ver resultados del cálculo
```sql
SELECT
    s.ID_NUM_ACTIVO,
    s.DESCRIPCION,
    fs.Costo_Fiscal_Simulado_MXN,
    fs.Meses_Depreciados,
    fs.Dep_Acum_Año_Anterior_Simulada
FROM Staging_Activo s
INNER JOIN Calculo_Fiscal_Simulado fs ON s.ID_Staging = fs.ID_Staging;
```

### Comparar fiscal real vs simulado
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
    END AS Tipo,
    COUNT(*) AS Cantidad,
    SUM(ISNULL(COSTO_REVALUADO, 0)) AS Total_Fiscal,
    SUM(ISNULL(COSTO_REEXPRESADO, 0)) AS Total_USGAAP
FROM Staging_Activo
GROUP BY
    CASE
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN 'AMBIGUO - REVISAR'
        ELSE 'Sin Costo'
    END;
```

---

## Ventajas del Diseño

1. ✅ **Tabla separada**: No contamina `Staging_Activo` con cálculos
2. ✅ **Relación 1 a 1**: Fácil de hacer JOIN
3. ✅ **Trazabilidad**: Observaciones y versión del SP
4. ✅ **Auditable**: Lote de cálculo y fecha
5. ✅ **Escalable**: Puede manejar miles de activos
6. ✅ **Flexible**: Fácil recalcular si cambian reglas

---

## Casos Especiales Manejados

| Caso | Solución |
|------|----------|
| Sin porcentaje fiscal en catálogo | Tasa = 0, Dep = 0, registra observación |
| Inicio después del corte | Meses = 0, Dep = 0, registra observación |
| Depreciación > 100% | Limita al costo, registra observación |
| Sin COSTO_REEXPRESADO | No se procesa, queda fuera del cursor |
| Sin FECHA_INIC_DEPREC_3 | No se procesa, queda fuera del cursor |

---

## Próximos Pasos

- [ ] Ejecutar scripts en BD de desarrollo
- [ ] Probar con datos reales de una compañía
- [ ] Modificar `sp_Calcular_RMF_Safe_Harbor` para integrar
- [ ] Crear reportes que muestren ambos tipos de fiscal
- [ ] Validar con cliente/contador

---

**Versión**: 1.0
**Fecha**: 2025-10-18
**Proyecto**: ActifRMF - Cálculo Fiscal Simulado
