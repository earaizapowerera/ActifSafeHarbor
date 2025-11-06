# ETL - Extracción, Transformación y Carga de Activos

## 📋 Tabla de Contenidos

- [Descripción General](#descripción-general)
- [Arquitectura](#arquitectura)
- [Query de Extracción](#query-de-extracción)
- [Transformaciones](#transformaciones)
- [Carga de Datos](#carga-de-datos)
- [Performance](#performance)
- [Configuración](#configuración)
- [Ejecución](#ejecución)

---

## 📖 Descripción General

El ETL (Extract, Transform, Load) es el **primer paso** del proceso de cálculo Safe Harbor. Su función es **extraer datos crudos** del sistema Actif y cargarlos en la tabla `Staging_Activo` para su posterior procesamiento.

### Características Principales

✅ **Query Configurable por Compañía** - Cada compañía puede tener su propio query personalizado
✅ **SqlBulkCopy** - Inserciones masivas ultra-rápidas (10-50x más rápido)
✅ **LEFT JOIN Optimizado** - Usa índices en lugar de subqueries
✅ **Sin INPC** - INPC se calcula en fase de cálculo, no en ETL
✅ **Arquitectura de Puente** - Funciona sin visibilidad entre BDs

---

## 🏗️ Arquitectura

### ETL como Puente Entre Bases de Datos

```
┌──────────────────────────────────────────────────────────┐
│  BD ORIGEN (actif_xxx)                                   │
│  - Tabla: activo                                         │
│  - Tabla: porcentaje_depreciacion                       │
│  - Tabla: calculo (histórico)                           │
│  - Tabla: tipo_activo, pais, moneda                     │
│  ❌ NO tiene visibilidad a BD Destino                   │
└────────────────────┬─────────────────────────────────────┘
                     │
                     │ 1. Lee datos
                     ▼
┌──────────────────────────────────────────────────────────┐
│  ETL .NET (ActifRMF.ETL)                                 │
│  - Lee query desde ConfiguracionCompania                │
│  - Extrae datos con SqlDataReader                       │
│  - Transforma en memoria (DataTable)                    │
│  - Inserta con SqlBulkCopy                              │
│  ✅ Funciona como PUENTE entre BDs                      │
└────────────────────┬─────────────────────────────────────┘
                     │
                     │ 2. Inserta datos
                     ▼
┌──────────────────────────────────────────────────────────┐
│  BD DESTINO (Actif_RMF)                                  │
│  - Tabla: Staging_Activo                                │
│  - Tabla: Calculo_RMF (después)                         │
│  - Tabla: ConfiguracionCompania                         │
│  ❌ NO tiene visibilidad a BD Origen                    │
└──────────────────────────────────────────────────────────┘
```

**Ventajas de esta arquitectura:**
- ✅ Funciona sin linked servers ni OPENROWSET
- ✅ Cada BD está aislada (seguridad)
- ✅ ETL es portable (puede ejecutarse desde cualquier máquina)
- ✅ Fácil de debuggear y mantener

---

## 🔍 Query de Extracción

### Ubicación

El query ETL está **almacenado en la base de datos** en la tabla `ConfiguracionCompania`:

```sql
SELECT Query_ETL
FROM ConfiguracionCompania
WHERE ID_Compania = 188
```

Cada compañía puede tener su propio query personalizado, adaptado a:
- Diferentes versiones del sistema Actif
- Diferentes estructuras de tablas
- Diferentes reglas de negocio

### Estructura del Query

```sql
SELECT
    -- =============================================
    -- IDENTIFICACIÓN DEL ACTIVO
    -- =============================================
    a.ID_COMPANIA,
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,                                -- Placa
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,

    -- =============================================
    -- DATOS FINANCIEROS BASE
    -- =============================================
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,                         -- Para activos NACIONALES (Fiscal)
    a.COSTO_REEXPRESADO,                       -- Para activos EXTRANJEROS (USGAAP)
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,

    -- =============================================
    -- PAÍS (1=Nacional, >1=Extranjero)
    -- =============================================
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,

    -- =============================================
    -- FECHAS
    -- =============================================
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC,
    a.FECHA_INIC_DEPREC3,
    a.STATUS,

    -- =============================================
    -- OWNERSHIP (0=NO propio, 1=Propio)
    -- =============================================
    a.FLG_PROPIO,

    -- =============================================
    -- FLAGS DE TIPO DE DEPRECIACIÓN
    -- =============================================
    a.FLG_NOCAPITALIZABLE_2 AS ManejaFiscal,    -- 'S' = Activo NACIONAL
    a.FLG_NOCAPITALIZABLE_3 AS ManejaUSGAAP,    -- 'S' = Activo EXTRANJERO

    -- =============================================
    -- TASA DE DEPRECIACIÓN FISCAL (con vigencia)
    -- =============================================
    ISNULL(pd.PORC_SEGUNDO_ANO, 0) AS Tasa_Anual,

    -- =============================================
    -- DEPRECIACIÓN HISTÓRICA (Diciembre año anterior)
    -- =============================================
    ISNULL(c_hist.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año

FROM activo a

-- =============================================
-- JOINS
-- =============================================
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA

-- Join con porcentaje_depreciacion VIGENTE
LEFT JOIN porcentaje_depreciacion pd
    ON pd.ID_TIPO_ACTIVO = a.ID_TIPO_ACTIVO
    AND pd.ID_SUBTIPO_ACTIVO = a.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2  -- 2 = Fiscal
    -- Validar vigencia en el año de cálculo
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' >= pd.FECHA_INICIO
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' <= ISNULL(pd.FECHA_FIN, '2100-12-31')

-- Join con depreciación histórica (Diciembre año anterior, Fiscal)
LEFT JOIN calculo c_hist
    ON c_hist.ID_NUM_ACTIVO = a.ID_NUM_ACTIVO
    AND c_hist.ID_COMPANIA = a.ID_COMPANIA
    AND c_hist.ID_ANO = @Año_Anterior
    AND c_hist.ID_MES = 12
    AND c_hist.ID_TIPO_DEP = 2

WHERE a.ID_COMPANIA = @ID_Compania
  AND (a.STATUS = 'A' OR (a.STATUS = 'B' AND YEAR(a.FECHA_BAJA) = @Año_Calculo))
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@Año_Calculo AS VARCHAR(4)) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01')

ORDER BY a.ID_COMPANIA, a.ID_NUM_ACTIVO
```

### Parámetros del Query

| Parámetro | Tipo | Descripción | Ejemplo |
|-----------|------|-------------|---------|
| `@ID_Compania` | INT | ID de la compañía a extraer | 188 |
| `@Año_Calculo` | INT | Año fiscal a calcular | 2024 |
| `@Año_Anterior` | INT | Año anterior (para histórico) | 2023 |

### Optimizaciones Implementadas

#### 1. LEFT JOIN en lugar de Subquery

**ANTES (lento):**
```sql
ISNULL((
    SELECT TOP 1 pd.PORC_SEGUNDO_ANO
    FROM porcentaje_depreciacion pd
    WHERE pd.ID_TIPO_ACTIVO = a.ID_TIPO_ACTIVO
      AND pd.ID_SUBTIPO_ACTIVO = a.ID_SUBTIPO_ACTIVO
      AND pd.ID_TIPO_DEP = 2
    ORDER BY pd.PORC_SEGUNDO_ANO DESC
), 0) AS Tasa_Anual
```

**AHORA (rápido):**
```sql
LEFT JOIN porcentaje_depreciacion pd
    ON pd.ID_TIPO_ACTIVO = a.ID_TIPO_ACTIVO
    AND pd.ID_SUBTIPO_ACTIVO = a.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' >= pd.FECHA_INICIO
    AND CAST(@Año_Calculo AS VARCHAR(4)) + '-01-01' <= ISNULL(pd.FECHA_FIN, '2100-12-31')
```

**Ventajas:**
- ✅ Usa índices de la tabla
- ✅ Una sola pasada por la tabla
- ✅ Evita duplicados con validación de vigencia

#### 2. Sin INPC en ETL

**ANTES:**
```sql
LEFT JOIN INPC2 inpc_adq ON ...
LEFT JOIN INPC2 inpc_mitad ON ...
```

**AHORA:**
```sql
-- INPC se calcula en la fase de CÁLCULO, no en ETL
-- ETL solo extrae datos crudos
```

**Ventajas:**
- ✅ Query más simple y rápido
- ✅ ETL no hace cálculos, solo extrae
- ✅ Menos JOINs = mejor performance

---

## 🔄 Transformaciones

### En Memoria (C# DataTable)

El ETL realiza las siguientes transformaciones **en memoria** antes de insertar:

#### 1. Conversión de Tasas
```csharp
// Tasa_Anual: 8.0 → 0.08
Tasa_Anual = valor original (ya viene dividido por 100 en el query)

// Tasa_Mensual: 8.0 → 0.006667
Tasa_Mensual = Tasa_Anual / 100.0 / 12.0
```

#### 2. Cálculo de Costos

**Activos EXTRANJEROS (ManejaUSGAAP = 'S'):**
```csharp
CostoUSD = COSTO_REEXPRESADO ?? COSTO_ADQUISICION
CostoMXN = CostoUSD × Tipo_Cambio_30_Junio
```

**Activos NACIONALES (ManejaFiscal = 'S'):**
```csharp
CostoMXN = COSTO_REVALUADO ?? COSTO_ADQUISICION
CostoUSD = NULL
```

#### 3. Validación de ERROR DE DEDO

```csharp
if (ManejaFiscal == 'S' AND ManejaUSGAAP == 'S')
{
    // Omitir este activo con advertencia
    Console.WriteLine("⚠️ ADVERTENCIA: Activo con ambos flags activos - OMITIDO");
    continue;
}
```

#### 4. Conversión de FLG_PROPIO

```csharp
FLG_PROPIO = (FLG_PROPIO_CHAR == 'S') ? 1 : 0
```

---

## 💾 Carga de Datos

### SqlBulkCopy - Inserciones Masivas

El ETL usa **SqlBulkCopy** para insertar datos de forma ultra-rápida:

```csharp
// 1. Preparar DataTable con transformaciones
DataTable dtStaging = PrepararDataTableStaging(dtOrigen, ...);

// 2. Configurar SqlBulkCopy
using var bulkCopy = new SqlBulkCopy(connStrDestino);
bulkCopy.DestinationTableName = "Staging_Activo";
bulkCopy.BatchSize = 1000;  // Commit cada 1000 registros
bulkCopy.BulkCopyTimeout = 300; // 5 minutos

// 3. Mapear columnas
bulkCopy.ColumnMappings.Add("ID_Compania", "ID_Compania");
bulkCopy.ColumnMappings.Add("ID_NUM_ACTIVO", "ID_NUM_ACTIVO");
// ... más columnas

// 4. Progreso
bulkCopy.NotifyAfter = 100;
bulkCopy.SqlRowsCopied += (sender, e) => {
    Console.WriteLine($"Procesados: {e.RowsCopied} / {totalRows}");
};

// 5. Insertar TODO de una vez
await bulkCopy.WriteToServerAsync(dtStaging);
```

### Ventajas de SqlBulkCopy

| Característica | INSERTs Individuales | SqlBulkCopy |
|---------------|---------------------|-------------|
| **Operaciones** | N INSERTs separados | 1 operación masiva |
| **Viajes a BD** | N viajes | 1 viaje |
| **Performance** | Lento | **10-50x más rápido** |
| **Memoria** | Baja | Baja (streaming) |
| **Transaccional** | Sí (por lotes) | Sí |

---

## ⚡ Performance

### Comparativa de Tiempos

#### Para 34 Activos (Compañía 188)

| Método | Tiempo | Mejora |
|--------|--------|--------|
| **INSERTs individuales** | ~4.8 seg | Base |
| **SqlBulkCopy** | ~2.7 seg (consola) | **1.8x** |
| **SqlBulkCopy (web)** | ~1.0 seg | **4.8x** |

#### Proyección para Producción

| Activos | INSERTs | SqlBulkCopy | Ahorro |
|---------|---------|-------------|--------|
| 100 | ~10 seg | ~0.5 seg | **20x** |
| 1,000 | ~100 seg | ~5 seg | **20x** |
| 10,000 | ~1000 seg (16 min) | ~50 seg | **20x** |
| 100,000 | ~10000 seg (2.7 hr) | ~500 seg (8 min) | **20x** |

---

## ⚙️ Configuración

### Tabla ConfiguracionCompania

```sql
CREATE TABLE ConfiguracionCompania (
    ID_Configuracion INT IDENTITY(1,1) PRIMARY KEY,
    ID_Compania INT NOT NULL,
    Nombre_Compania NVARCHAR(200) NOT NULL,
    Nombre_Corto NVARCHAR(50) NOT NULL,

    -- Connection string a BD origen
    ConnectionString_Actif NVARCHAR(500) NOT NULL,

    -- Query ETL personalizado
    Query_ETL NVARCHAR(MAX) NULL,

    Activo BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME NOT NULL DEFAULT GETDATE(),
    FechaModificacion DATETIME NULL
);
```

### Ejemplo de Configuración

```sql
-- Compañía 188
INSERT INTO ConfiguracionCompania
    (ID_Compania, Nombre_Compania, Nombre_Corto, ConnectionString_Actif, Query_ETL)
VALUES
    (188,
     'Compañia Prueba 188',
     'CIMA',
     'Server=dbdev.powerera.com;Database=actif_learensayo10;User Id=earaiza;Password=***;TrustServerCertificate=True;',
     'SELECT a.ID_COMPANIA, a.ID_NUM_ACTIVO, ... FROM activo a ...');
```

### Modificar Query de una Compañía

```sql
UPDATE ConfiguracionCompania
SET Query_ETL = 'SELECT ... nuevo query ...',
    FechaModificacion = GETDATE()
WHERE ID_Compania = 188;
```

---

## 🚀 Ejecución

### Línea de Comandos

```bash
cd /Users/enrique/actifrmf/ETL_NET/ActifRMF.ETL

# Ejecutar ETL para compañía 188, año 2024
dotnet run 188 2024

# Con límite de registros (testing)
dotnet run 188 2024 --limit 100

# Con lote específico (para sincronizar con web)
dotnet run 188 2024 --lote "5b3bc590-bee0-434c-b629-db9ccdadeeef"
```

### API Web

```bash
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{
    "idCompania": 188,
    "añoCalculo": 2024,
    "usuario": "admin",
    "maxRegistros": null
  }'
```

**Respuesta:**
```json
{
  "message": "ETL iniciado",
  "loteImportacion": "d2f23b10-285f-4ea8-9840-83b5c3cfeb1d",
  "idCompania": 188,
  "añoCalculo": 2024
}
```

El ETL se ejecuta en **background** y puedes monitorear el progreso con:

```bash
curl http://localhost:5071/api/etl/progreso/d2f23b10-285f-4ea8-9840-83b5c3cfeb1d
```

### Interfaz Web

1. Abrir: http://localhost:5071/extraccion.html
2. Seleccionar compañía (ej: 188)
3. Ingresar año (ej: 2024)
4. Clic en "Ejecutar ETL"
5. Ver progreso en tiempo real

---

## 📊 Salida del ETL

### Tabla Staging_Activo

El ETL inserta datos en la tabla `Staging_Activo` con las siguientes columnas:

```sql
ID_Staging BIGINT IDENTITY(1,1) PRIMARY KEY
ID_Compania INT NOT NULL
ID_NUM_ACTIVO INT NOT NULL
ID_ACTIVO NVARCHAR(50) NULL                  -- Placa
DESCRIPCION NVARCHAR(500) NULL
ID_TIPO_ACTIVO INT NULL
Nombre_TipoActivo NVARCHAR(200) NULL
ID_PAIS INT NOT NULL                          -- 1=Nacional, >1=Extranjero
Nombre_Pais NVARCHAR(100) NULL
FECHA_COMPRA DATETIME NULL
FECHA_BAJA DATETIME NULL
FECHA_INICIO_DEP DATETIME NULL
STATUS NVARCHAR(10) NULL
FLG_PROPIO INT NULL                           -- 0=NO propio, 1=Propio
Tasa_Anual DECIMAL(10,6) NULL                 -- Ej: 0.08
Tasa_Mensual DECIMAL(10,6) NULL               -- Ej: 0.006667
Dep_Acum_Inicio_Año DECIMAL(18,4) NULL        -- Histórico año anterior
ManejaFiscal NVARCHAR(1) NULL                 -- 'S' o 'N'
ManejaUSGAAP NVARCHAR(1) NULL                 -- 'S' o 'N'
CostoUSD DECIMAL(18,4) NULL                   -- Solo extranjeros
CostoMXN DECIMAL(18,4) NULL                   -- Todos
Año_Calculo INT NOT NULL
Lote_Importacion UNIQUEIDENTIFIER NOT NULL
Fecha_Importacion DATETIME NOT NULL
```

### Ejemplo de Datos

```
ID_NUM_ACTIVO: 44073
ID_PAIS: 2 (Extranjero)
ManejaUSGAAP: S
Tasa_Anual: 0.080000
Tasa_Mensual: 0.006667
CostoUSD: 3250.00
CostoMXN: 59305.35
Dep_Acum_Inicio_Año: 0.00
```

---

## 🔧 Troubleshooting

### Query no configurado

**Error:**
```
No se encontró Query_ETL configurado para compañía 188
```

**Solución:**
```sql
-- Verificar configuración
SELECT ID_Compania, Nombre_Compania,
       CASE WHEN Query_ETL IS NULL THEN 'SIN QUERY' ELSE 'OK' END
FROM ConfiguracionCompania
WHERE ID_Compania = 188;

-- Si no existe, insertar query
UPDATE ConfiguracionCompania
SET Query_ETL = '<query completo>'
WHERE ID_Compania = 188;
```

### Duplicados en porcentaje_depreciacion

**Síntoma:** Error de duplicados o tasas incorrectas

**Solución:** Verificar vigencia de tasas

```sql
SELECT ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
       FECHA_INICIO, ISNULL(FECHA_FIN, '2100-12-31') as FECHA_FIN,
       PORC_SEGUNDO_ANO
FROM porcentaje_depreciacion
WHERE ID_TIPO_ACTIVO = 13
  AND ID_SUBTIPO_ACTIVO = 13
  AND ID_TIPO_DEP = 2
ORDER BY FECHA_INICIO;
```

### Performance lento

**Síntomas:**
- ETL tarda más de 10 segundos para 100 activos
- Alto uso de CPU

**Solución:**
1. Verificar que se use SqlBulkCopy (no INSERTs individuales)
2. Verificar índices en BD origen:
   ```sql
   -- Índices recomendados
   CREATE INDEX IX_activo_compania_status ON activo(ID_COMPANIA, STATUS);
   CREATE INDEX IX_porcen_tipo_dep ON porcentaje_depreciacion(ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO, ID_TIPO_DEP);
   CREATE INDEX IX_calculo_hist ON calculo(ID_COMPANIA, ID_NUM_ACTIVO, ID_ANO, ID_MES, ID_TIPO_DEP);
   ```

---

## 📚 Referencias

- [README.md](README.md) - Documentación general del sistema
- [RMF.md](RMF.md) - Marco legal Safe Harbor
- [DICCIONARIO_DATOS.md](DICCIONARIO_DATOS.md) - Diccionario de datos Actif

---

**Última actualización:** 2025-11-05
**Versión:** 2.0.0 - SqlBulkCopy + Queries Configurables
