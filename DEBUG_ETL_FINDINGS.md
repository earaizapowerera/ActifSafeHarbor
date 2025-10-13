# Hallazgos Técnicos: Debugging ETL ActifRMF

**Fecha:** 13 de Octubre de 2025
**Sesión de Debugging:** Investigación error "Invalid column name 'COSTO_REVALUADO'"

---

## 🎯 Resumen Ejecutivo

Durante esta sesión de debugging se identificó la causa raíz del error `"Invalid column name 'COSTO_REVALUADO'"` que impedía la ejecución del proceso ETL.

**Problema:** La tabla destino `Staging_Activo` en la base de datos `Actif_RMF` no contenía la columna `COSTO_REVALUADO` que el código intentaba insertar.

**Solución Pendiente:** Agregar la columna `COSTO_REVALUADO DECIMAL(18, 2) NULL` a la tabla `dbo.Staging_Activo` en la base de datos `Actif_RMF`.

---

## 🔍 Proceso de Investigación

### 1. Análisis Inicial del Error

**Error reportado:**
```
❌ ERROR en ETL: Invalid column name 'COSTO_REVALUADO'.
```

**Primera hipótesis (incorrecta):** El error ocurría al leer desde la base de datos origen.

### 2. Adición de Debug Output

Se agregaron dos secciones de debug en `ETLService.cs` para visualizar:

#### Debug 1: Query con Sustituciones (Líneas 197-201)
```csharp
// 🔍 DEBUG: Mostrar query con sustituciones ANTES de ejecutar
Console.WriteLine("\n🔍 DEBUG - Query a ejecutar:");
Console.WriteLine("================================================================================");
Console.WriteLine(queryFinal);
Console.WriteLine("================================================================================\n");
```

**Propósito:** Ver el query SQL exacto que se ejecuta después de reemplazar los parámetros.

#### Debug 2: Columnas del DataReader (Líneas 237-244)
```csharp
// 🔍 DEBUG: Mostrar columnas del DataReader
Console.WriteLine("\n🔍 DEBUG - Columnas en el DataReader:");
Console.WriteLine("================================================================================");
for (int i = 0; i < readerOrigen.FieldCount; i++)
{
    Console.WriteLine($"  [{i}] {readerOrigen.GetName(i)}");
}
Console.WriteLine("================================================================================\n");
```

**Propósito:** Ver exactamente qué columnas regresa SQL Server desde la base origen.

### 3. Ejecución de Pruebas

Se ejecutó el ETL con el siguiente request:
```json
{
  "idCompania": 188,
  "añoCalculo": 2024
}
```

**Resultado del Debug 1 - Query Final:**
```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,        ← COLUMNA PRESENTE EN EL SELECT
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    ...
WHERE a.ID_COMPANIA = 188
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(2024 AS VARCHAR) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(2024 AS VARCHAR) + '-01-01')
```

**Resultado del Debug 2 - Columnas del DataReader:**
```
🔍 DEBUG - Columnas en el DataReader:
================================================================================
  [0] ID_NUM_ACTIVO
  [1] ID_ACTIVO
  [2] ID_TIPO_ACTIVO
  [3] ID_SUBTIPO_ACTIVO
  [4] Nombre_TipoActivo
  [5] DESCRIPCION
  [6] COSTO_ADQUISICION
  [7] COSTO_REVALUADO       ← COLUMNA PRESENTE EN EL DATAREADER
  [8] ID_MONEDA
  [9] Nombre_Moneda
  [10] ID_PAIS
  [11] Nombre_Pais
  [12] FECHA_COMPRA
  [13] FECHA_BAJA
  [14] FECHA_INICIO_DEP
  [15] STATUS
  [16] FLG_PROPIO
  [17] Tasa_Anual
  [18] Tasa_Mensual
  [19] Dep_Acum_Inicio_Año
================================================================================
```

**Error Final:**
```
❌ ERROR en ETL: Invalid column name 'COSTO_REVALUADO'.
```

