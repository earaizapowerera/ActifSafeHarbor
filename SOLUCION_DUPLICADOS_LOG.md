# Solucion Robusta: Prevencion de Duplicados en Log_Ejecucion_ETL

## Problema Identificado

La tabla `Log_Ejecucion_ETL` permitia multiples registros para el mismo `Lote_Importacion`, causando duplicados en el dropdown de lotes ETL. La solucion temporal era usar `DISTINCT` en las consultas, pero esto no resuelve el problema de raiz.

## Solucion Implementada

### 1. Constraint de Base de Datos (SQL)

**Archivo:** `/Users/enrique/ActifRMF/SQL/07_FIX_LOG_DUPLICADOS.sql`

Se creo un script que:

1. **Limpia duplicados existentes**: Elimina registros duplicados manteniendo solo el mas reciente por cada combinacion `(Lote_Importacion, Tipo_Proceso)`

2. **Agrega constraint UNIQUE**:
   ```sql
   ALTER TABLE dbo.Log_Ejecucion_ETL
   ADD CONSTRAINT UQ_Log_Lote_TipoProceso
   UNIQUE (Lote_Importacion, Tipo_Proceso);
   ```

   Este constraint garantiza que:
   - Cada `Lote_Importacion` de tipo 'ETL' solo puede tener UN registro
   - Cada `Lote_Importacion` de tipo 'CALCULO' solo puede tener UN registro
   - No se pueden insertar duplicados a nivel de base de datos

### 2. Logica MERGE en ETLService.cs

**Archivo:** `/Users/enrique/ActifRMF/ActifRMF/Services/ETLService.cs`

Se modifico el codigo para usar `MERGE` en lugar de `INSERT` directo:

#### Proceso ETL (lineas 85-127)

```csharp
// Usar MERGE para insertar solo si no existe, o actualizar si ya existe
var sqlLog = @"
    MERGE INTO dbo.Log_Ejecucion_ETL AS target
    USING (SELECT @LoteImportacion AS Lote_Importacion, 'ETL' AS Tipo_Proceso) AS source
    ON target.Lote_Importacion = source.Lote_Importacion
       AND target.Tipo_Proceso = source.Tipo_Proceso
    WHEN MATCHED THEN
        UPDATE SET
            Fecha_Inicio = @FechaInicio,
            Estado = 'En Proceso',
            Usuario = @Usuario,
            [... resetear otros campos ...]
    WHEN NOT MATCHED THEN
        INSERT (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
                Fecha_Inicio, Estado, Usuario)
        VALUES (@IdCompania, @AñoCalculo, @LoteImportacion, 'ETL',
                @FechaInicio, 'En Proceso', @Usuario);

    SELECT ID_Log
    FROM dbo.Log_Ejecucion_ETL
    WHERE Lote_Importacion = @LoteImportacion
      AND Tipo_Proceso = 'ETL';";
```

**Comportamiento:**
- Si el lote ya existe: ACTUALIZA el registro existente (reinicia el proceso)
- Si el lote NO existe: INSERTA un nuevo registro
- Siempre devuelve el `ID_Log` para posteriores updates

#### Proceso CALCULO (lineas 336-378)

Se aplico la misma logica MERGE para el proceso de calculo.

### 3. Eliminacion del DISTINCT

**Archivo:** `/Users/enrique/ActifRMF/ActifRMF/Program.cs`

Se elimino el `DISTINCT` del endpoint `/api/calculo/lotes-disponibles` (linea 380):

**ANTES:**
```sql
SELECT DISTINCT
    l.Lote_Importacion,
    l.Fecha_Inicio,
    l.Registros_Procesados
FROM dbo.Log_Ejecucion_ETL l
...
```

**DESPUES:**
```sql
SELECT
    l.Lote_Importacion,
    l.Fecha_Inicio,
    l.Registros_Procesados
FROM dbo.Log_Ejecucion_ETL l
...
```

Ya no se necesita `DISTINCT` porque el constraint garantiza que no hay duplicados.

### 4. Actualizacion del DatabaseSetupService

**Archivo:** `/Users/enrique/ActifRMF/ActifRMF/Services/DatabaseSetupService.cs`

Se agrego el nuevo script al setup automatico (linea 77):

