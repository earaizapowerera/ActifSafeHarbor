# Actualizar INPC para Activos Nacionales

## Descripción

Este programa actualiza el campo `INPC_Mitad_Periodo` en la tabla `Staging_Activo` según la lógica fiscal del SAT para activos nacionales.

## Lógica SAT Implementada

El programa determina qué mes INPC usar según 3 casos:

### Caso 1: Activos dados de baja en el año
- **Condición**: `FECHA_BAJA IS NOT NULL AND YEAR(FECHA_BAJA) = @Año_Calculo`
- **Lógica**: Usa el mes ANTERIOR a la fecha de baja
- **Mapeo**: Tabla `INPCbajas`
- **Ejemplo**: Activo dado de baja en febrero 2024 → usa INPC de enero 2024

### Caso 2: Activos adquiridos en el año
- **Condición**: `YEAR(FECHA_COMPRA) = @Año_Calculo`
- **Lógica**: Calcula el "mes medio" según fórmula SAT
- **Fórmula**: `mes_medio = ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)`
- **Ejemplos**:
  - Comprado en enero: mes medio = 6 (junio)
  - Comprado en julio: mes medio = 9 (septiembre) → INPC de abril
  - Comprado en octubre: mes medio = 11 (noviembre) → INPC de mayo

### Caso 3: Activos activos de años anteriores
- **Condición**: `YEAR(FECHA_COMPRA) < @Año_Calculo`
- **Lógica**: Usa tabla `INPCSegunMes`
- **Para Safe Harbor anual (diciembre)**: mes 12 → mes 6 (junio)
- **Ejemplo**: Activo activo todo 2024 → usa INPC de junio 2024

## Requisitos Previos

1. **Tablas auxiliares creadas**: `INPCbajas`, `INPCSegunMes`, `inpcdeprec`
   - Ya creadas en el script: `/Users/enrique/ActifRMF/Database/Create_INPC_Aux_Tables.sql`

2. **Columna agregada** en `Staging_Activo`:
   ```sql
   ALTER TABLE Staging_Activo ADD INPC_Mitad_Periodo DECIMAL(18,6) NULL
   ```

3. **Datos en `Staging_Activo`**: Debe ejecutarse el ETL primero

## Flujo de Ejecución

```
┌─────────────────────┐
│   1. ETL            │  ← Importa activos a Staging_Activo
│   (ActifRMF.ETL)   │     (ya NO trae INPC_Mitad_Ejercicio)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   2. Actualizar     │  ← Este programa
│      INPC           │     Actualiza INPC_Mitad_Periodo
│   (este programa)   │     según lógica SAT
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   3. Calcular RMF   │  ← Usa INPC_Mitad_Periodo
│   (SP Nacionales)   │     del campo ya actualizado
└─────────────────────┘
```

## Uso

### Compilar el proyecto

```bash
cd /Users/enrique/ActifRMF/Database/ActualizarINPC
dotnet build
```

### Ejecutar

```bash
# Sintaxis: dotnet run <idCompania> <añoCalculo>

# Ejemplo:
dotnet run 188 2024
```

### Output esperado

```
===========================================
ACTUALIZAR INPC PARA ACTIVOS NACIONALES
===========================================

Compañía: 188
Año: 2024

Obteniendo activos de Staging_Activo...
Activos a procesar: 25

Procesando activos...
  Procesados: 10/25
  Procesados: 20/25

✅ TOTAL ACTUALIZADOS: 25

Proceso completado.
```

## Integración con el ETL

### Opción 1: Manual (actual)

1. Ejecutar ETL:
```bash
cd /Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL
dotnet run 188 2024
```

2. Ejecutar actualización INPC:
```bash
cd /Users/enrique/ActifRMF/Database/ActualizarINPC
dotnet run 188 2024
```

3. Ejecutar cálculo RMF:
```bash
curl -X POST http://localhost:5071/api/calculo/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 188, "añoCalculo": 2024}'
```

### Opción 2: Automatizado (recomendado)

Agregar la llamada al actualizador en el flujo del ETL o en la API de cálculo.

## Modificaciones Necesarias

### 1. ETL - Dejar de traer INPC_Mitad_Ejercicio

En `/Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL/Program.cs`, actualizar el query de extracción para:
- Dejar `INPC_Adquisicion` (se sigue necesitando)
- Remover o dejar NULL el campo `INPC_Mitad_Ejercicio`

### 2. SP Nacionales - Usar INPC_Mitad_Periodo del campo

En `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql`, la línea 371:

**ANTES:**
```sql
SET INPC_Mitad_Periodo = INPC_Mitad_Ejercicio;  -- Por simplicidad, usar INPC de junio
```

**DESPUÉS:**
```sql
-- INPC_Mitad_Periodo ya viene poblado por el programa ActualizarINPC
-- Solo verificar que tenga valor
UPDATE #ActivosCalculo
SET INPC_Mitad_Periodo = COALESCE(INPC_Mitad_Periodo, INPC_Mitad_Ejercicio)
WHERE INPC_Mitad_Periodo IS NULL;
```

## Ventajas del Nuevo Sistema

1. ✅ **Separación de responsabilidades**: El SP de cálculo NO necesita saber la lógica INPC
2. ✅ **Modularidad**: La lógica INPC se puede modificar sin tocar el SP principal
3. ✅ **No requiere linked servers**: Usa conexiones separadas como el ETL
4. ✅ **Claridad**: Cada programa hace una cosa específica
5. ✅ **Testeable**: Se puede probar independientemente

## Troubleshooting

### Error: "Invalid column name 'INPC_Mitad_Periodo'"

**Solución**: Agregar la columna a Staging_Activo:
```bash
sqlcmd -S dbdev.powerera.com -d Actif_RMF -U earaiza -P 'VgfN-n4ju?H1Z4#JFRE' -C \
  -Q "ALTER TABLE Staging_Activo ADD INPC_Mitad_Periodo DECIMAL(18,6) NULL"
```

### Error: "Activos a procesar: 0"

**Causas posibles**:
1. No se ejecutó el ETL antes
2. No hay activos nacionales (ManejaFiscal = 'S') para esa compañía
3. Todos los activos ya tienen INPC_Mitad_Periodo poblado

**Solución**: Ejecutar el ETL primero o verificar datos en Staging_Activo

### Los INPC no se encuentran

**Causa**: La tabla `inpc2` en `actif_web_cima_dev` no tiene datos para ese año/mes

**Solución**: Verificar que existan los INPC necesarios en la base de datos origen

## Archivos Creados

1. `/Users/enrique/ActifRMF/Database/Create_INPC_Aux_Tables.sql` - Crea tablas auxiliares
2. `/Users/enrique/ActifRMF/Database/ActualizarINPC/Program.cs` - Programa principal
3. `/Users/enrique/ActifRMF/Database/ActualizarINPC/Ejecutar_Actualizar_INPC.csproj` - Proyecto .NET
4. `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql` - SP alternativo (no usado)

## Próximos Pasos

1. Modificar el ETL para no traer INPC_Mitad_Ejercicio
2. Modificar el SP Nacionales para usar el campo INPC_Mitad_Periodo ya poblado
3. Integrar la ejecución del ActualizadorINPC en el flujo automatizado
4. Probar con activos reales para verificar cálculos

---

**Fecha de creación**: 2025-11-05
**Autor**: Claude Code
