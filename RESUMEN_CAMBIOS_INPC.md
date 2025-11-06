# Resumen de Cambios - Sistema INPC Simplificado

**Fecha**: 2025-11-05
**Objetivo**: Simplificar el manejo de INPC, dejando solo 2 campos en Calculo_RMF y eliminando todos de Staging_Activo

---

## 1. Cambios en Base de Datos

### Staging_Activo - Campos INPC Eliminados ✅

**Campos eliminados:**
```sql
ALTER TABLE Staging_Activo DROP COLUMN INPC_Adquisicion;
ALTER TABLE Staging_Activo DROP COLUMN INPC_Mitad_Ejercicio;
ALTER TABLE Staging_Activo DROP COLUMN INPC_Mitad_Periodo;
```

**Resultado**: Staging_Activo NO tiene ningún campo INPC

---

### Calculo_RMF - Solo 2 Campos INPC ✅

**Campos renombrados:**
```sql
EXEC sp_rename 'Calculo_RMF.INPC_Adqu', 'INPCCompra', 'COLUMN';
EXEC sp_rename 'Calculo_RMF.INPC_Mitad_Periodo', 'INPCUtilizado', 'COLUMN';
```

**Campo eliminado:**
```sql
ALTER TABLE Calculo_RMF DROP COLUMN INPC_Mitad_Ejercicio;
```

**Campos finales:**
- ✅ `INPCCompra` - INPC del mes de compra
- ✅ `INPCUtilizado` - INPC del mes a utilizar según lógica SAT

---

### Tablas Auxiliares Creadas ✅

**Archivo**: `/Users/enrique/ActifRMF/Database/Create_INPC_Aux_Tables.sql`

**Tablas:**
1. `INPCSegunMes` - Mapeo mes de cálculo → mes INPC (para activos activos)
2. `INPCbajas` - Mapeo mes anterior a baja → mes INPC
3. `inpcdeprec` - Mapeo mes fin depreciación → mes INPC

---

## 2. Cambios en ETL

**Archivo**: `/Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL/Program.cs`

**Cambios realizados:**
- ❌ Eliminado: `INPC_Adquisicion, INPC_Mitad_Ejercicio` del INSERT (línea 477)
- ❌ Eliminado: `@INPC_Adquisicion, @INPC_Mitad_Ejercicio` del VALUES (línea 486)
- ❌ Eliminado: `AddWithValue` para INPC (líneas 515-516)

**Resultado**: ETL NO trae ningún INPC de la BD origen

---

## 3. Cambios en Stored Procedures

### SP Nacionales ✅

**Archivo**: `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql`

**Versión**: `v4.4-SIN-INPC`

**Cambios:**
1. Tabla temporal usa `INPCCompra` e `INPCUtilizado`
2. INSERT a #ActivosCalculo NO trae INPC de Staging (ya no existen)
3. Cálculos usan factor 1.0 (sin actualización INPC por ahora)
4. INSERT a Calculo_RMF guarda `INPCCompra` e `INPCUtilizado` en NULL
5. Los INPC se actualizarán DESPUÉS por programa externo

**Ejecutado en BD**: ✅

---

### SP Extranjeros ✅

**Archivo**: `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros.sql`

**Versión**: `v4.8-SIN-INPC`

**Cambios:**
1. Eliminados campos `INPC_Adqu`, `INPC_Mitad_Ejercicio`, `INPC_Mitad_Periodo` de tabla temporal
2. Eliminados de INSERT a #ActivosCalculo
3. INSERT a Calculo_RMF guarda `INPCCompra` e `INPCUtilizado` como NULL (no aplican para extranjeros)

**Ejecutado en BD**: ✅

---

## 4. Programa ActualizarINPC

**Ubicación**: `/Users/enrique/ActifRMF/Database/ActualizarINPC/`

**Archivo principal**: `Program.cs`

### Funcionalidad Actualizada ✅

El programa ahora:

