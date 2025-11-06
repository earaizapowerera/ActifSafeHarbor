# Diccionario de Datos - Staging_Activo

**Base de datos:** Actif_RMF
**Tabla:** Staging_Activo
**Propósito:** Tabla de staging para almacenar activos importados desde las bases de datos fuente de cada compañía antes de procesarlos en los cálculos de Safe Harbor.

---

## Resumen de Uso

| Estado | Cantidad | Descripción |
|--------|----------|-------------|
| ✓ USADA | 18 | Columnas utilizadas activamente en los SPs de cálculo |
| ⚠️ METADATA | 3 | Columnas de control/log (no en cálculos) |
| ✗ NO USADA | 12 | Columnas que NO se utilizan y podrían eliminarse |
| **TOTAL** | **33** | |

---

## Columnas de Control (Primary Key y Metadata)

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **ID_Staging** | bigint | NO | ✓ | IDENTITY | Primary Key autoincrementable |
| **Año_Calculo** | int | NO | ✓ | Parámetro | Año fiscal para el cálculo (ej: 2025) |
| **Fecha_Importacion** | datetime | NO | ⚠️ | GETDATE() | Fecha/hora de importación ETL (solo log) |
| **Lote_Importacion** | uniqueidentifier | NO | ⚠️ | NEWID() | GUID del lote de importación ETL (solo log) |

---

## Identificadores del Activo

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **ID_Compania** | int | NO | ✓ | Parámetro | ID de la compañía (1=ABL, 2=AL) |
| **ID_NUM_ACTIVO** | int | NO | ✓ | activo.ID_NUM_ACTIVO | ID numérico único del activo en la BD origen |
| **ID_ACTIVO** | nvarchar(50) | YES | ✓ | activo.ID_ACTIVO | Placa o código alfanumérico del activo |
| **DESCRIPCION** | nvarchar(500) | YES | ✓ | activo.DESCRIPCION | Descripción del activo |
| **ID_TIPO_ACTIVO** | int | YES | ✗ | activo.ID_TIPO_ACTIVO | ID del tipo de activo (Edificio, Maquinaria, etc.) - **NO SE USA** |
| **ID_SUBTIPO_ACTIVO** | int | YES | ✗ | activo.ID_SUBTIPO_ACTIVO | ID del subtipo de activo - **NO SE USA** |
| **Nombre_TipoActivo** | nvarchar(200) | YES | ✗ | tipo_activo.NOMBRE | Nombre descriptivo del tipo - **NO SE USA** |

---

## Moneda y País

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **ID_MONEDA** | int | YES | ✗ | activo.ID_MONEDA | ID de la moneda - **NO SE USA** |
| **Nombre_Moneda** | nvarchar(50) | YES | ✗ | moneda.NOMBRE | Nombre de la moneda - **NO SE USA** |
| **ID_PAIS** | int | NO | ✓ | activo.ID_PAIS | **CRÍTICO:** ID del país (1=México, 2=USA, etc.) - Usado para separar Nacionales/Extranjeros |
| **Nombre_Pais** | nvarchar(100) | YES | ✗ | pais.NOMBRE | Nombre del país - **NO SE USA** |

**Uso de ID_PAIS:**
- `ID_PAIS = 1` (México): Procesa en SP Nacionales con CostoMXN
- `ID_PAIS > 1` (Extranjeros): Procesa en SP Extranjeros con CostoUSD

---

## Fechas del Activo

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **FECHA_COMPRA** | datetime | YES | ✓ | activo.FECHA_COMPRA | **Fecha de adquisición** - Usada para: <br>1. INPC de adquisición (YEAR/MONTH)<br>2. Cálculo de meses en extranjeros |
| **FECHA_BAJA** | datetime | YES | ✓ | activo.FECHA_BAJA | Fecha de baja del activo - Para calcular meses de uso en el ejercicio |
| **FECHA_INICIO_DEP** | datetime | YES | ✓ | activo.FECHA_INIC_DEPREC | **Fecha inicio depreciación FISCAL** - Usada en SP Nacionales para calcular `Meses_Uso_Inicio_Ejercicio` |
| **FECHA_INIC_DEPREC_3** | date | YES | ✓ | activo.FECHA_INIC_DEPREC_3 | **Fecha inicio depreciación USGAAP** - Usada en SP Extranjeros y fn_CalcularDepFiscal_Tipo2 |