### 4. Conclusión Crítica

**HALLAZGO CLAVE:** La columna `COSTO_REVALUADO` **SÍ EXISTE** en:
- ✅ El query SQL
- ✅ El DataReader (datos de origen)
- ❌ **NO EXISTE** en la tabla destino `Staging_Activo`

El error **NO** ocurre al leer desde la base origen, sino al **insertar en la base destino**.

---

## 📊 Esquema de la Base de Datos Origen

### Query de Extracción ETL (Compañía 188)

```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC AS FECHA_INICIO_DEP,
    a.STATUS,
    CAST(CASE WHEN a.FLG_PROPIO = 'P' THEN 1 ELSE 0 END AS INT) AS FLG_PROPIO,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR)
         ELSE 0
    END AS Tasa_Anual,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR / 12.0)
         ELSE 0
    END AS Tasa_Mensual,
    ISNULL(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año
FROM activo a
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA
INNER JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_COMPANIA = @ID_COMPANIA
    AND c.ID_ANO = @AÑO_ANTERIOR
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
WHERE a.ID_COMPANIA = @ID_COMPANIA
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@AÑO_CALCULO AS VARCHAR) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@AÑO_CALCULO AS VARCHAR) + '-01-01')
```

**Parámetros:**
- `@ID_COMPANIA`: ID de la compañía (ej: 188)
- `@AÑO_CALCULO`: Año del cálculo (ej: 2024)
- `@AÑO_ANTERIOR`: Año anterior al cálculo (ej: 2023)

**Notas Importantes:**
1. El query utiliza `a.COSTO_REVALUADO` sin alias para evitar problemas de nombres
2. Extrae 34,898 registros para la compañía 188 en el año 2024
3. El query ejecuta correctamente y regresa todas las columnas esperadas

---

## 🏗️ Esquema de la Base de Datos Destino

### Tabla: dbo.Staging_Activo

**Ubicación:** `Server=dbdev.powerera.com;Database=Actif_RMF`

#### Schema Actual (CON ERROR)

La tabla actualmente NO tiene la columna `COSTO_REVALUADO`.

#### Schema Requerido (CORRECCIÓN NECESARIA)

```sql
CREATE TABLE dbo.Staging_Activo (
    -- Identity / Keys
    ID_Staging BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Metadata de Control
    ID_Compania INT NOT NULL,
    Lote_Importacion UNIQUEIDENTIFIER NOT NULL,
    Año_Calculo INT NOT NULL,
    Fecha_Importacion DATETIME DEFAULT GETDATE(),

    -- Datos del Activo
    ID_NUM_ACTIVO INT NOT NULL,
    ID_ACTIVO NVARCHAR(50),
    ID_TIPO_ACTIVO INT NOT NULL,
    ID_SUBTIPO_ACTIVO INT NOT NULL,
    Nombre_TipoActivo NVARCHAR(100),
    DESCRIPCION NVARCHAR(255),

    -- ⚠️ COLUMNAS FALTANTES - AGREGAR:
    COSTO_ADQUISICION DECIMAL(18, 2) NULL,
    COSTO_REVALUADO DECIMAL(18, 2) NULL,        -- ⭐ ESTA COLUMNA FALTA

    -- Moneda y País
    ID_MONEDA INT NULL,
    Nombre_Moneda NVARCHAR(50),
    ID_PAIS INT NOT NULL,
    Nombre_Pais NVARCHAR(100),

    -- Fechas
    FECHA_COMPRA DATE NULL,
    FECHA_BAJA DATE NULL,
    FECHA_INICIO_DEP DATE NULL,

    -- Status y Flags
    STATUS NVARCHAR(10),
    FLG_PROPIO INT NULL,

    -- Tasas de Depreciación
    Tasa_Anual DECIMAL(10, 6) NULL,
    Tasa_Mensual DECIMAL(10, 6) NULL,
    Dep_Acum_Inicio_Año DECIMAL(18, 2) NULL
);

-- Índices recomendados
CREATE INDEX IX_Staging_Activo_Compania_Lote
    ON dbo.Staging_Activo(ID_Compania, Lote_Importacion);

CREATE INDEX IX_Staging_Activo_Activo
    ON dbo.Staging_Activo(ID_NUM_ACTIVO);
```