1. **Lee de Calculo_RMF** (no de Staging_Activo):
   ```sql
   SELECT ID_Calculo, Fecha_Adquisicion, Fecha_Baja, MOI, Saldo_Inicio_Año,
          Dep_Fiscal_Ejercicio, Meses_Uso_En_Ejercicio
   FROM Calculo_RMF
   WHERE Tipo_Activo = 'Nacional' AND INPCCompra IS NULL
   ```

2. **Obtiene 2 INPC** de la BD origen (`actif_web_cima_dev.inpc2`):
   - `INPCCompra`: Del mes de FECHA_COMPRA
   - `INPCUtilizado`: Según lógica SAT (3 casos)

3. **Lógica SAT para INPCUtilizado**:
   - **Caso 1 - Bajas**: Usa mes ANTERIOR a la baja (tabla INPCbajas)
   - **Caso 2 - Adquiridos en año**: Calcula "mes medio" con fórmula SAT
   - **Caso 3 - Activos todo el año**: Usa tabla INPCSegunMes (dic → junio)

4. **Calcula factores de actualización**:
   ```csharp
   Factor = INPCUtilizado / INPCCompra
   ```

5. **Recalcula valores finales**:
   - Saldo_Actualizado
   - Dep_Actualizada
   - Valor_Promedio
   - Proporcion
   - Valor_Reportable_MXN (con regla 10% MOI)

6. **Actualiza Calculo_RMF** con todos los valores

**Compilado**: ✅

---

## 5. Flujo de Ejecución Actualizado

```
┌─────────────────────────────────────────────────────────┐
│  PASO 1: ETL                                            │
│  cd /Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL       │
│  dotnet run 188 2024                                    │
│                                                         │
│  → Importa activos a Staging_Activo (SIN INPC)        │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  PASO 2: Calcular RMF                                   │
│  EXEC sp_Calcular_RMF_Activos_Nacionales 188, 2024     │
│  EXEC sp_Calcular_RMF_Activos_Extranjeros 188, 2024    │
│                                                         │
│  → Crea registros en Calculo_RMF                       │
│    - Nacionales: INPCCompra e INPCUtilizado en NULL    │
│    - Extranjeros: INPCCompra e INPCUtilizado en NULL   │
│    - Factores de actualización = 1.0                   │
│    - Valores sin actualizar por INPC                   │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  PASO 3: Actualizar INPC (Solo Nacionales)             │
│  cd /Users/enrique/ActifRMF/Database/ActualizarINPC    │
│  dotnet run 188 2024                                    │
│                                                         │
│  → Actualiza Calculo_RMF:                              │
│    - INPCCompra (del mes de compra)                    │
│    - INPCUtilizado (según lógica SAT)                  │
│    - Recalcula factores y valores finales              │
│    - Solo para Tipo_Activo = 'Nacional'                │
└─────────────────────────────────────────────────────────┘
```

---

## 6. Diferencias Entre Activos

### Activos NACIONALES (Fiscal)
- **Identificación**: `ManejaFiscal = 'S'` en Staging, `Tipo_Activo = 'Nacional'` en Calculo_RMF
- **MOI**: CostoMXN
- **INPC**: ✅ Sí usan INPC
  - INPCCompra: Del mes de compra
  - INPCUtilizado: Según lógica SAT (bajas, adquisiciones, activos normales)
- **Actualización**: Factor = INPCUtilizado / INPCCompra
- **Programa**: ActualizarINPC actualiza estos activos

### Activos EXTRANJEROS (USGAAP)
- **Identificación**: `ID_PAIS > 1`, `Tipo_Activo = 'Extranjero'` en Calculo_RMF
- **MOI**: CostoUSD (convertido a MXN con TC 30-Jun)
- **INPC**: ❌ NO usan INPC
  - INPCCompra: NULL
  - INPCUtilizado: NULL
- **Actualización**: No aplica (factor = 1.0)
- **Programa**: ActualizarINPC ignora estos activos

---

## 7. Archivos Creados/Modificados