**Importante:**
- **FECHA_COMPRA**: Se usa para INPC (año/mes de adquisición) y para cálculo de meses en extranjeros
- **FECHA_INICIO_DEP**: Se usa para calcular meses de depreciación acumulada en nacionales (NO para INPC)
- **FECHA_INIC_DEPREC_3**: Se usa para calcular meses de depreciación acumulada en extranjeros tipo 2

---

## Status y Ownership

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **STATUS** | nvarchar(10) | YES | ✗ | activo.STATUS | Estado del activo (A=Activo, B=Baja) - **FILTRADO EN ETL, NO SE USA EN SPs** |
| **FLG_PROPIO** | int | YES | ✗ | activo.FLG_PROPIO | 0=No propio, 1=Propio - **FILTRADO EN ETL (=0), NO SE USA EN SPs** |

**Nota:** Estos campos se filtran durante el ETL pero no se usan en los stored procedures de cálculo.

---

## Tasas de Depreciación

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **Tasa_Anual** | decimal(10,6) | YES | ✓ | porcentaje_depreciacion.PORCENTAJE / 100 | **Tasa de depreciación anual fiscal** como decimal (ej: 10.00 = 10%)<br>**NOTA:** Ahora se prefiere usar esta con mayor precisión |
| **Tasa_Mensual** | decimal(18,6) | YES | ⚠️ | Tasa_Anual / 12 | Tasa mensual precalculada - **DEPRECATED: Ahora se calcula desde Tasa_Anual** |

**Evolución:**
- Antes: Se usaba `Tasa_Mensual` directamente (6 decimales) → causaba errores de precisión
- Ahora: Se usa `(Tasa_Anual / 12 / 100)` con 10 decimales para mayor precisión
- La columna `Tasa_Mensual` aún existe pero ya no se usa activamente

---

## Depreciación Acumulada

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **Dep_Acum_Inicio_Año** | decimal(18,4) | YES | ✓ | calculo.ACUMULADO_HISTORICA<br>(Dic año anterior) | **Depreciación acumulada al 31/Dic del año anterior**<br><br>**NACIONALES:** Se usa el valor histórico (NUNCA se calcula)<br>**EXTRANJEROS:** Si es NULL o 0, se calcula con fn_CalcularDepFiscal_Tipo2 |

**Importante para Extranjeros:**
- Si `Dep_Acum_Inicio_Año` tiene valor → se usa directamente (activos con cálculo fiscal histórico)
- Si `Dep_Acum_Inicio_Año` es NULL o 0 → se marca `Usa_Calculo_Tipo2=1` y se calcula usando FECHA_INIC_DEPREC_3

---

## INPC (Inflación)

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **INPC_Adquisicion** | decimal(18,6) | YES | ✓ | INPC2.Indice<br>(WHERE Anio=YEAR(FECHA_COMPRA)<br>AND Mes=MONTH(FECHA_COMPRA)<br>AND Id_Grupo_Simulacion=8) | **INPC del mes de adquisición** (solo mexicanos)<br>Usado en SP Nacionales para actualizar saldos |
| **INPC_Mitad_Ejercicio** | decimal(18,6) | YES | ✓ | INPC2.Indice<br>(WHERE Anio=@Año_Calculo<br>AND Mes=6<br>AND Id_Grupo_Simulacion=8) | **INPC de junio del año de cálculo**<br>Usado para calcular factor de actualización |

**Importante:**
- Solo aplica para activos MEXICANOS (ID_PAIS=1)
- Se obtiene desde tabla `INPC2` de la base de datos origen durante el ETL
- Grupo de Simulación = 8 (Safe Harbor)

---

