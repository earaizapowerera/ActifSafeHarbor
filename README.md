# ActifRMF - Sistema de Cálculo Safe Harbor (Art. 182 LISR)

## Descripción General

Sistema para calcular la deducción mínima de activos fijos conforme al **Safe Harbor del Artículo 182 de la Ley del Impuesto Sobre la Renta (LISR)**.

El sistema implementa un proceso ETL completo que:
1. Extrae datos del sistema Actif (base de datos de activos fijos)
2. Calcula la deducción Safe Harbor aplicando fórmulas fiscales específicas
3. Genera reportes en Excel para presentación de impuestos

---

## 🏢 Clasificación de Activos: Nacionales vs Extranjeros

**⚠️ IMPORTANTE**: La clasificación de activos NO se basa en la procedencia geográfica del activo, sino en **quién es el DUEÑO actual**.

### Activos EXTRANJEROS (USGAAP)
**Definición**: Activos propiedad de una empresa **americana** que los deja en **consignación** a la empresa mexicana.

**Criterios de identificación:**
- `FLG_NOCAPITALIZABLE_3 = 'S'` (Maneja USGAAP)
- `COSTO_REEXPRESADO > 0` (Costo reexpresado en USD)

**Tratamiento fiscal:**
- MOI: `COSTO_REEXPRESADO` (en USD)
- Conversión a MXN: `CostoUSD × Tipo_Cambio_30_Junio`
- **Depreciación acumulada**: **SIEMPRE se calcula** (no se usa histórico)
  - Fórmula: `MOI × Tasa_Mensual × Meses_Uso_Inicio_Ejercicio`
  - Si excede MOI: se limita a MOI (100% depreciado)

### Activos NACIONALES (Fiscal)
**Definición**: Activos propiedad de la empresa **mexicana** (sin importar su procedencia o fabricación).

**Criterios de identificación:**
- `FLG_NOCAPITALIZABLE_2 = 'S'` (Maneja Fiscal)
- `COSTO_REVALUADO > 0` (Costo revaluado/fiscal en MXN)

**Tratamiento fiscal:**
- MOI: `COSTO_REVALUADO` (en MXN directo)
- **Depreciación acumulada**: **NUNCA se calcula** (se usa el histórico del sistema Actif)
  - Se obtiene de: `calculo.ACUMULADO_HISTORICA` (Dic año anterior)
  - Si no existe: se pone 0

### ⚠️ ERROR DE DEDO
**Activos que cumplen AMBAS condiciones simultáneamente NO se procesan:**
- `FLG_NOCAPITALIZABLE_2 = 'S'` AND `FLG_NOCAPITALIZABLE_3 = 'S'`

Esto indica un error de captura en el sistema origen y el ETL los **omite automáticamente** con una advertencia en el log.

---

## 📊 Arquitectura del Sistema

### Arquitectura de 3 Tablas

```
┌─────────────────────────┐
│  actif_web_CIMA_Dev    │  ← Sistema ORIGEN (otra BD - puede ser remota)
│  (BD de Actif)         │     Contiene: activos, tasas, INPC, depreciación histórica
└────────────┬────────────┘
             │
             │ ETL .NET (ActifRMF.ETL) - FUNCIONA COMO PUENTE
             │ Lee de BD origen, procesa, inserta en BD destino
             │ NO usa OPENROWSET ni queries distribuidas
             ▼
┌─────────────────────────┐
│   Staging_Activo       │  ← TABLA TEMPORAL (staging)
│   (Actif_RMF)          │     Solo para IMPORTAR datos RAW
└────────────┬────────────┘     Contiene: Folio, MOI, Tasas, Dep_Acum_Inicio, INPC
             │
             │ SP Cálculo lee de aquí
             │ (sp_Calcular_RMF_Activos_Extranjeros)
             │ (sp_Calcular_RMF_Activos_Nacionales)
             ▼
┌─────────────────────────┐
│   Calculo_RMF          │  ← TABLA DEFINITIVA (resultados)
│   (Actif_RMF)          │     Todos los cálculos Safe Harbor
└────────────┬────────────┘     Contiene: TODAS las columnas del Excel
             │
             │ API Lee de aquí (/api/reporte)
             ▼
┌─────────────────────────┐
│   Excel (Reporte)      │  ← PRODUCTO FINAL
│   - Extranjeros        │     Para presentar a impuestos
│   - Nacionales         │
└─────────────────────────┘
```

