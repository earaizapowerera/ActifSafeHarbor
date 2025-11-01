# Resumen Ejecutivo: Criterios Actualizados de Clasificación de Activos

## 📋 Cambio Principal

**Antes:** Se usaban flags (`FLG_NOCAPITALIZABLE_2` y `FLG_NOCAPITALIZABLE_3`) y campo `ID_PAIS`

**Ahora:** Se usan **campos de costo** como slots dedicados:
- `COSTO_REEXPRESADO` = Slot USGAAP (Extranjeros)
- `COSTO_REVALUADO` = Slot Fiscal (Nacionales)

---

## 🎯 Criterios de Clasificación (Versión 2.0)

### 1. Activos Extranjeros (Fiscal Simulado)
```sql
COSTO_REEXPRESADO > 0 AND (COSTO_REVALUADO = 0 OR NULL)
```
- Tienen costo en slot USGAAP
- NO tienen costo en slot Fiscal
- Requieren cálculo fiscal **simulado**

### 2. Activos Nacionales (Fiscal Real)
```sql
COSTO_REVALUADO > 0 AND (COSTO_REEXPRESADO = 0 OR NULL)
```
- Tienen costo en slot Fiscal
- NO tienen costo en slot USGAAP
- Usan cálculo fiscal **real** de tabla `calculo`

### 3. Activos Ambiguos (Error - NO Procesar)
```sql
COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
```
- Tienen **ambos costos** > 0
- Es un **error de configuración**
- Van a **Reporte de Ambigüedad** para corrección manual
- **NO se procesan** en cálculos automáticos

---

## 📊 Tabla Resumen

| Tipo | COSTO_REEXPRESADO | COSTO_REVALUADO | Acción |
|------|-------------------|-----------------|--------|
| **Extranjero** | > 0 | = 0 o NULL | Fiscal Simulado |
| **Nacional** | = 0 o NULL | > 0 | Fiscal Real |
| **Ambiguo** | > 0 | > 0 | ⚠️ Reporte Error |
| Sin Costo | = 0 o NULL | = 0 o NULL | No procesar |

---

## 🔄 Flujo del Sistema

```
1. ETL importa activos
   ↓
2. Sistema clasifica por slots de costo
   ↓
3. Extranjeros → sp_Calcular_Fiscal_Simulado
   Nacionales → Usa fiscal real existente
   Ambiguos → Reporte de Ambigüedad
   ↓
4. Safe Harbor usa depreciación correcta
   ↓
5. Reportes finales (excluyen ambiguos)
```

---

## ✅ Validación Rápida

### Query de Resumen
```sql
SELECT
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN '⚠️ AMBIGUO - REVISAR'
        ELSE 'Sin Costo'
    END AS Tipo,
    COUNT(*) AS Cantidad
FROM Staging_Activo
GROUP BY
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero - Fiscal Simulado'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional - Fiscal Real'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN '⚠️ AMBIGUO - REVISAR'
        ELSE 'Sin Costo'
    END;
```

### Detectar Activos Ambiguos
```sql
SELECT
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    COSTO_REEXPRESADO AS Costo_USGAAP,
    COSTO_REVALUADO AS Costo_Fiscal
FROM Staging_Activo
WHERE COSTO_REEXPRESADO > 0
  AND COSTO_REVALUADO > 0;
```

Si este query retorna filas → **Activos requieren corrección en sistema origen (Actif)**

---

## 🚀 Cómo Probar el Sistema

### Opción 1: Interfaz Web
1. Acceder a **http://localhost:5071**
2. Ir a **Extracción ETL** (extraccion.html)
3. Seleccionar compañía y año
4. Ejecutar ETL
5. Ver estadísticas:
   - Extranjeros
   - Nacionales
   - ⚠️ **Ambiguos** (si hay)

### Opción 2: API
```bash
# Ejecutar ETL
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 1, "añoCalculo": 2024}'

# Ver resultados
curl http://localhost:5071/api/calculo/resultado/1/2024
```

### Opción 3: SQL Directo
Usar queries de validación del documento **PRUEBAS_FISCAL_SIMULADO.md**

---

## 📁 Documentos Actualizados

1. **CLASIFICACION_ACTIVOS.md** - Criterios detallados (nuevo)
2. **FISCAL_SIMULADO.md** - Documentación técnica completa (actualizado)
3. **RESUMEN_FISCAL_SIMULADO.md** - Resumen de implementación (actualizado)
4. **PRUEBAS_FISCAL_SIMULADO.md** - Guía de pruebas (nuevo)
5. **RESUMEN_CRITERIOS_ACTUALIZADOS.md** - Este documento (nuevo)

---

## ⚠️ Importante

### Activos Ambiguos son un ERROR
- No deben existir en un sistema bien configurado
- Si se detectan → Corregir en sistema Actif
- NO se procesan automáticamente
- Requieren revisión manual

### ¿Cómo Corregir un Activo Ambiguo?

En el sistema **Actif**, establecer **solo uno** de los costos:

**Si es extranjero:**
```sql
UPDATE activo
SET COSTO_REVALUADO = NULL  -- Eliminar fiscal
WHERE ID_NUM_ACTIVO = XXX;
```

**Si es nacional:**
```sql
UPDATE activo
SET COSTO_REEXPRESADO = NULL  -- Eliminar USGAAP
WHERE ID_NUM_ACTIVO = XXX;
```

---

## 🎯 Próximos Pasos

1. ✅ Documentación actualizada
2. ⏳ Actualizar stored procedures con nuevos criterios
3. ⏳ Crear vista vw_Activos_Ambiguos
4. ⏳ Modificar interfaz web para mostrar advertencias
5. ⏳ Probar con datos reales
6. ⏳ Validar con cliente/contador

---

## 📞 Sistema Activo

El sistema **ActifRMF** está corriendo en:
- **URL:** http://localhost:5071
- **Puerto:** 5071
- **Base de datos:** Actif_RMF (dbdev.powerera.com)
- **Estado:** ✅ Activo

---

**Versión:** 2.0
**Fecha:** 2025-10-29
**Cambio:** Clasificación por slots de costo (COSTO_REEXPRESADO vs COSTO_REVALUADO)
**Proyecto:** ActifRMF