## Costos y Valores

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **Costo_Fiscal** | decimal(18,4) | YES | ✗ | activo.COSTO_FISCAL | Costo fiscal del activo - **NO SE USA** |
| **COSTO_REVALUADO** | decimal(18,4) | YES | ✗ | activo.COSTO_REVALUADO | Costo revaluado - **NO SE USA (antes sí, ver v4.4)** |
| **COSTO_REEXPRESADO** | decimal(18,4) | YES | ✗ | activo.COSTO_REEXPRESADO | Costo reexpresado - **NO SE USA** |
| **CostoUSD** | decimal(18,4) | YES | ✓ | *Calculado en .NET* | **MOI para activos extranjeros** (ID_PAIS > 1)<br>Usado en SP Extranjeros |
| **CostoMXN** | decimal(18,4) | YES | ✓ | *Calculado en .NET* | **MOI para activos nacionales** (ID_PAIS = 1)<br>Usado en SP Nacionales |

**Cálculo de Costos (en ETL .NET):**
```csharp
// Extranjeros (ID_PAIS > 1)
CostoUSD = COSTO_REVALUADO (ya está en USD)

// Nacionales (ID_PAIS = 1)
CostoMXN = COSTO_REVALUADO (ya está en MXN)
```

---

## Flags de Clasificación

| Columna | Tipo | Nullable | Uso | Origen | Descripción |
|---------|------|----------|-----|--------|-------------|
| **ManejaFiscal** | nvarchar(1) | YES | ✓ | *Calculado en .NET* | **'S' = Activo nacional (mexicano) con depreciación fiscal**<br>Usado en SP Nacionales como filtro principal:<br>`WHERE ManejaFiscal = 'S'` |
| **ManejaUSGAAP** | nvarchar(1) | YES | ✗? | *Calculado en .NET* | **'S' = Activo con depreciación USGAAP**<br>Documentado en SP Extranjeros pero **NO SE USA como filtro** |

**Lógica de Clasificación:**
```sql
-- SP Nacionales
WHERE ManejaFiscal = 'S'      -- Mexicanos con fiscal
  AND CostoMXN > 0
  AND Tasa_Anual > 0

-- SP Extranjeros
WHERE ID_PAIS > 1              -- Solo extranjeros (no importa ManejaUSGAAP)
  AND CostoUSD > 0
```

---

## Columnas que DEBEN ELIMINARSE

Las siguientes columnas **NO se usan** en ningún stored procedure de cálculo y pueden eliminarse para simplificar el esquema:

### 1. Identificadores no usados (3 columnas)
- `ID_TIPO_ACTIVO` - No se usa en cálculos
- `ID_SUBTIPO_ACTIVO` - No se usa en cálculos
- `Nombre_TipoActivo` - No se usa en cálculos

### 2. Moneda no usada (2 columnas)
- `ID_MONEDA` - No se usa (tenemos CostoUSD/CostoMXN)
- `Nombre_Moneda` - No se usa

### 3. País no usado (1 columna)
- `Nombre_Pais` - No se usa (solo necesitamos ID_PAIS)

### 4. Status/Ownership no usados (2 columnas)
- `STATUS` - Filtrado en ETL, no usado en SPs
- `FLG_PROPIO` - Filtrado en ETL (solo FLG_PROPIO=0), no usado en SPs

### 5. Costos legacy no usados (3 columnas)
- `Costo_Fiscal` - No se usa
- `COSTO_REVALUADO` - No se usa (reemplazado por CostoUSD/CostoMXN)
- `COSTO_REEXPRESADO` - No se usa

### 6. Tasa mensual deprecated (1 columna)
- `Tasa_Mensual` - Ya no se usa (se calcula desde Tasa_Anual)

**Total a eliminar: 12 columnas**

---

## Columnas que DEBEN MANTENERSE

### Columnas críticas para cálculos (18 columnas)

**Identificación y Control:**
- ID_Staging (PK)
- ID_Compania
- ID_NUM_ACTIVO
- ID_ACTIVO
- DESCRIPCION
- Año_Calculo

**Fechas:**
- FECHA_COMPRA (para INPC y meses)
- FECHA_BAJA (para meses de uso)
- FECHA_INICIO_DEP (para meses depreciación nacionales)
- FECHA_INIC_DEPREC_3 (para meses depreciación extranjeros)

**Clasificación:**
- ID_PAIS (México vs Extranjeros)
- ManejaFiscal (filtro nacionales)