### Script de Corrección (EJECUTAR EN dbdev.powerera.com)

```sql
USE Actif_RMF;
GO

-- Verificar si la columna ya existe
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo'
    AND TABLE_NAME = 'Staging_Activo'
    AND COLUMN_NAME = 'COSTO_REVALUADO'
)
BEGIN
    -- Agregar la columna faltante
    ALTER TABLE dbo.Staging_Activo
    ADD COSTO_REVALUADO DECIMAL(18, 2) NULL;

    PRINT '✅ Column COSTO_REVALUADO added successfully';
END
ELSE
BEGIN
    PRINT 'ℹ️ Column COSTO_REVALUADO already exists';
END
GO

-- Verificar el resultado
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
  AND TABLE_NAME = 'Staging_Activo'
ORDER BY ORDINAL_POSITION;
GO
```

---

## 💻 Código de Inserción (ETLService.cs)

### Ubicación: `/Users/enrique/ActifRMF/ActifRMF/Services/ETLService.cs`

**Líneas 252-277:** INSERT Statement

```csharp
var sqlInsert = @"
    INSERT INTO Actif_RMF.dbo.Staging_Activo
        (ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
         Nombre_TipoActivo, DESCRIPCION, COSTO_ADQUISICION, COSTO_REVALUADO, ID_MONEDA, Nombre_Moneda,
         ID_PAIS, Nombre_Pais, FECHA_COMPRA, FECHA_BAJA, FECHA_INICIO_DEP, STATUS,
         FLG_PROPIO, Tasa_Anual, Tasa_Mensual, Dep_Acum_Inicio_Año,
         Año_Calculo, Lote_Importacion)
    VALUES
        (@IdCompania, @IdNumActivo, @IdActivo, @IdTipoActivo, @IdSubtipoActivo,
         @NombreTipoActivo, @Descripcion, @CostoAdquisicion, @CostoRevaluado, @IdMoneda, @NombreMoneda,
         @IdPais, @NombrePais, @FechaCompra, @FechaBaja, @FechaInicioDep, @Status,
         @FlgPropio, @TasaAnual, @TasaMensual, @DepAcumInicioAño,
         @AñoCalculo, @LoteImportacion)";

using var cmdInsert = new SqlCommand(sqlInsert, connRMF);
cmdInsert.Parameters.AddWithValue("@IdCompania", idCompania);
cmdInsert.Parameters.AddWithValue("@IdNumActivo", readerOrigen["ID_NUM_ACTIVO"]);
cmdInsert.Parameters.AddWithValue("@IdActivo", readerOrigen["ID_ACTIVO"] ?? DBNull.Value);
cmdInsert.Parameters.AddWithValue("@IdTipoActivo", readerOrigen["ID_TIPO_ACTIVO"]);
cmdInsert.Parameters.AddWithValue("@IdSubtipoActivo", readerOrigen["ID_SUBTIPO_ACTIVO"]);
cmdInsert.Parameters.AddWithValue("@NombreTipoActivo", readerOrigen["Nombre_TipoActivo"] ?? DBNull.Value);
cmdInsert.Parameters.AddWithValue("@Descripcion", readerOrigen["DESCRIPCION"] ?? DBNull.Value);
cmdInsert.Parameters.AddWithValue("@CostoAdquisicion", readerOrigen["COSTO_ADQUISICION"]);

// Read COSTO_REVALUADO directly (no alias)
cmdInsert.Parameters.AddWithValue("@CostoRevaluado", readerOrigen["COSTO_REVALUADO"] ?? DBNull.Value);
// ⬆️ Esta línea intenta leer COSTO_REVALUADO del DataReader (FUNCIONA)
// ⬇️ El error ocurre al intentar insertar en Staging_Activo (FALLA)

cmdInsert.Parameters.AddWithValue("@IdMoneda", readerOrigen["ID_MONEDA"] ?? DBNull.Value);
// ... resto de parámetros ...

await cmdInsert.ExecuteNonQueryAsync(); // ❌ AQUÍ OCURRE EL ERROR
```