---

## 🔄 Flujo Completo del Proceso

### PASO 1: ETL (Extracción)

**⚠️ IMPORTANTE**: El ETL se ejecuta desde la **aplicación .NET**, NO desde stored procedures con OPENROWSET.

**Programa ETL**: `/Users/enrique/actifrmf/ETL_NET/ActifRMF.ETL/Program.cs`
**Tabla destino**: `Staging_Activo`
**📄 Documentación detallada**: Ver [ETL.md](ETL.md)

#### Características Principales

✅ **Query Configurable** - Cada compañía tiene su propio query en `ConfiguracionCompania.Query_ETL`
✅ **SqlBulkCopy** - Inserciones masivas ultra-rápidas (10-50x más rápido que INSERTs)
✅ **LEFT JOIN Optimizado** - Usa índices en lugar de subqueries
✅ **Sin INPC** - INPC se calcula en fase de cálculo, no en ETL
✅ **Arquitectura de Puente** - Funciona sin visibilidad entre BDs

#### ¿Qué hace el ETL .NET?

1. **Limpia datos previos** - Elimina de `Calculo_RMF` y `Staging_Activo`
2. **Lee query de BD** - Obtiene query personalizado de `ConfiguracionCompania`
3. **Extrae activos** - Ejecuta query con parámetros (@ID_Compania, @Año_Calculo, @Año_Anterior)
4. **Transforma en memoria** - Calcula CostoUSD, CostoMXN, Tasa_Mensual
5. **Valida datos** - Detecta "ERROR DE DEDO" (ambos flags activos)
6. **Inserta con SqlBulkCopy** - Carga masiva en `Staging_Activo`

#### Performance

| Activos | Tiempo (aprox) |
|---------|---------------|
| 100 | ~0.5 seg |
| 1,000 | ~5 seg |
| 10,000 | ~50 seg |

#### Ejecución

**Línea de comandos:**
```bash
dotnet run 188 2024
```

**API Web:**
```bash
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -d '{"idCompania": 188, "añoCalculo": 2024}'
```

**Interfaz Web:** http://localhost:5071/extraccion.html

Para más detalles sobre el query, configuración y troubleshooting, ver **[ETL.md](ETL.md)**

---

### PASO 2: CÁLCULO (Safe Harbor)

**Stored Procedures**:
- `sp_Calcular_RMF_Activos_Extranjeros` - Para activos extranjeros
- `sp_Calcular_RMF_Activos_Nacionales` - Para activos nacionales

**Tabla origen**: `Staging_Activo`
**Tabla destino**: `Calculo_RMF`

**¿Qué hace?**
1. Lee datos de `Staging_Activo`
2. Calcula **TODAS** las columnas del Excel aplicando fórmulas Safe Harbor
3. Inserta el registro completo en `Calculo_RMF`

**IMPORTANTE**: El cálculo hace INSERT completo, NO hace UPDATE parcial.

---

### PASO 3: REPORTE (Excel)

**API Endpoint**: `/api/reporte`
**Tabla origen**: `Calculo_RMF`

**¿Qué hace?**
- Lee **SOLO** de `Calculo_RMF`
- **NO hace cálculos** - solo formatea
- Exporta a Excel usando SheetJS

---

## 📋 Campos del Excel y Fórmulas

### Activos EXTRANJEROS (ID_PAIS > 1)