```csharp
var scripts = new[]
{
    "/Users/enrique/ActifRMF/SQL/02_CREATE_TABLES.sql",
    "/Users/enrique/ActifRMF/SQL/03_INSERT_CATALOGOS.sql",
    "/Users/enrique/ActifRMF/SQL/04_SP_ETL_Importar_Activos.sql",
    "/Users/enrique/ActifRMF/SQL/05_SP_Calcular_RMF_Activos_Extranjeros.sql",
    "/Users/enrique/ActifRMF/SQL/06_AJUSTES_TABLAS.sql",
    "/Users/enrique/ActifRMF/SQL/07_FIX_LOG_DUPLICADOS.sql"  // NUEVO
};
```

## Ventajas de esta Solucion

1. **Prevencion a nivel de BD**: El constraint `UNIQUE` impide fisicamente la insercion de duplicados
2. **Logica robusta**: El `MERGE` maneja correctamente reintentos y re-ejecuciones
3. **Performance mejorado**: Ya no se necesita `DISTINCT` en las consultas
4. **Consistencia garantizada**: La integridad se mantiene incluso con concurrencia
5. **Idempotencia**: Ejecutar el ETL multiples veces con el mismo lote no crea duplicados

## Como Aplicar la Solucion

### Opcion 1: Setup automatico (base de datos nueva)

```bash
curl -X POST http://localhost:5226/api/setup/database
```

El script `07_FIX_LOG_DUPLICADOS.sql` se ejecutara automaticamente.

### Opcion 2: Ejecucion manual (base de datos existente)

Ejecutar directamente el script SQL:

```bash
# Conectarse a SQL Server
sqlcmd -S localhost -U sa -P YourPassword -d Actif_RMF -i /Users/enrique/ActifRMF/SQL/07_FIX_LOG_DUPLICADOS.sql
```

O desde SSMS/Azure Data Studio:
1. Abrir `/Users/enrique/ActifRMF/SQL/07_FIX_LOG_DUPLICADOS.sql`
2. Ejecutar contra la base de datos `Actif_RMF`

## Verificacion

Despues de aplicar la solucion:

1. **Verificar constraint creado:**
   ```sql
   SELECT name, type_desc
   FROM sys.indexes
   WHERE name = 'UQ_Log_Lote_TipoProceso'
   AND object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL');
   ```

2. **Verificar no hay duplicados:**
   ```sql
   SELECT
       Tipo_Proceso,
       COUNT(*) AS Total_Registros,
       COUNT(DISTINCT Lote_Importacion) AS Lotes_Unicos
   FROM dbo.Log_Ejecucion_ETL
   GROUP BY Tipo_Proceso;
   ```

   `Total_Registros` debe ser igual a `Lotes_Unicos`.

3. **Probar insercion duplicada (debe fallar):**
   ```sql
   -- Esto debe dar error de constraint violation
   INSERT INTO dbo.Log_Ejecucion_ETL
       (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
        Fecha_Inicio, Estado, Usuario)
   VALUES
       (1, 2024, NEWID(), 'ETL', GETDATE(), 'En Proceso', 'Test');

   -- Intentar insertar el mismo lote otra vez (debe fallar)
   INSERT INTO dbo.Log_Ejecucion_ETL
       (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
        Fecha_Inicio, Estado, Usuario)
   VALUES
       (1, 2024, [mismo GUID], 'ETL', GETDATE(), 'En Proceso', 'Test');
   ```

## Archivos Modificados

1. `/Users/enrique/ActifRMF/SQL/07_FIX_LOG_DUPLICADOS.sql` - **NUEVO**
2. `/Users/enrique/ActifRMF/ActifRMF/Services/ETLService.cs` - Modificado (MERGE logic)
3. `/Users/enrique/ActifRMF/ActifRMF/Program.cs` - Modificado (removido DISTINCT)
4. `/Users/enrique/ActifRMF/ActifRMF/Services/DatabaseSetupService.cs` - Modificado (nuevo script)

## Estado del Proyecto

- ✅ Compilacion exitosa
- ✅ Constraint de BD implementado
- ✅ Logica MERGE implementada
- ✅ DISTINCT removido
- ✅ Script integrado en setup automatico

## Proximos Pasos

1. Ejecutar el script `07_FIX_LOG_DUPLICADOS.sql` en la base de datos
2. Reiniciar el backend para aplicar los cambios de codigo
3. Ejecutar las pruebas Selenium para verificar que el dropdown funciona correctamente
4. Verificar que no se crean duplicados al ejecutar ETL multiples veces

---

**Fecha de implementacion:** 2025-10-13
**Autor:** Claude Code
**Version:** 1.0