**El código es correcto.** El problema está en la definición de la tabla destino.

---

## 🚀 Cómo Funciona la Aplicación Completa

### Arquitectura General

```
┌─────────────────────────────────────────────────────────────┐
│                    USUARIO (Navegador)                      │
│                  http://localhost:5071                      │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ HTTP Requests
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              .NET 9 Minimal API (Program.cs)                │
│                     Puerto 5071                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Endpoints:                                            │  │
│  │ • POST /api/etl/ejecutar                              │  │
│  │ • POST /api/calculo/ejecutar                          │  │
│  │ • GET/POST/PUT/DELETE /api/companias                  │  │
│  │ • GET /api/calculo/resultado                          │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Invoca Servicios
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                    CAPA DE SERVICIOS                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ETLService.cs                                         │  │
│  │ • EjecutarETLAsync()                                  │  │
│  │ • EjecutarCalculoAsync()                              │  │
│  │ • ObtenerProgreso()                                   │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ DatabaseSetupService.cs                               │  │
│  │ • InicializarBaseDatos()                              │  │
│  │ • GetTableCountsAsync()                               │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ SQL Queries
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              BASES DE DATOS (SQL Server)                    │
│                  dbdev.powerera.com                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Actif_RMF (Destino)                                   │  │
│  │ • ConfiguracionCompania                               │  │
│  │ • Staging_Activo        ← ⚠️ FALTA COSTO_REVALUADO   │  │
│  │ • Calculo_RMF                                         │  │
│  │ • Log_Ejecucion_ETL                                   │  │
│  │ • Tipo_Cambio                                         │  │
│  │ • Catalogo_Rutas_Calculo                              │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ actif_web_CIMA_Dev (Origen - Ejemplo)                │  │
│  │ • activo           ← Datos de activos fijos           │  │
│  │ • compania         ← Catálogo compañías               │  │
│  │ • calculo          ← Depreciaciones históricas        │  │
│  │ • tipo_activo      ← Catálogo tipos                   │  │
│  │ • pais             ← Catálogo países                  │  │
│  │ • moneda           ← Catálogo monedas                 │  │
│  │ • porcentaje_depreciacion                             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Flujo Completo de ETL

#### Paso 1: Configuración de Compañía
```
Usuario → companias.html
    ↓
POST /api/companias
{
  "idCompania": 188,
  "nombreCompania": "Compañia Prueba 188",
  "nombreCorto": "CP188",
  "connectionString": "Server=...;Database=actif_web_CIMA_Dev;...",
  "activo": true
}
    ↓
Guarda en: Actif_RMF.dbo.ConfiguracionCompania
```

#### Paso 2: Ejecución de ETL
```
Usuario → extraccion.html
    ↓
POST /api/etl/ejecutar
{
  "idCompania": 188,
  "añoCalculo": 2024
}
    ↓
ETLService.EjecutarETLAsync()
    ↓
1. Lee ConfiguracionCompania → Obtiene ConnectionString + Query_ETL
2. Conecta a Base Origen (actif_web_CIMA_Dev)
3. Ejecuta Query_ETL con parámetros reemplazados
4. Por cada registro:
   - Lee desde DataReader
   - Inserta en Actif_RMF.dbo.Staging_Activo ← ⚠️ AQUÍ FALLA
5. Registra en Log_Ejecucion_ETL
6. Actualiza progreso en tiempo real
```

#### Paso 3: Cálculo RMF (Stored Procedure)
```
Usuario → calculo.html
    ↓
POST /api/calculo/ejecutar
{
  "idCompania": 188,
  "añoCalculo": 2024,
  "loteImportacion": "9e1102b2-b29e-4d3d-9b3c-03cf50705003"
}
    ↓