| # | Columna Excel | Campo BD | Fórmula / Cálculo |
|---|--------------|----------|-------------------|
| 1 | Compañía | Nombre_Compania | De ConfiguracionCompania |
| 2 | Folio | ID_NUM_ACTIVO | Del sistema origen |
| 3 | Placa | ID_ACTIVO | De Staging_Activo |
| 4 | Descripción | DESCRIPCION | De Staging_Activo |
| 5 | Tipo | Nombre_TipoActivo | De Staging_Activo |
| 6 | Fecha Adquisición | FECHA_COMPRA | De Staging_Activo |
| 7 | Fecha Baja | FECHA_BAJA | De Staging_Activo (NULL si activo) |
| 8 | **MOI** (A) | MOI | `COSTO_ADQUISICION` del sistema origen |
| 9 | **Anual Rate** (B) | Tasa_Anual | `PORCENTAJE / 100` (ej: 8 → 0.08) |
| 10 | **Month Rate** (C) | Tasa_Mensual | `Tasa_Anual / 12` (ej: 0.08 → 0.006667) |
| 11 | **Deprec Anual** (D) | Dep_Anual | `MOI * Tasa_Anual` |
| 12 | **Meses Uso Inicio Ejerc.** (E) | Meses_Uso_Inicio_Ejercicio | `DATEDIFF(MONTH, FECHA_COMPRA, '2024-01-01')` |
| 13 | **Meses Uso Hasta Mitad** (F) | Meses_Uso_Hasta_Mitad_Periodo | `DATEDIFF(MONTH, FECHA_COMPRA, '2024-06-30')` |
| 14 | **Meses Uso En Ejercicio** (G) | Meses_Uso_En_Ejercicio | `DATEDIFF(MONTH, '2024-01-01', fecha_fin)` |
| 15 | **Dep Fiscal Acum. Inicio Año** (H) | Dep_Acum_Inicio | **EXTRANJEROS**: `MOI * Tasa_Mensual * Meses_Uso_Inicio_Ejercicio` |
| 16 | **Saldo Por Deducir ISR Inicio** (I) | Saldo_Inicio_Año | `MOI - Dep_Acum_Inicio` |
| 17 | **Dep Fiscal Ejercicio** (J) | Dep_Fiscal_Ejercicio | `MOI * Tasa_Mensual * Meses_Uso_En_Ejercicio` |
| 18 | **Monto Pendiente** (K) | Monto_Pendiente | `Saldo_Inicio_Año - Dep_Fiscal_Ejercicio` |
| 19 | **Proporción** (L) | Proporcion | `(Saldo_Inicio_Año + Monto_Pendiente) / 2` |
| 20 | **Prueba 10% MOI** (M) | Prueba_10_Pct_MOI | `MOI * 0.10` |
| 21 | **Aplica 10%?** | Aplica_10_Pct | `IF(Proporcion < Prueba_10_Pct_MOI, TRUE, FALSE)` |
| 22 | **Tipo Cambio 30 Junio** (N) | Tipo_Cambio_30_Junio | Del sistema (18.2478 para 2024) |
| 23 | **Valor Reportable MXN** (O) | Valor_Reportable_MXN | `Proporcion * Tipo_Cambio_30_Junio` |
| 24 | Observaciones | Observaciones | Descripción de ruta + alertas |

---

### Activos NACIONALES (ID_PAIS = 1)

