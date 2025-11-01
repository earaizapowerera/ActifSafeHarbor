# Cambios Versión 3.0: Fórmulas Correctas del Excel

## Resumen Ejecutivo

Se actualizó el sistema ActifRMF (versión 3.0) para implementar las fórmulas EXACTAS del archivo Excel "Propuesta reporte Calculo AF.xlsx", con soporte completo para los criterios de clasificación actualizados y manejo de casos especiales.

**Fecha:** 2025-10-29
**Versión:** 3.0.0

---

## 🎯 Cambios Principales

### 1. Clasificación Actualizada de Activos

**Antes (v2.x):**
- Usaba `ID_PAIS` y `FLG_PROPIO`

**Ahora (v3.0):**
- Usa **slots de costo**:
  - **Extranjeros**: `COSTO_REEXPRESADO > 0` AND `COSTO_REVALUADO = 0`
  - **Nacionales**: `COSTO_REVALUADO > 0` AND `COSTO_REEXPRESADO = 0`
  - **Ambiguos**: Ambos > 0 (ERROR - no procesar)

### 2. Fórmulas Correctas del Excel

#### Activos Extranjeros
```
Formula Final = IF(Proporción > 10% MOI, Proporción, 10% MOI) × TC_30_Junio

Donde:
  Proporción = (Monto_Pendiente / 12) × Meses_Ejercicio
  Monto_Pendiente = Saldo_Inicio - Dep_Ejercicio
  Saldo_Inicio = MOI - Dep_Acum_Inicio
  Dep_Ejercicio = MOI × Tasa_Mensual × Meses_Hasta_Mitad_Periodo
```

**Características:**
- ✅ NO usa INPC
- ✅ SÍ usa regla 10% MOI mínimo (Art 182 LISR)
- ✅ Convierte a MXN con TC del 30 de junio
- ✅ Usa meses HASTA LA MITAD del periodo para depreciación

#### Activos Nacionales (Por Implementar)
```
Formula Final = (Saldo_Actualizado - 50% × Dep_Actualizada) / 12 × Meses_Ejercicio

Donde:
  Saldo_Actualizado = Saldo_Inicio × (INPC_Jun / INPC_Adqu)
  Dep_Actualizada = Dep_Ejercicio × (INPC_MitadPeriodo / INPC_Adqu)
```

**Características:**
- ✅ SÍ usa actualización INPC
- ✅ NO usa regla 10% MOI
- ✅ Calcula "valor promedio" del activo
- ✅ Usa meses COMPLETOS del ejercicio

### 3. Manejo de Casos Especiales

El sistema ahora detecta y maneja correctamente:

| Caso | Observación en Excel | Manejo en v3.0 |
|------|----------------------|----------------|
| **Activo en uso** | "Activo en uso en 2024" | Meses_Mitad = 6, Meses_Ejercicio = 12 |
| **Adquirido antes junio** | "Activo adquirido en 2024 antes junio" | Meses_Mitad = desde adq hasta jun, Meses_Ejercicio = desde adq hasta dic |
| **Adquirido después junio** | "Activo adquirido en 2024 después junio" | Meses_Mitad = (meses_totales / 2), Meses_Ejercicio = desde adq hasta dic |
| **Dado de baja** | "Activo dado de baja en 2024" | Meses_Mitad = MIN(mes_baja, 6), Meses_Ejercicio = mes_baja |
| **Totalmente depreciado** | "Activo en uso prueba 10% MOI" | Aplica 10% MOI mínimo |
| **Terreno** | "Terreno en uso en 2024" | Sin depreciación, usa 10% MOI directo |
| **Edificio depreciado** | "Edificio dado de baja en 2024 totalmente depreciado" | Manejo especial de baja |

### 4. Detección de Activos Ambiguos

**Nuevo:** El sistema detecta activos con configuración ambigua (ambos costos > 0) y:
- ✅ Los registra en tabla `Log_Activos_Ambiguos`
- ✅ NO los procesa en cálculos automáticos
- ✅ Genera reporte de corrección
- ✅ Alerta en el resumen del SP

---

## 📁 Archivos Creados/Modificados

### Nuevos Archivos SQL

1. **20_SP_Calcular_RMF_Unificado.sql**
   - Stored procedure principal v3.0
   - Implementa clasificación por slots
   - Fórmulas correctas para extranjeros
   - Manejo de casos especiales

