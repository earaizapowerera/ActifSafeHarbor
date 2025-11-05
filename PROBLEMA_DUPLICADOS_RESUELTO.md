# Problema de Duplicados - RESUELTO

## Fecha
2025-11-01

## Problema Identificado

Durante las pruebas de los casos de uso, se detectó que algunos activos se estaban calculando **DOS VECES**:
- Una vez como "Extranjero" (por el SP `sp_Calcular_RMF_Activos_Extranjeros`)
- Una vez como "Nacional" (por el SP `sp_Calcular_RMF_Activos_Nacionales`)

### Activos Afectados

**Activos 117757 y 117930 de la compañía 122:**
- `ID_PAIS = 1` (México)
- `ManejaUSGAAP = 'S'` (usan contabilidad USGAAP)
- `ManejaFiscal = 'N'` (no usan contabilidad fiscal mexicana)
- Tienen AMBOS costos: `CostoUSD` y `CostoMXN`

### Resultados Duplicados

```
ID_NUM_ACTIVO  | Tipo_Activo | Ruta_Calculo | MOI (USD/MXN)  | Valor_MXN      | Version_SP
117757         | Extranjero  | EXT-10PCT    | 4,404,216.68   | 8,036,726.51   | v4.6
117757         | Nacional    | NAC-10PCT    | 80,367,265.13  | 8,036,726.51   | NAC-v1.0
117930         | Extranjero  | EXT-10PCT    | 9,248,494.39   | 16,876,467.59  | v4.6
117930         | Nacional    | NAC-10PCT    | 168,764,675.93 | 16,876,467.59  | NAC-v1.0
```

Aunque el valor final en MXN era el mismo, cada activo aparecía duplicado en los resultados.

## Causa Raíz

### SP de Extranjeros (versión incorrecta)
Una versión previa del SP (`sp_Calcular_RMF_Activos_Extranjeros`) había eliminado el filtro `ID_PAIS > 1`, incluyendo activos mexicanos si tenían `ManejaUSGAAP='S'`.

### SP de Nacionales
El SP `sp_Calcular_RMF_Activos_Nacionales` incluía todos los activos con `ID_PAIS=1` y `CostoMXN > 0`.

### Conflicto
Los activos mexicanos con contabilidad USGAAP cumplían los criterios de AMBOS SPs:
- ✅ Extranjeros: porque `ManejaUSGAAP='S'`
- ✅ Nacionales: porque `ID_PAIS=1` y `CostoMXN > 0`

## Solución Implementada

### 1. Creación de SP v4.6 Corregido

**Archivo:** `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.6.sql`

**Cambios principales:**

#### a) Filtro estricto por país
```sql
WHERE s.ID_Compania = @ID_Compania
  AND s.Lote_Importacion = @Lote_Importacion
  AND s.ID_PAIS > 1  -- CRÍTICO: Solo extranjeros (excluye México = 1)
  AND s.CostoUSD IS NOT NULL
  AND s.CostoUSD > 0;
```

#### b) Uso correcto del campo de costo
```sql
s.CostoUSD AS MOI,  -- Usar CostoUSD para activos extranjeros
```

(La versión anterior usaba `COSTO_REVALUADO` que estaba NULL)

#### c) Documentación clara
```sql
-- IMPORTANTE: NO incluir activos mexicanos (ID_PAIS=1) aunque tengan ManejaUSGAAP='S'
-- Los activos mexicanos con USGAAP se procesan en el SP de Nacionales usando CostoMXN
```

### 2. Regla de Negocio Clarificada

**Activos EXTRANJEROS (SP Extranjeros):**
- Criterio: `ID_PAIS > 1`
- MOI: `CostoUSD`
- Routing: `EXT-*`

**Activos NACIONALES (SP Nacionales):**
- Criterio: `ID_PAIS = 1`
- MOI: `CostoMXN`
- Routing: `NAC-*`
- Incluye activos mexicanos con contabilidad USGAAP

**Conclusión:** La bandera `ManejaUSGAAP` NO determina qué SP usar, solo el `ID_PAIS`.

## Resultados Después del Fix

### Ejecución sin duplicados

```
ID_Compania | Total_Registros | Extranjeros | Nacionales | Activos_Unicos | Duplicados
12          | 1               | 1           | 0          | 1              | 0
122         | 4               | 2           | 2          | 4              | 0
123         | 5               | 0           | 5          | 5              | 0
188         | 1               | 1           | 0          | 1              | 0
```

### Activos 117757 y 117930 (previamente duplicados)

```
ID_NUM_ACTIVO | Tipo_Activo | Ruta_Calculo | MOI            | Valor_MXN      | Version_SP
117757        | Nacional    | NAC-10PCT    | 80,367,265.13  | 8,036,726.51   | NAC-v1.0
117930        | Nacional    | NAC-10PCT    | 168,764,675.93 | 16,876,467.59  | NAC-v1.0
```

✅ Ahora aparecen **UNA SOLA VEZ** como "Nacional" (correcto, porque ID_PAIS=1)

## Verificación

### Todos los casos de uso funcionando

**EXTRANJEROS (4 activos):**
- ✅ EXT-BAJA: Activo 45308 (Co. 188)
- ✅ EXT-ANTES-JUN: Activo 2962147 (Co. 122)
- ✅ EXT-DESP-JUN: Activo 223238 (Co. 12)
- ✅ EXT-10PCT: Activo 117933 (Co. 122)

**NACIONALES (7 activos):**
- ✅ NAC-10PCT: Activos 117757, 117930, 126259, 192055
- ✅ NAC-ANTES-JUN: Activo 2962402 (Co. 123)
- ✅ NAC-DESP-JUN: Activo 2962404 (Co. 123)
- ✅ NAC-NORMAL: Activo 133852 (Co. 123)

**Total:** 11 registros calculados, 11 activos únicos, **0 duplicados** ✅

## Archivos Modificados

1. `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.6.sql` - CREADO
2. Base de datos: SP `dbo.sp_Calcular_RMF_Activos_Extranjeros` actualizado a v4.6

## Lecciones Aprendidas

1. **Separación clara de responsabilidades:** Los dos SPs deben ser mutuamente exclusivos basados en `ID_PAIS`
2. **Campo correcto para MOI:** Extranjeros usan `CostoUSD`, Nacionales usan `CostoMXN`
3. **Banderas contables vs ubicación:** `ManejaUSGAAP` es para contabilidad, `ID_PAIS` es para clasificación RMF
4. **Documentación en código:** Comentarios claros previenen modificaciones incorrectas futuras

## Advertencias para el Futuro

⚠️ **NO MODIFICAR** el filtro `ID_PAIS > 1` en el SP de Extranjeros sin revisar el impacto en el SP de Nacionales.

⚠️ Los dos SPs deben mantener criterios **mutuamente exclusivos** para evitar duplicación:
- Extranjeros: `ID_PAIS > 1`
- Nacionales: `ID_PAIS = 1`

⚠️ Si se necesita cambiar la lógica de clasificación, actualizar AMBOS SPs y documentar la razón del cambio.