| # | Columna Excel | Campo BD | Fórmula / Cálculo |
|---|--------------|----------|-------------------|
| 1 | Compañía | Nombre_Compania | De ConfiguracionCompania |
| 2 | Folio | ID_NUM_ACTIVO | Del sistema origen |
| 3 | Placa | ID_ACTIVO | De Staging_Activo |
| 4 | Descripción | DESCRIPCION | De Staging_Activo |
| 5 | Tipo | Nombre_TipoActivo | De Staging_Activo |
| 6 | Fecha Adquisición | FECHA_COMPRA | De Staging_Activo |
| 7 | Fecha Baja | FECHA_BAJA | De Staging_Activo (NULL si activo) |
| 8 | **MOI** (A) | MOI | `COSTO_ADQUISICION` del sistema origen |
| 9 | **Anual Rate** (B) | Tasa_Anual | `PORCENTAJE / 100` (ej: 10 → 0.10) |
| 10 | **Month Rate** (C) | Tasa_Mensual | `Tasa_Anual / 12` |
| 11 | **Deprec Anual** (D) | Dep_Anual | `MOI * Tasa_Anual` |
| 12 | **Meses Uso Al Ejerc. Anterior** (E) | Meses_Uso_Inicio_Ejercicio | `DATEDIFF(MONTH, FECHA_COMPRA, '2024-01-01')` |
| 13 | **Meses Uso En Ejercicio** (G) | Meses_Uso_En_Ejercicio | `DATEDIFF(MONTH, '2024-01-01', fecha_fin)` |
| 14 | **Dep Fiscal Acum. Inicio Año** (H) | Dep_Acum_Inicio | **NACIONALES**: `Dep_Acum_Inicio_Año` del sistema origen |
| 15 | **Saldo Por Deducir ISR Inicio** (I) | Saldo_Inicio_Año | `MOI - Dep_Acum_Inicio` |
| 16 | **INPC Adquisición** (P1) | INPC_Adqu | Del mes de FECHA_COMPRA |
| 17 | **INPC Mitad Ejercicio** (Q1) | INPC_Mitad_Ejercicio | Del 30-Jun-2024 |
| 18 | **Factor Actualiz. (P1)** (R1) | Factor_Actualizacion_Saldo | `INPC_Mitad_Ejercicio / INPC_Adqu` |
| 19 | **Saldo Actualizado (P1)** (S1) | Saldo_Actualizado | `Saldo_Inicio_Año * Factor_Actualizacion_Saldo` |
| 20 | **Dep Fiscal Ejercicio** (J) | Dep_Fiscal_Ejercicio | `MOI * Tasa_Mensual * Meses_Uso_En_Ejercicio` |
| 21 | **INPC Adquisición (P2)** | INPC_Adqu | (mismo que P1) |
| 22 | **INPC Mitad Periodo** (Q2) | INPC_Mitad_Periodo | Del mes mitad del periodo usado |
| 23 | **Factor Actualiz. (P2)** (R2) | Factor_Actualizacion_Dep | `INPC_Mitad_Periodo / INPC_Adqu` |
| 24 | **Deprec Fiscal Actualizada** (T) | Dep_Actualizada | `Dep_Fiscal_Ejercicio * Factor_Actualizacion_Dep` |
| 25 | **50% Deprec Fiscal** (U) | - | `Dep_Actualizada * 0.5` |
| 26 | **Valor Promedio** (V) | Valor_Promedio | `Saldo_Actualizado - (Dep_Actualizada * 0.5)` |
| 27 | **Valor Prom. Prop. Año** (W) | Proporcion | `Valor_Promedio * (Meses_Uso_En_Ejercicio / 12)` |
| 28 | **Saldo Fiscal Deducir Hist.** (X) | - | `MOI - Dep_Acum_Inicio - Dep_Fiscal_Ejercicio` |
| 29 | **Saldo Fiscal Deducir Actual.** (Y) | - | `Saldo_Fiscal_Hist * Factor_Actualizacion_Dep` |
| 30 | **Prueba 10% MOI** | Prueba_10_Pct_MOI | `MOI * 0.10` |
| 31 | **Valor Reportable MXN** (Z) | Valor_Reportable_MXN | `MAX(Proporcion, Prueba_10_Pct_MOI)` |
| 32 | Estado (B/A) | - | `IF(FECHA_BAJA IS NOT NULL, "B", "A")` |
| 33 | Observaciones | Observaciones | Descripción de ruta + alertas |

---

## 🎯 Reglas de Negocio Safe Harbor

### Clasificación de Activos

**Por Nacionalidad** (`ID_PAIS`):
- **Nacional**: `ID_PAIS = 1` (México)
- **Extranjero**: `ID_PAIS > 1` (ej: 2=Estados Unidos)

**Por Ownership** (`FLG_PROPIO`):
- **FLG_PROPIO = 0**: **NO propio** → **INCLUIR en reporte**
- **FLG_PROPIO = 1**: Propio → **EXCLUIR del reporte**

**CRÍTICO**: Solo se reportan activos con `FLG_PROPIO = 0` (NO propios).

---

### Rutas de Cálculo

El sistema clasifica cada activo en una "ruta" que determina el cálculo:

#### Extranjeros:
- **1.3.1.1** - Extranjero, Baja en año
- **1.3.1.2** - Extranjero, Alta en año
- **1.3.1.3** - Extranjero, Alta y baja en año
- **1.3.1.4** - Extranjero, Activo todo el año

#### Nacionales:
- **2.1.1.1** - Nacional, Baja en año
- **2.1.1.2** - Nacional, Alta en año
- **2.1.1.3** - Nacional, Alta y baja en año
- **2.1.1.4** - Nacional, Activo todo el año

Cada ruta aplica fórmulas específicas para calcular meses de uso, depreciación y valores reportables.

---

### Safe Harbor - Regla 10% MOI

**Artículo 182 LISR**: La deducción mínima permitida es el **10% del MOI** (Monto Original de Inversión).

**Aplicación**:
```
Valor_Reportable = MAX(Proporcion, MOI * 0.10)
```

Si el valor calculado por depreciación es menor al 10% del MOI, se usa el 10% del MOI.

---