ETLService.EjecutarCalculoAsync()
    ↓
EXEC dbo.sp_Calcular_RMF_Activos_Extranjeros
     @ID_Compania = 188,
     @Año_Calculo = 2024,
     @Lote_Importacion = '9e1102b2-b29e-4d3d-9b3c-03cf50705003'
    ↓
Inserta en: Actif_RMF.dbo.Calculo_RMF
```

#### Paso 4: Generación de Reportes
```
Usuario → reporte.html
    ↓
GET /api/calculo/resultado/{idCompania}/{añoCalculo}
    ↓
Lee desde: Actif_RMF.dbo.Calculo_RMF
    ↓
Genera Excel con múltiples hojas:
  • Resumen Activos Extranjeros
  • Detalle Activos Extranjeros
  • Resumen Activos Nacionales
  • Detalle Activos Nacionales
```

### Archivos Clave del Proyecto

```
/Users/enrique/ActifRMF/ActifRMF/
├── Program.cs                       ← API Endpoints (Minimal API)
├── Services/
│   ├── ETLService.cs                ← Lógica de ETL y Cálculo
│   └── DatabaseSetupService.cs      ← Setup inicial de BD
├── wwwroot/
│   ├── index.html                   ← Dashboard principal
│   ├── companias.html               ← CRUD de compañías
│   ├── extraccion.html              ← Ejecución de ETL
│   ├── calculo.html                 ← Ejecución de cálculo
│   ├── inpc.html                    ← Catálogo INPC
│   └── reporte.html                 ← Generación de reportes
└── appsettings.json                 ← Connection strings

```

---

## ⚙️ Configuración de Conexiones

### appsettings.json

```json
{
  "ConnectionStrings": {
    "ActifRMF": "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=usuarioPrueba;Password=Password123!;TrustServerCertificate=True;"
  }
}
```

**Nota:** Los connection strings de las bases origen se configuran por compañía en la tabla `ConfiguracionCompania`.

### Ejemplo de Query_ETL Personalizado

Cada compañía puede tener un query ETL personalizado almacenado en `ConfiguracionCompania.Query_ETL`. Si no tiene uno, usa el query predeterminado.

**Query almacenado para Compañía 188:**
```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,        ← COLUMNA CRÍTICA
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC AS FECHA_INICIO_DEP,
    a.STATUS,
    CAST(CASE WHEN a.FLG_PROPIO = 'P' THEN 1 ELSE 0 END AS INT) AS FLG_PROPIO,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR)
         ELSE 0
    END AS Tasa_Anual,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR / 12.0)
         ELSE 0
    END AS Tasa_Mensual,
    ISNULL(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año
FROM activo a
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA
INNER JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_COMPANIA = @ID_COMPANIA
    AND c.ID_ANO = @AÑO_ANTERIOR
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
WHERE a.ID_COMPANIA = @ID_COMPANIA
  AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(@AÑO_CALCULO AS VARCHAR) + '-12-31')
  AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(@AÑO_CALCULO AS VARCHAR) + '-01-01')
```

**Parámetros reemplazados en tiempo de ejecución:**
- `@ID_COMPANIA` → 188
- `@AÑO_CALCULO` → 2024
- `@AÑO_ANTERIOR` → 2023

---

## 📝 Instrucciones para Continuar el Desarrollo

### 1. Corregir el Esquema de Base de Datos

**ACCIÓN INMEDIATA:** Ejecutar el script SQL en dbdev.powerera.com:

```bash
# Opción 1: Con PESqlConnect
cd /Users/enrique/ActifRMF/ActifRMF
PESqlConnect dbdev.powerera.com usuarioPrueba Password123! Actif_RMF "
ALTER TABLE dbo.Staging_Activo
ADD COSTO_REVALUADO DECIMAL(18, 2) NULL;
"