2. **21_CREATE_Log_Activos_Ambiguos.sql**
   - Tabla de log para activos ambiguos
   - Vista `vw_Activos_Ambiguos_Activos`
   - Queries de consulta

### Documentación Actualizada

3. **CAMBIOS_V3_FORMULAS_CORRECTAS.md** (este archivo)
4. **CLASIFICACION_ACTIVOS.md** (actualizado previamente)
5. **FISCAL_SIMULADO.md** (actualizado previamente)

---

## 🚀 Cómo Usar el Nuevo Sistema

### Opción 1: Desde SQL

```sql
-- 1. Crear tablas necesarias (primera vez)
:r 21_CREATE_Log_Activos_Ambiguos.sql

-- 2. Crear/actualizar SP
:r 20_SP_Calcular_RMF_Unificado.sql

-- 3. Ejecutar cálculo
EXEC dbo.sp_Calcular_RMF_Unificado
    @ID_Compania = 1,
    @Año_Calculo = 2024,
    @Lote_Importacion = 'GUID-DEL-ETL';

-- 4. Ver resultados
SELECT * FROM Calculo_RMF WHERE Lote_Calculo = 'GUID-RESULTADO';

-- 5. Ver activos ambiguos (si hay)
SELECT * FROM vw_Activos_Ambiguos_Activos;
```

### Opción 2: Desde la Interfaz Web

```
1. http://localhost:5071/extraccion.html
   - Ejecutar ETL
   - Ver advertencia si hay activos ambiguos

2. http://localhost:5071/calculo.html
   - Ejecutar cálculo RMF
   - Ver resumen con clasificación correcta

3. http://localhost:5071/reportes.html (por implementar)
   - Ver reporte de activos ambiguos
   - Exportar a Excel
```

---

## 📊 Estructura de Resultados

### Tabla: Calculo_RMF (Actualizada)

Campos nuevos/modificados:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `Meses_Uso_Hasta_Mitad_Periodo` | INT | **CRÍTICO**: Meses para cálculo depreciación |
| `Prueba_10_Pct_MOI` | DECIMAL | 10% del MOI (para extranjeros) |
| `Aplica_10_Pct` | BIT | 1 = Usó 10% MOI, 0 = Usó proporción |
| `Fuente_Dep_Acum` | NVARCHAR | 'Fiscal Real', 'Fiscal Simulado', 'Sin Depreciación' |
| `Ruta_Calculo` | NVARCHAR | Código del caso (EXT-BAJA, EXT-10PCT, etc.) |
| `Descripcion_Ruta` | NVARCHAR | Descripción legible del caso |
| `Observaciones` | NVARCHAR | Detalles específicos del activo |

### Tabla: Log_Activos_Ambiguos (Nueva)

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `ID_Log` | BIGINT | PK |
| `ID_Staging` | BIGINT | Referencia al staging |
| `COSTO_REEXPRESADO` | DECIMAL | Costo USGAAP (conflicto) |
| `COSTO_REVALUADO` | DECIMAL | Costo Fiscal (conflicto) |
| `Estado` | NVARCHAR | Pendiente, Corregido, Ignorado |
| `Fecha_Deteccion` | DATETIME | Cuándo se detectó |

---

## ⚠️ Diferencias Críticas vs Versión Anterior

### 1. Meses para Depreciación de Extranjeros

**Antes:**
```sql
Dep_Ejercicio = MOI × Tasa_Mensual × Meses_Ejercicio_Completos
```

**Ahora (CORRECTO):**
```sql
Dep_Ejercicio = MOI × Tasa_Mensual × Meses_Hasta_Mitad_Periodo
```

**Impacto:** Los activos extranjeros ahora calculan depreciación solo hasta la mitad del periodo, como indica el Excel.

### 2. Regla del 10% MOI

**Antes:**
- Se aplicaba ocasionalmente o incorrectamente

**Ahora (CORRECTO):**
- Se aplica SIEMPRE para extranjeros
- Fórmula: `IF(Proporción > 10% MOI, Proporción, 10% MOI)`
- Campo `Aplica_10_Pct` indica cuándo se usó

### 3. Clasificación de Activos

**Antes:**
- `ID_PAIS > 1` = Extranjero