## 🔧 Stored Procedures

### 1. `sp_ETL_Importar_Activos`

**Archivo**: `/Users/enrique/ActifRMF/SQL/04_SP_ETL_Importar_Activos.sql`

**Función**: Importar datos del sistema Actif a Staging_Activo

**Parámetros**:
- `@ID_Compania INT` - ID de compañía
- `@Año_Calculo INT` - Año fiscal
- `@Usuario NVARCHAR(100)` - Usuario ejecutando

**Proceso**:
1. Valida compañía y obtiene connection string
2. Limpia datos anteriores de Staging_Activo
3. Construye query dinámico con OPENROWSET
4. Importa datos aplicando transformaciones:
   - Tasa_Anual = PORCENTAJE / 100.0
   - Tasa_Mensual = PORCENTAJE / 1200.0
5. Filtra: `FLG_PROPIO = 0` (solo NO propios)
6. Registra en log de ejecución

**Salida**: `Staging_Activo` poblada con datos RAW

---

### 2. `sp_Calcular_RMF_Activos_Extranjeros`

**Archivo**: `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros.sql`

**Función**: Calcular Safe Harbor para activos extranjeros

**Parámetros**:
- `@ID_Compania INT`
- `@Año_Calculo INT`
- `@Lote_Importacion UNIQUEIDENTIFIER`
- `@Usuario NVARCHAR(100)`

**Proceso**:
1. Lee activos extranjeros de Staging_Activo
2. Determina ruta de cálculo (1.3.1.1 a 1.3.1.4)
3. Calcula meses de uso
4. Calcula depreciación acumulada: `MOI * Tasa_Mensual * Meses`
5. Calcula saldo, proporción, 10% MOI
6. Convierte a MXN con tipo de cambio
7. Inserta en Calculo_RMF

**Salida**: `Calculo_RMF` con cálculos completos

---

### 3. `sp_Calcular_RMF_Activos_Nacionales`

**Archivo**: `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql`

**Función**: Calcular Safe Harbor para activos nacionales

**Similar a extranjeros, pero además**:
- Aplica actualización con INPC
- Calcula factor de actualización
- Actualiza saldo y depreciación con INPC
- Maneja casos especiales de INPC no encontrado

---

## 🗄️ Estructura de Base de Datos

### Tabla: `Staging_Activo`

**Propósito**: Tabla temporal de importación (ETL)

**Columnas principales**:
```sql
ID_Staging BIGINT IDENTITY(1,1) PRIMARY KEY
ID_Compania INT NOT NULL
ID_NUM_ACTIVO INT NOT NULL
ID_ACTIVO NVARCHAR(50) NULL -- Placa
ID_TIPO_ACTIVO INT NULL
ID_SUBTIPO_ACTIVO INT NULL
Nombre_TipoActivo NVARCHAR(200) NULL
DESCRIPCION NVARCHAR(500) NULL
ID_MONEDA INT NULL
Nombre_Moneda NVARCHAR(50) NULL
ID_PAIS INT NOT NULL -- 1=Nacional, >1=Extranjero
Nombre_Pais NVARCHAR(100) NULL
FECHA_COMPRA DATETIME NULL
FECHA_BAJA DATETIME NULL
FECHA_INICIO_DEP DATETIME NULL
STATUS NVARCHAR(10) NULL
FLG_PROPIO INT NULL -- 0=NO propio (incluir), 1=Propio (excluir)
Tasa_Anual DECIMAL(10,6) NULL -- DEBE ser 0.08, NO 8.0
Tasa_Mensual DECIMAL(10,6) NULL
Dep_Acum_Inicio_Año DECIMAL(18,4) NULL
INPC_Adquisicion DECIMAL(18,6) NULL -- Solo nacionales
INPC_Mitad_Ejercicio DECIMAL(18,6) NULL -- Solo nacionales
Año_Calculo INT NOT NULL
Fecha_Importacion DATETIME NOT NULL DEFAULT GETDATE()
Lote_Importacion UNIQUEIDENTIFIER NOT NULL
```

---

### Tabla: `Calculo_RMF`

**Propósito**: Tabla definitiva con resultados de cálculos

