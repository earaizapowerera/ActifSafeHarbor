# Changelog - ActifRMF

## [2.4.0] - 2025-11-20

### 🎯 Cambios Principales

**Fix crítico**: Depreciación acumulada y factores fiscales ahora calculados correctamente

### ✅ Corregido

#### 1. Factores Fiscales Incorrectos (Factor = 1.0)
**Problema**: `sp_Actualizar_INPC_Nacionales v2.3` tenía condición `WHERE INPCCompra IS NULL` que causaba que NO procesara ningún activo porque `sp_Calcular_RMF_Activos_Nacionales` ya poblaba el INPCCompra.

**Solución**:
- Actualizado `sp_Actualizar_INPC_Nacionales` a **v2.4**
- Removida condición restrictiva `WHERE INPCCompra IS NULL`
- Ahora procesa TODOS los activos nacionales
- Resultado: Factores fiscales correctos (ej: 4.882 en lugar de 1.0)

**Archivos modificados**:
- `Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql`

#### 2. Depreciación Acumulada Incorrecta
**Problema**: Sistema traía depreciación acumulada del sistema origen (Actif) con datos históricos incorrectos. Ejemplo: Folio 50847 mostraba $249.18 cuando debería ser $83,974.78 (totalmente depreciado).

**Solución**:
- Modificado Query ETL para traer `NULL AS Dep_Acum_Inicio_Año`
- Activado cálculo automático en `sp_Calcular_RMF_Activos_Nacionales v5.3`
- Fórmula aplicada: `Dep_Acum = MOI × Tasa_Mensual × Meses_Uso_Inicio`
- Ahora calcula igual que activos extranjeros (consistencia)

**Cambios en Base de Datos**:
```sql
-- ANTES:
ISNULL(c_hist.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año

-- DESPUÉS:
NULL AS Dep_Acum_Inicio_Año  -- Forzar cálculo automático
```

**Archivos modificados**:
- `ConfiguracionCompania.Query_ETL` (Compañía 188)

### 🔧 Mejoras

#### Separación de Columnas Fiscal vs Safe Harbor
- Renombradas columnas con prefijos `FI_` (Fiscal) y `SH_` (Safe Harbor)
- Colores distintivos en reporte:
  - 🔵 Azul: Fiscal Paso 1
  - 🟡 Amarillo: Fiscal Paso 2
  - 🟢 Verde: Safe Harbor
  - ⚪ Blanco: Compartido (INPC Adquisición)

**Archivos modificados**:
- `ActifRMF/wwwroot/js/reporte.js`
- `ActifRMF/Program.cs` (consulta con campos SH_ pre-calculados)

### 📚 Documentación

#### Nuevos Documentos
- `ANALISIS_COMPLETO_CASO_1_FOLIO_50847_FINAL.txt` - Análisis detallado con valores correctos
- `CASOS_USO_NACIONALES_2025.txt` - 7 casos de uso para validación manual

#### Casos de Uso Revisados
- ✅ **CASO 1**: Folio 50847 - Edificio totalmente depreciado (RevisadoOK)

### 🔢 Versionamiento

**Versión**: 2.4.0
- **2**: Major version (sistema estable)
- **4**: Corrección crítica de factores INPC
- **0**: Sin cambios menores adicionales

**AssemblyVersion**: 2.4.0.0
**InformationalVersion**: 2.4.0-AutoDepCalc+INPCv2.4

### 📊 Impacto

#### Antes (v2.3 - Incorrecto):
```
Factor_Actualizacion_Saldo:  1.0000 ❌
Dep_Acum_Inicio:            $249.18 ❌
Saldo_Actualizado:          $290,746.63 ❌
Valor_Reportable:           $283,447.55 ❌
```

#### Después (v2.4 - Correcto):
```
Factor_Actualizacion_Saldo:  4.8820 ✅
Dep_Acum_Inicio:            $83,974.78 ✅
Saldo_Actualizado:          $0.00 ✅
Valor_Reportable:           $5,980.40 ✅ (10% MOI)
```

### 🧪 Validación

**Compañías validadas**:
- ✅ Compañía 188 (8 activos nacionales)
- ⏳ Compañía 12 (pendiente)
- ⏳ Compañía 122 (pendiente)
- ⏳ Compañía 123 (pendiente)

**Casos de uso**:
- ✅ Caso 1: Edificio totalmente depreciado - CORRECTO
- ⏳ Caso 2: Vehículo tasa 25% - Pendiente
- ⏳ Casos 3-7 - Pendiente

### 🚀 Deployment

**Stored Procedures actualizados**:
- `sp_Actualizar_INPC_Nacionales` v2.4 (desplegado)
- `sp_Calcular_RMF_Activos_Nacionales` v5.3 (ya estaba desplegado)

**Queries ETL actualizados**:
- Compañía 188: Query modificado para traer NULL en Dep_Acum

### ⚠️ Notas Importantes

1. **Cálculo automático ahora es obligatorio**: El sistema ya NO trae depreciación acumulada del sistema origen. Siempre la calcula.

2. **Consistencia nacional/extranjero**: Ambos tipos de activos ahora usan la misma lógica para calcular depreciación acumulada.

3. **Activos totalmente depreciados**: Se detectan automáticamente cuando `Dep_Acum > MOI` y se limitan correctamente a saldo $0.00.

4. **Regla 10% MOI**: Se aplica correctamente para activos sin valor (totalmente depreciados), reportando mínimo 10% del MOI.

### 🔗 Referencias

- Art. 182 LISR - Safe Harbor para activos no propios
- `RMF.md` - Documentación completa de reglas fiscales
- `ETL.md` - Documentación del proceso ETL

---

## [2.3.0] - 2025-11-15

### Agregado
- Separación de cálculos Fiscal vs Safe Harbor en SP
- Campos INPC_SH_Junio, Factor_SH, Saldo_SH_Actualizado, etc.
- FECHA_FIN_DEPREC calculada automáticamente

### Mejorado
- Validación de INPC faltantes con mensajes de error claros
- Cálculo automático de Dep_Acum cuando es 0 o NULL (v5.3)

---

## [2.2.0] - 2025-11-10

### Agregado
- Sistema de reportes con AG-Grid
- Exportación a Excel con SheetJS
- Separación de tabs Nacional/Extranjero

---

## [2.1.0] - 2025-11-05

### Agregado
- ETL optimizado con SqlBulkCopy
- Queries configurables por compañía en `ConfiguracionCompania`
- Performance mejorado 10-50x

---

## [2.0.0] - 2025-10-20

### Agregado
- API .NET 9.0
- Stored procedures para cálculo Safe Harbor
- Arquitectura de 3 tablas (Staging → Calculo → Reporte)