**Valores y Tasas:**
- Tasa_Anual
- Dep_Acum_Inicio_Año
- CostoUSD (MOI extranjeros)
- CostoMXN (MOI nacionales)

**INPC:**
- INPC_Adquisicion
- INPC_Mitad_Ejercicio

### Columnas de metadata/log (3 columnas)
- Fecha_Importacion
- Lote_Importacion
- ManejaUSGAAP (por si se necesita después)

**Total a mantener: 21 columnas**

---

## Propuesta de Limpieza

### Paso 1: Verificar que no se usen en reportes
Antes de eliminar, verificar que las columnas marcadas como "NO USADA" tampoco se usen en:
- Vistas
- Reportes de Power BI / Crystal Reports
- Interfaz web (JavaScript)

### Paso 2: Script de eliminación
```sql
USE Actif_RMF;
GO

-- Eliminar columnas no usadas
ALTER TABLE Staging_Activo DROP COLUMN ID_TIPO_ACTIVO;
ALTER TABLE Staging_Activo DROP COLUMN ID_SUBTIPO_ACTIVO;
ALTER TABLE Staging_Activo DROP COLUMN Nombre_TipoActivo;
ALTER TABLE Staging_Activo DROP COLUMN ID_MONEDA;
ALTER TABLE Staging_Activo DROP COLUMN Nombre_Moneda;
ALTER TABLE Staging_Activo DROP COLUMN Nombre_Pais;
ALTER TABLE Staging_Activo DROP COLUMN STATUS;
ALTER TABLE Staging_Activo DROP COLUMN FLG_PROPIO;
ALTER TABLE Staging_Activo DROP COLUMN Costo_Fiscal;
ALTER TABLE Staging_Activo DROP COLUMN COSTO_REVALUADO;
ALTER TABLE Staging_Activo DROP COLUMN COSTO_REEXPRESADO;
ALTER TABLE Staging_Activo DROP COLUMN Tasa_Mensual;

PRINT 'Columnas no usadas eliminadas de Staging_Activo';
GO
```

### Paso 3: Actualizar ETL
Eliminar las columnas del script de inserción en `sp_ETL_Importar_Activos`.

---

## Flujo de Datos

```
┌─────────────────────────────────────────────────────────────┐
│                    BASE DE DATOS ORIGEN                      │
│  (activo, tipo_activo, pais, moneda, porcentaje_depreciacion,│
│   calculo, INPC2)                                            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ ETL: sp_ETL_Importar_Activos
                     │ (.NET también calcula CostoUSD/CostoMXN, ManejaFiscal)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   STAGING_ACTIVO (21 cols)                   │
│                                                              │
│  Nacionales (ManejaFiscal='S'):                             │
│    - CostoMXN, FECHA_INICIO_DEP, Dep_Acum_Inicio_Año       │
│    - INPC_Adquisicion, INPC_Mitad_Ejercicio                │
│                                                              │
│  Extranjeros (ID_PAIS > 1):                                 │
│    - CostoUSD, FECHA_INIC_DEPREC_3, Dep_Acum_Inicio_Año    │
│    - fn_CalcularDepFiscal_Tipo2 si no hay histórico        │
└──────────┬────────────────────────────────┬─────────────────┘
           │                                │
           │                                │
           ▼                                ▼
┌─────────────────────┐      ┌─────────────────────────────┐
│ SP Nacionales       │      │ SP Extranjeros              │
│ (ManejaFiscal='S')  │      │ (ID_PAIS > 1)               │
│                     │      │                             │
│ - CostoMXN          │      │ - CostoUSD                  │
│ - FECHA_INICIO_DEP  │      │ - FECHA_INIC_DEPREC_3       │
│ - INPC actualización│      │ - Tipo de cambio            │
│ - Dep histórico     │      │ - fn_Tipo2 si necesario     │
└─────────┬───────────┘      └──────────┬──────────────────┘
          │                             │
          │                             │
          └──────────┬──────────────────┘
                     ▼
          ┌──────────────────────┐
          │   CALCULO_RMF        │
          │  (Resultados finales)│
          └──────────────────────┘
```

---

## Versión del Documento
- **Creado:** 2025-11-05
- **Versión:** 1.0
- **Autor:** Claude Code