**Columnas principales**:
```sql
ID_Calculo BIGINT IDENTITY(1,1) PRIMARY KEY
ID_Staging BIGINT NOT NULL -- FK a Staging_Activo
ID_Compania INT NOT NULL
ID_NUM_ACTIVO INT NOT NULL
Año_Calculo INT NOT NULL
Tipo_Activo NVARCHAR(20) NULL -- 'Extranjero' o 'Nacional'
ID_PAIS INT NULL
Ruta_Calculo NVARCHAR(20) NULL -- '1.3.1.1', '2.1.1.4', etc.
Descripcion_Ruta NVARCHAR(200) NULL
MOI DECIMAL(18,4) NULL
Tasa_Anual DECIMAL(10,6) NULL
Tasa_Mensual DECIMAL(10,6) NULL
Dep_Anual DECIMAL(18,4) NULL
Meses_Uso_Inicio_Ejercicio INT NULL
Meses_Uso_Hasta_Mitad_Periodo INT NULL
Meses_Uso_En_Ejercicio INT NULL
Dep_Acum_Inicio DECIMAL(18,4) NULL
Saldo_Inicio_Año DECIMAL(18,4) NULL
Dep_Fiscal_Ejercicio DECIMAL(18,4) NULL
Monto_Pendiente DECIMAL(18,4) NULL
Proporcion DECIMAL(18,4) NULL
Prueba_10_Pct_MOI DECIMAL(18,4) NULL
Aplica_10_Pct BIT NULL
-- Para NACIONALES:
INPC_Adqu DECIMAL(18,6) NULL
INPC_Mitad_Ejercicio DECIMAL(18,6) NULL
INPC_Mitad_Periodo DECIMAL(18,6) NULL
Factor_Actualizacion_Saldo DECIMAL(18,10) NULL
Factor_Actualizacion_Dep DECIMAL(18,10) NULL
Saldo_Actualizado DECIMAL(18,4) NULL
Dep_Actualizada DECIMAL(18,4) NULL
Valor_Promedio DECIMAL(18,4) NULL
-- Para EXTRANJEROS:
Tipo_Cambio_30_Junio DECIMAL(18,6) NULL
Valor_Reportable_USD DECIMAL(18,4) NULL
-- COMÚN:
Valor_Reportable_MXN DECIMAL(18,4) NULL -- *** COLUMNA FINAL ***
Observaciones NVARCHAR(MAX) NULL
Fecha_Calculo DATETIME NOT NULL DEFAULT GETDATE()
Lote_Calculo UNIQUEIDENTIFIER NOT NULL
Version_SP NVARCHAR(20) NULL
```

---

## ⚠️ Problemas Conocidos y Soluciones

### Problema: Tasa_Anual guardada como 8.0 en lugar de 0.08

**Causa**: El SP desplegado en producción era una versión antigua que NO aplicaba la división `/100`.

**Solución temporal**: Ejecutar UPDATE manual:
```sql
UPDATE Staging_Activo
SET Tasa_Anual = Tasa_Anual / 100.0
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
```

**Solución permanente**: Re-desplegar SP corregido con:
```sql
pd.PORCENTAJE / 100.0 AS Tasa_Anual
```

**Nota**: Los cálculos usan `Tasa_Mensual` directamente, por lo que los resultados son correctos incluso si `Tasa_Anual` está incorrecta.

---

### Problema: Diferencias entre archivo SQL y base de datos

**Síntoma**: El archivo SQL espera columna `COSTO_ADQUISICION` pero la BD tiene `COSTO_REVALUADO`.

**Causa**: El esquema de la BD evolucionó sin actualizar los archivos SQL.

**Solución**: Actualizar SP para remover referencia a `COSTO_ADQUISICION` en el INSERT.

---

## 🚀 Cómo Usar el Sistema

### 1. Ejecutar ETL

**Via API**:
```bash
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 188, "añoCalculo": 2024, "usuario": "admin"}'
```

**Resultado**: `Staging_Activo` poblada con datos del año.

---

### 2. Ejecutar Cálculos

**Via API**:
```bash
curl -X POST http://localhost:5071/api/calculo/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 188, "añoCalculo": 2024, "usuario": "admin"}'
```

**Resultado**: `Calculo_RMF` con todos los cálculos Safe Harbor.

---

### 3. Generar Reporte Excel

**Via Web**: http://localhost:5071/reporte.html

**Via API**:
```bash
curl http://localhost:5071/api/reporte?año=2024&companias=188
```

**Resultado**: Archivo Excel con todas las columnas y cálculos.