# Opción 2: Conectar directamente con SQL Server Management Studio
# Server: dbdev.powerera.com
# Login: usuarioPrueba / Password123!
# Database: Actif_RMF
# Ejecutar: ALTER TABLE dbo.Staging_Activo ADD COSTO_REVALUADO DECIMAL(18, 2) NULL;
```

### 2. Verificar la Corrección

Después de agregar la columna, ejecutar:

```sql
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
  AND TABLE_NAME = 'Staging_Activo'
  AND COLUMN_NAME = 'COSTO_REVALUADO';
```

**Resultado esperado:**
```
COLUMN_NAME        DATA_TYPE    IS_NULLABLE
------------------------------------------
COSTO_REVALUADO    decimal      YES
```

### 3. Probar el ETL Nuevamente

```bash
# Terminal 1: Iniciar servidor
cd /Users/enrique/ActifRMF/ActifRMF
dotnet run --urls="http://localhost:5071"

# Terminal 2: Ejecutar ETL
curl -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 188, "añoCalculo": 2024}'
```

**Resultado esperado:**
```json
{
  "message": "ETL iniciado",
  "loteImportacion": "...",
  "idCompania": 188,
  "añoCalculo": 2024
}
```

Y en los logs del servidor:
```
✅ ETL Completado
Registros importados: 34898
Duración: X segundos
```

### 4. Validar Datos Insertados

```sql
USE Actif_RMF;

-- Verificar que se insertaron registros
SELECT COUNT(*) AS Total_Registros
FROM dbo.Staging_Activo
WHERE ID_Compania = 188
  AND Año_Calculo = 2024;

-- Verificar que COSTO_REVALUADO tiene datos
SELECT
    COUNT(*) AS Total,
    COUNT(COSTO_REVALUADO) AS Con_Costo_Revaluado,
    SUM(CAST(COSTO_REVALUADO AS DECIMAL(18,2))) AS Suma_Costo_Revaluado
FROM dbo.Staging_Activo
WHERE ID_Compania = 188
  AND Año_Calculo = 2024;

-- Ver algunos ejemplos
SELECT TOP 10
    ID_NUM_ACTIVO,
    ID_ACTIVO,
    DESCRIPCION,
    COSTO_ADQUISICION,
    COSTO_REVALUADO,
    ID_PAIS,
    FLG_PROPIO
FROM dbo.Staging_Activo
WHERE ID_Compania = 188
  AND Año_Calculo = 2024
  AND COSTO_REVALUADO IS NOT NULL
ORDER BY COSTO_REVALUADO DESC;
```

---

## 🐛 Lecciones Aprendidas

### 1. Importancia del Debug Estratégico

Los dos puntos de debug agregados fueron cruciales para identificar que:
- El query origen está correcto
- Los datos se leen correctamente
- El error ocurre en el destino, no en el origen

### 2. Errores de SQL Server

El mensaje "Invalid column name 'COSTO_REVALUADO'" puede ocurrir en dos contextos:
- ❌ Al leer: `readerOrigen["COSTO_REVALUADO"]` (no fue el caso)
- ✅ Al insertar: `INSERT INTO ... (COSTO_REVALUADO)` (fue el caso real)

### 3. Validación de Esquemas

Siempre validar que las tablas destino tengan todas las columnas que el código espera antes de ejecutar inserciones masivas.

### 4. Testing con Datos Reales

Los 34,898 registros de la compañía 188 proveen un dataset robusto para pruebas de carga y validación.

---

## 🔗 Referencias

- **Código fuente:** `/Users/enrique/ActifRMF/ActifRMF/`
- **README principal:** `/Users/enrique/ActifRMF/README.md`
- **Guía de conexiones:** `/Users/enrique/readme.md`
- **Servidor:** dbdev.powerera.com
- **Usuario DB:** earaiza / usuarioPrueba
- **Puerto aplicación:** 5071

---

**Fecha actualización:** 13 de Octubre de 2025
**Autor:** Claude (Debugging Session)
**Estado:** ✅ Causa raíz identificada - ⏳ Corrección pendiente en esquema de BD