**Ahora (CORRECTO):**
- `COSTO_REEXPRESADO > 0` AND `COSTO_REVALUADO = 0` = Extranjero
- `COSTO_REVALUADO > 0` AND `COSTO_REEXPRESADO = 0` = Nacional
- Ambos > 0 = ERROR

---

## 📈 Casos de Prueba

### Caso 1: Activo Extranjero en Uso Normal

```
Activo: Servidor HP
COSTO_REEXPRESADO: $100,000 USD
COSTO_REVALUADO: 0
FECHA_COMPRA: 20/01/2019
Tasa: 8% anual (0.667% mensual)

Resultado esperado:
  Meses_Inicio: 60
  Meses_Mitad: 6
  Meses_Ejercicio: 12
  Dep_Acum_Inicio: 100000 × 0.00667 × 60 = 40,000
  Saldo_Inicio: 60,000
  Dep_Ejercicio: 100000 × 0.00667 × 6 = 4,000
  Monto_Pendiente: 56,000
  Proporción: 56000/12 × 12 = 56,000
  10% MOI: 10,000
  Valor_USD: 56,000 (> 10% MOI)
  Valor_MXN: 56000 × 18.2478 = 1,021,877 MXN
```

### Caso 2: Activo Extranjero con 10% MOI

```
Activo: Equipo Industrial
COSTO_REEXPRESADO: $800,000 USD
FECHA_COMPRA: 20/01/2012 (ya casi depreciado)

Resultado esperado:
  Proporción calculada: ~64,000 USD (8% del MOI)
  10% MOI: 80,000 USD
  Valor_USD: 80,000 USD (se usa 10% MOI)
  Aplica_10_Pct: 1
  Observaciones: "Activo en uso prueba 10% MOI"
```

### Caso 3: Activo Adquirido Después de Junio

```
Activo: Maquinaria
COSTO_REEXPRESADO: $550,000 USD
FECHA_COMPRA: 20/07/2024

Resultado esperado:
  Meses_Mitad: 3 (mitad del periodo jul-dic)
  Meses_Ejercicio: 6
  Observaciones: "Activo adquirido en 2024 después de junio"
```

---

## 🔧 Pendientes para Completar v3.0

- [ ] **Implementar fórmulas de activos nacionales**
  - Con actualización INPC
  - Con valor promedio
  - Sin regla 10% MOI

- [ ] **Actualizar interfaz web**
  - Mostrar advertencia de activos ambiguos
  - Agregar reporte de ambigüedad
  - Exportar a Excel con formato correcto

- [ ] **Pruebas con datos reales**
  - Comparar resultados con Excel
  - Validar casos especiales
  - Confirmar con cliente/contador

- [ ] **Documentación de usuario**
  - Manual de operación
  - Guía de corrección de activos ambiguos
  - FAQ

---

## 📞 Prueba Rápida del Sistema

```bash
# Sistema corriendo en:
http://localhost:5071

# Verificar que el sistema está activo:
curl http://localhost:5071/health

# Ver clasificación de activos actuales:
# (ejecutar desde SQL Server)
```

```sql
SELECT
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN '⚠️ AMBIGUO'
        ELSE 'Sin Costo'
    END AS Tipo,
    COUNT(*) AS Cantidad
FROM Staging_Activo
WHERE ID_Compania = 1
  AND Año_Calculo = 2024
GROUP BY
    CASE
        WHEN COSTO_REEXPRESADO > 0 AND ISNULL(COSTO_REVALUADO, 0) = 0
            THEN 'Extranjero'
        WHEN COSTO_REVALUADO > 0 AND ISNULL(COSTO_REEXPRESADO, 0) = 0
            THEN 'Nacional'
        WHEN COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO > 0
            THEN '⚠️ AMBIGUO'
        ELSE 'Sin Costo'
    END;
```

---

## 📖 Referencias

- **Excel fuente**: `/Users/enrique/ActifRMF/Propuesta reporte Calculo AF.xlsx`
- **Documentación de fórmulas**: `FORMULAS_EXCEL_COMPLETAS.md`
- **Clasificación de activos**: `CLASIFICACION_ACTIVOS.md`
- **Fiscal simulado**: `FISCAL_SIMULADO.md`
- **Marco legal**: `RMF.md`

---

**Versión:** 3.0.0
**Estado:** Activos extranjeros implementados, nacionales pendientes
**Fecha:** 2025-10-29
**Proyecto:** ActifRMF