### Creados ✅
1. `/Users/enrique/ActifRMF/Database/Create_INPC_Aux_Tables.sql`
2. `/Users/enrique/ActifRMF/Database/ActualizarINPC/Program.cs` (reescrito)
3. `/Users/enrique/ActifRMF/Database/ActualizarINPC/Ejecutar_Actualizar_INPC.csproj`
4. `/Users/enrique/ActifRMF/Database/ActualizarINPC/README.md`
5. `/Users/enrique/ActifRMF/RESUMEN_CAMBIOS_INPC.md` (este archivo)

### Modificados ✅
1. `/Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL/Program.cs`
2. `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql`
3. `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros.sql`

### Base de Datos ✅
1. Staging_Activo - 3 columnas eliminadas
2. Calculo_RMF - 2 columnas renombradas, 1 eliminada
3. INPCbajas, INPCSegunMes, inpcdeprec - tablas creadas

---

## 8. Ventajas del Nuevo Sistema

✅ **Separación clara de responsabilidades**:
- ETL: Solo importa datos base
- SP Cálculo: Solo calcula sin INPC
- Programa INPC: Solo actualiza INPC y recalcula

✅ **No requiere linked servers**:
- Usa conexiones separadas como el ETL

✅ **Modular y testeable**:
- Cada componente se puede probar independientemente

✅ **Lógica SAT correcta**:
- Implementa los 3 casos fiscales (bajas, adquisiciones, activos normales)

✅ **Simplificado**:
- Solo 2 campos INPC en lugar de 3
- Sin campos INPC en Staging

---

## 9. Próximos Pasos (Opcionales)

### Integración Automatizada
Agregar la ejecución del ActualizarINPC al flujo del API:

**Archivo**: `/Users/enrique/ActifRMF/ActifRMF/Program.cs`

```csharp
// Después de ejecutar SP de cálculo
await ExecuteSP("sp_Calcular_RMF_Activos_Nacionales", idCompania, añoCalculo);

// Ejecutar actualización de INPC
var processStartInfo = new ProcessStartInfo
{
    FileName = "dotnet",
    Arguments = $"run {idCompania} {añoCalculo}",
    WorkingDirectory = "/Users/enrique/ActifRMF/Database/ActualizarINPC"
};
await Process.Start(processStartInfo).WaitForExitAsync();

// Continuar con extranjeros
await ExecuteSP("sp_Calcular_RMF_Activos_Extranjeros", idCompania, añoCalculo);
```

---

## 10. Comandos de Prueba

### Flujo Completo Manual

```bash
# 1. ETL
cd /Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL
dotnet run 188 2024

# 2. Cálculo Nacionales
sqlcmd -S dbdev.powerera.com -d Actif_RMF -U earaiza -P '...' -C \
  -Q "EXEC sp_Calcular_RMF_Activos_Nacionales 188, 2024"

# 3. Actualizar INPC
cd /Users/enrique/ActifRMF/Database/ActualizarINPC
dotnet run 188 2024

# 4. Cálculo Extranjeros
sqlcmd -S dbdev.powerera.com -d Actif_RMF -U earaiza -P '...' -C \
  -Q "EXEC sp_Calcular_RMF_Activos_Extranjeros 188, 2024"
```

### Verificar Resultados

```sql
-- Ver activos nacionales con INPC
SELECT TOP 10
    ID_NUM_ACTIVO,
    INPCCompra,
    INPCUtilizado,
    Factor_Actualizacion_Saldo,
    Saldo_Actualizado,
    Valor_Reportable_MXN
FROM Calculo_RMF
WHERE ID_Compania = 188
  AND Año_Calculo = 2024
  AND Tipo_Activo = 'Nacional'
ORDER BY ID_NUM_ACTIVO;

-- Ver activos extranjeros sin INPC
SELECT TOP 10
    ID_NUM_ACTIVO,
    INPCCompra,  -- Debe ser NULL
    INPCUtilizado,  -- Debe ser NULL
    Valor_Reportable_MXN
FROM Calculo_RMF
WHERE ID_Compania = 188
  AND Año_Calculo = 2024
  AND Tipo_Activo = 'Extranjero'
ORDER BY ID_NUM_ACTIVO;
```

---

**Fin del documento**