---

## 📁 Estructura del Proyecto

```
ActifRMF/
├── ActifRMF/                    # Proyecto .NET
│   ├── Program.cs               # API endpoints
│   ├── Services/
│   │   ├── ETLService.cs       # Lógica ETL
│   │   ├── CalculoService.cs   # Lógica cálculos
│   │   └── ReporteService.cs   # Generación Excel
│   └── wwwroot/
│       ├── index.html          # Dashboard
│       ├── companias.html      # Gestión compañías
│       ├── extraccion.html     # ETL UI
│       ├── calculo.html        # Cálculo UI
│       └── reporte.html        # Reporte UI
├── SQL/
│   ├── 01_CREATE_DATABASE.sql
│   ├── 02_CREATE_TABLES.sql
│   ├── 03_CREATE_CATALOGS.sql
│   ├── 04_SP_ETL_Importar_Activos.sql
│   └── ...
├── Database/
│   └── StoredProcedures/
│       ├── sp_Calcular_RMF_Activos_Extranjeros.sql
│       └── sp_Calcular_RMF_Activos_Nacionales.sql
└── README.md                    # Este archivo
```

---

## 📚 Documentación Adicional

### Reportes de Análisis y Verificación

En `/tmp/` se encuentran los siguientes documentos generados durante el desarrollo:

1. **FLUJO_COMPLETO_ACTIFRMF.md** - Arquitectura de 3 tablas y proceso completo
2. **REPORTE_EJECUCION_DIRECTA_SP.md** - Resultados de pruebas de SPs
3. **VERIFICACION_CAMPOS_BD_EXCEL.md** - Mapeo completo de campos BD ↔ Excel
4. **RESUMEN_FINAL_CORRECCIONES.md** - Correcciones implementadas
5. **VERIFICACION_FORMULAS_EXTRANJEROS.md** - Verificación de fórmulas columna por columna

### Archivos de Referencia

- **DICCIONARIO_DATOS.md** - Diccionario completo de tablas Actif
- **RMF.md** - Marco legal LISR Art. 182 y reglas Safe Harbor
- **Propuesta reporte Calculo AF.xlsx** - Excel de referencia con ejemplos

---

## 🔐 Conexiones a Base de Datos

### Actif (Sistema Origen)

**Servidor**: dbdev.powerera.com
**Base de Datos**: actif_web_CIMA_Dev
**Usuario**: earaiza

**Connection String**:
```
Server=dbdev.powerera.com;Database=actif_web_CIMA_Dev;User Id=earaiza;Password=***;TrustServerCertificate=True;
```

---

### Actif_RMF (Sistema Destino)

**Servidor**: dbdev.powerera.com
**Base de Datos**: Actif_RMF
**Usuario**: earaiza

**Connection String**:
```
Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=***;TrustServerCertificate=True;
```

---

## 🧪 Verificación de Cálculos

### Caso de Prueba: Compañía 188, Folio 45308

**Datos del Activo**:
- **MOI**: $311.89 USD
- **Tipo**: Extranjero (ID_PAIS = 2)
- **Ruta**: 1.3.1.1 (Baja en año, July 2024)
- **Tasa_Mensual**: 0.006667 (8% anual)
- **Meses uso en ejercicio**: 7 meses

**Resultados Calculados** (✅ Verificados correctos):
```
Dep_Acum_Inicio:      $0.00
Saldo_Inicio_Año:     $311.89
Dep_Fiscal_Ejercicio: $12.48
Monto_Pendiente:      $299.41
Proporción:           $174.66
Tipo_Cambio:          18.2478
Valor_Reportable_MXN: $3,187.13  ✅ CORRECTO
```

---

## 📞 Soporte

Para reportar problemas o solicitar mejoras, contactar al equipo de desarrollo.

---

**Fecha de creación**: 2025-10-12
**Última actualización**: 2025-11-05
**Versión**: 2.0.0 - ETL optimizado con SqlBulkCopy + Queries Configurables

## 📄 Documentación Adicional

- **[ETL.md](ETL.md)** - Documentación completa del ETL (query, transformaciones, performance)
- **[RMF.md](RMF.md)** - Marco legal LISR Art. 182 y reglas Safe Harbor
- **[DICCIONARIO_DATOS.md](DICCIONARIO_DATOS.md)** - Diccionario de tablas Actif
