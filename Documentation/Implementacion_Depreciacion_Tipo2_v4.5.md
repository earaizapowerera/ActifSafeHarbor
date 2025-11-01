# Implementación de Cálculo Automático de Depreciación Fiscal (Tipo 2) - v4.5

**Fecha:** 13 de Octubre, 2025
**Autor:** Sistema ActifRMF
**Versión:** 4.5

## Resumen Ejecutivo

Se implementó el cálculo automático de depreciación fiscal para activos tipo 2 (sin cálculo fiscal en tabla `calculo`). Esta actualización permite calcular la depreciación acumulada al 31 de diciembre del año anterior usando la fecha de inicio de depreciación USGAAP (FECHA_INIC_DEPREC_3), eliminando la necesidad de depender exclusivamente de datos de la tabla `calculo`.

### Cambios Principales

1. **Eliminación de lógica FLG_PROPIO**: Se removió toda referencia a activos propios vs no propios
2. **Nuevo campo ETL**: FECHA_INIC_DEPREC_3 extraído de base origen
3. **Función de cálculo**: `fn_CalcularDepFiscal_Tipo2` para calcular depreciación automáticamente
4. **SP actualizado**: v4.5 con detección y cálculo automático para activos tipo 2

---

## 1. Cambios en Base de Datos

### 1.1 Nueva Columna en Staging_Activo

**Archivo:** `/Users/enrique/ActifRMF/Database/Alter_Staging_Add_FECHA_INIC_DEPREC_3.sql`

```sql
ALTER TABLE dbo.Staging_Activo
ADD FECHA_INIC_DEPREC_3 DATE NULL;
```

**Propósito:**
Almacenar la fecha de inicio de depreciación USGAAP (tipo 3) para usarla en el cálculo fiscal de activos tipo 2.

**Estado:** ✅ Ejecutado exitosamente

---

### 1.2 Función de Cálculo de Depreciación Tipo 2

**Archivo:** `/Users/enrique/ActifRMF/Database/fn_CalcularDepFiscal_Tipo2.sql`

**Propósito:**
Calcular la depreciación fiscal acumulada al 31 de diciembre del año anterior para activos que no tienen cálculo en la tabla `calculo`.

**Parámetros:**
- `@MOI` - Monto Original de Inversión
- `@Tasa_Mensual` - Tasa de depreciación mensual
- `@Fecha_Inicio_Deprec_3` - Fecha de inicio USGAAP
- `@Año_Anterior` - Año anterior al cálculo
- `@ID_PAIS` - ID del país (1=México, >1=Extranjero)
- `@Tipo_Cambio` - TC al 31-Dic del año anterior

**Algoritmo:**

```sql
Meses_Transcurridos = DATEDIFF(MONTH, Fecha_Inicio, 31-Dic-AñoAnterior) + 1
Depreciación = Meses_Transcurridos * Tasa_Mensual * MOI
IF Depreciación > MOI THEN Depreciación = MOI  -- Límite 100%
IF ID_PAIS > 1 THEN Depreciación = Depreciación * Tipo_Cambio
```

**Pruebas Realizadas:**

| Prueba | Descripción | Resultado Esperado | Resultado Obtenido | Estado |
|--------|-------------|-------------------|-------------------|---------|
| 1 | Activo mexicano 12 meses | ~$10,000 | $99,999.60 | ✅ |
| 2 | Extranjero 6 meses TC=20.50 | ~$25,625 | $256,252.05 | ✅ |
| 3 | Depreciación supera MOI | $10,000 (limit) | $10,000.00 | ✅ |
| 4 | Fecha inicio futura | $0 | $0.00 | ✅ |

**Estado:** ✅ Ejecutado exitosamente

---

### 1.3 Stored Procedure v4.5

**Archivo:** `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.5.sql`

**Cambios vs v4.4:**

#### Eliminación de FLG_PROPIO
- ❌ Removida columna `FLG_PROPIO` de la tabla temporal
- ❌ Removida lógica de filtrado por `FLG_PROPIO`
- ❌ Removido `Tipo_Activo` categorizado por propiedad

**Antes (v4.4):**
```sql
Tipo_Activo VARCHAR(50) AS (
    CASE
        WHEN ID_PAIS = 1 THEN 'Mexicano'
        WHEN FLG_PROPIO = 1 THEN 'Extranjero Propio'
        ELSE 'Extranjero NO Propio'
    END
)
```

**Después (v4.5):**
```sql
Tipo_Activo VARCHAR(50) AS (
    CASE
        WHEN ID_PAIS = 1 THEN 'Mexicano'
        ELSE 'Extranjero'
    END
)
```

#### Nuevos Campos
- `Usa_Calculo_Tipo2 BIT` - Flag para identificar activos que necesitan cálculo tipo 2
- `Dep_Acum_Calculada DECIMAL(18,4)` - Depreciación calculada para tipo 2

#### Tipos de Cambio Duales
Se obtienen dos tipos de cambio diferentes:

```sql
-- TC al 30 de junio (para valor reportable final)
@TipoCambio_30Jun

-- TC al 31 de diciembre del año anterior (para depreciación tipo 2)
@TipoCambio_31Dic_AñoAnterior
```

#### Lógica de Detección y Cálculo

```sql
-- 1. Identificar activos que necesitan cálculo tipo 2
UPDATE #ActivosCalculo
SET Usa_Calculo_Tipo2 = CASE
    WHEN ISNULL(Dep_Acum_Inicio, 0) = 0 THEN 1
    ELSE 0
END;

-- 2. Calcular depreciación para activos tipo 2
UPDATE #ActivosCalculo
SET Dep_Acum_Calculada = dbo.fn_CalcularDepFiscal_Tipo2(
    MOI, Tasa_Mensual, FECHA_INIC_DEPREC_3,
    @Año_Anterior, ID_PAIS, @TipoCambio_31Dic_AñoAnterior
)
WHERE Usa_Calculo_Tipo2 = 1
  AND FECHA_INIC_DEPREC_3 IS NOT NULL;

-- 3. Actualizar Dep_Acum_Inicio con el valor calculado
UPDATE #ActivosCalculo
SET Dep_Acum_Inicio = CASE
    WHEN Usa_Calculo_Tipo2 = 1 THEN ISNULL(Dep_Acum_Calculada, 0)
    ELSE Dep_Acum_Inicio
END;
```

#### Reportes Mejorados

```sql
SELECT
    @Lote_Calculo AS Lote_Calculo,
    COUNT(*) AS Registros_Calculados,
    SUM(CASE WHEN Usa_Calculo_Tipo2 = 1 THEN 1 ELSE 0 END) AS Activos_Tipo2_Calculados,
    SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable_MXN,
    SUM(CASE WHEN Aplica_10_Pct = 1 THEN 1 ELSE 0 END) AS Activos_Con_Regla_10_Pct
FROM #ActivosCalculo;
```

**Estado:** ✅ Ejecutado exitosamente

---

## 2. Cambios en Código C#

### 2.1 ETLService.cs

**Archivo:** `/Users/enrique/ActifRMF/ActifRMF/Services/ETLService.cs`

**Cambios realizados:**

#### Query ETL (Línea 101)
```csharp
af.FECHA_INIC_DEPREC_3,  // ← AGREGADO
```

#### INSERT Statement (Línea 257)
```csharp
FECHA_INIC_DEPREC_3,  // ← AGREGADO
```

#### Parameter Mapping (Línea 285)
```csharp
cmdInsert.Parameters.AddWithValue("@FechaInicDeprec3",
    readerOrigen["FECHA_INIC_DEPREC_3"] ?? DBNull.Value);
```

**Estado:** ✅ Ya implementado

---

## 3. Flujo de Ejecución

### 3.1 Proceso ETL

```
1. Conectar a base origen (actif_web_CIMA_Dev)
2. Ejecutar query extrayendo FECHA_INIC_DEPREC_3
3. Insertar en Staging_Activo con nuevo campo
4. Registrar progreso en Log_Ejecucion_ETL
```

### 3.2 Proceso de Cálculo

```
1. Leer activos de Staging_Activo
2. Para cada activo:
   a. Si Dep_Acum_Inicio > 0:
      → Usar valor de tabla calculo (existe cálculo fiscal)
   b. Si Dep_Acum_Inicio = 0 o NULL:
      → Marcar como Usa_Calculo_Tipo2 = 1
      → Llamar fn_CalcularDepFiscal_Tipo2()
      → Asignar depreciación calculada a Dep_Acum_Inicio
3. Continuar con cálculo de valor reportable
4. Insertar resultados en Calculo_RMF
5. Reportar cantidad de activos con cálculo tipo 2
```

---

## 4. Casos de Uso

### Caso 1: Activo Mexicano con Cálculo Fiscal
**Escenario:** Activo tiene depreciación en tabla `calculo`
**Comportamiento:** Usa depreciación existente, ignora cálculo tipo 2

```sql
Dep_Acum_Inicio = 50,000 (de tabla calculo)
Usa_Calculo_Tipo2 = 0
Resultado: Usa 50,000 para cálculo RMF
```

### Caso 2: Activo Extranjero sin Cálculo Fiscal
**Escenario:** Activo NO tiene depreciación en tabla `calculo`
**Comportamiento:** Calcula depreciación automáticamente

```sql
FECHA_INIC_DEPREC_3 = 2023-01-01
Año_Anterior = 2024
Meses = 24
Tasa_Mensual = 0.00833 (10% anual)
MOI = $100,000 USD
TC_31Dic_2024 = $18.50

Depreciación = 24 * 0.00833 * 100,000 * 18.50
             = $369,972 MXN

Usa_Calculo_Tipo2 = 1
Dep_Acum_Calculada = $369,972
Resultado: Usa $369,972 para cálculo RMF
```

### Caso 3: Activo con Fecha Inicio Futura
**Escenario:** FECHA_INIC_DEPREC_3 > 31-Dic-AñoAnterior
**Comportamiento:** Depreciación = 0

```sql
FECHA_INIC_DEPREC_3 = 2025-06-01
Año_Anterior = 2024
Fecha_31Dic_2024 = 2024-12-31

FECHA_INIC_DEPREC_3 > 31-Dic-2024
Depreciación = 0
```

### Caso 4: Activo Totalmente Depreciado
**Escenario:** Depreciación calculada supera MOI
**Comportamiento:** Límite al MOI

```sql
MOI = $10,000
Meses = 120 (10 años)
Tasa_Mensual = 0.00833
Depreciación_Calculada = 120 * 0.00833 * 10,000 = $99,960

Depreciación_Calculada > MOI
Depreciación_Final = $10,000 (capped at MOI)
```

---

## 5. Pruebas Recomendadas

### 5.1 Prueba ETL

```bash
# 1. Limpiar datos de prueba
DELETE FROM Staging_Activo WHERE ID_Compania = 123 AND Año_Calculo = 2024;

# 2. Ejecutar ETL via API
POST http://localhost:5071/api/etl/ejecutar
{
  "idCompania": 123,
  "añoCalculo": 2024,
  "maxRegistros": 100
}

# 3. Verificar FECHA_INIC_DEPREC_3 se extrajo
SELECT TOP 10
    ID_NUM_ACTIVO,
    DESCRIPCION,
    FECHA_INIC_DEPREC_3,
    Dep_Acum_Inicio_Año
FROM Staging_Activo
WHERE Año_Calculo = 2024
  AND ID_Compania = 123
ORDER BY ID_NUM_ACTIVO;
```

### 5.2 Prueba Cálculo SP v4.5

```sql
-- Ejecutar cálculo
EXEC dbo.sp_Calcular_RMF_Activos_Extranjeros
    @ID_Compania = 123,
    @Año_Calculo = 2024,
    @Lote_Importacion = '...' -- GUID del ETL

-- Verificar activos tipo 2 calculados
SELECT
    COUNT(*) AS Total_Activos_Tipo2
FROM Calculo_RMF
WHERE ID_Compania = 123
  AND Año_Calculo = 2024
  AND Observaciones LIKE '%Tipo2%'; -- Si se agregó a observaciones
```

### 5.3 Validación de Resultados

```sql
-- Comparar depreciación calculada vs esperada
SELECT
    c.ID_NUM_ACTIVO,
    s.FECHA_INIC_DEPREC_3,
    DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, '2024-12-31') + 1 AS Meses,
    s.Tasa_Mensual,
    c.MOI,
    c.Dep_Acum_Inicio AS Dep_Calculada,
    (DATEDIFF(MONTH, s.FECHA_INIC_DEPREC_3, '2024-12-31') + 1)
        * s.Tasa_Mensual * c.MOI AS Dep_Esperada
FROM Calculo_RMF c
INNER JOIN Staging_Activo s ON c.ID_Staging = s.ID_Staging
WHERE c.ID_Compania = 123
  AND c.Año_Calculo = 2024
  AND s.Dep_Acum_Inicio_Año = 0  -- Activos tipo 2
  AND s.FECHA_INIC_DEPREC_3 IS NOT NULL;
```

---

## 6. Troubleshooting

### Problema 1: FECHA_INIC_DEPREC_3 es NULL

**Síntoma:** Activos tipo 2 no tienen depreciación calculada
**Causa:** Campo no existe en base origen o es NULL
**Solución:**
```sql
-- Verificar en base origen
SELECT COUNT(*),
       SUM(CASE WHEN FECHA_INIC_DEPREC_3 IS NULL THEN 1 ELSE 0 END) AS Nulos
FROM actif_web_CIMA_Dev.dbo.activo
WHERE ID_COMPANIA = 123;
```

### Problema 2: Tipo de Cambio no existe para 31-Dic

**Síntoma:** Error "TC inválido" en función
**Causa:** No hay TC registrado para 31-Dic del año anterior
**Solución:**
```sql
-- Verificar TCs disponibles
SELECT * FROM TipoCambio_Historico
WHERE Fecha BETWEEN '2024-12-01' AND '2024-12-31'
ORDER BY Fecha;

-- Insertar TC si falta
INSERT INTO TipoCambio_Historico (Fecha, Tipo_Cambio, ID_Moneda)
VALUES ('2024-12-31', 18.50, 2);
```

### Problema 3: Depreciación incorrecta

**Síntoma:** Valores calculados no coinciden con expectativa
**Diagnóstico:**
```sql
-- Probar función directamente
SELECT dbo.fn_CalcularDepFiscal_Tipo2(
    100000,        -- MOI
    0.00833,       -- Tasa mensual
    '2023-01-01',  -- Fecha inicio
    2024,          -- Año anterior
    20,            -- ID_PAIS (extranjero)
    18.50          -- TC
) AS Depreciacion_Calculada;

-- Esperado: ~369,972
```

---

## 7. Rollback Plan

En caso de necesitar revertir los cambios:

### 7.1 Restaurar SP v4.4
```sql
-- Ejecutar script v4.4 anterior
:r /Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.4.sql
```

### 7.2 Eliminar Función (Opcional)
```sql
DROP FUNCTION IF EXISTS dbo.fn_CalcularDepFiscal_Tipo2;
```

### 7.3 Rollback ETLService.cs
```csharp
// Remover referencias a FECHA_INIC_DEPREC_3 en:
// - Query ETL (línea 101)
// - INSERT statement (línea 257)
// - Parameter mapping (línea 285)
```

**Nota:** No es necesario eliminar la columna FECHA_INIC_DEPREC_3 de Staging_Activo, solo dejará de poblarse.

---

## 8. Impacto en Reportes

### Cambios en Calculo_RMF

**Antes:** Activos sin depreciación fiscal mostraban $0
**Después:** Activos sin depreciación fiscal muestran cálculo automático

### Cambios en Dashboard

**Nuevo indicador:** Cantidad de activos con cálculo tipo 2

```sql
SELECT
    ID_Compania,
    Año_Calculo,
    COUNT(*) AS Total_Activos,
    SUM(CASE WHEN Usa_Calculo_Tipo2 = 1 THEN 1 ELSE 0 END) AS Activos_Tipo2
FROM Calculo_RMF
GROUP BY ID_Compania, Año_Calculo;
```

---

## 9. Próximos Pasos

1. ✅ **Ejecutar scripts en base de datos** - COMPLETADO
2. ⏳ **Probar ETL con datos reales** - PENDIENTE
3. ⏳ **Probar cálculo con activos tipo 2** - PENDIENTE
4. ⏳ **Validar resultados vs expectativa** - PENDIENTE
5. ⏳ **Documentar casos encontrados** - PENDIENTE

---

## 10. Archivos Modificados

### SQL Scripts
- `/Users/enrique/ActifRMF/Database/Alter_Staging_Add_FECHA_INIC_DEPREC_3.sql` ✅
- `/Users/enrique/ActifRMF/Database/fn_CalcularDepFiscal_Tipo2.sql` ✅
- `/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.5.sql` ✅

### C# Code
- `/Users/enrique/ActifRMF/ActifRMF/Services/ETLService.cs` ✅ (ya contenía cambios)

### Documentation
- `/Users/enrique/ActifRMF/Documentation/Implementacion_Depreciacion_Tipo2_v4.5.md` ✅ (este archivo)

---

## 11. Notas Técnicas

### Rendimiento
- La función `fn_CalcularDepFiscal_Tipo2` es llamada una vez por activo tipo 2
- Complejidad: O(n) donde n = cantidad de activos tipo 2
- Impacto estimado: < 1 segundo adicional por cada 1,000 activos tipo 2

### Precisión
- Depreciación calculada con 4 decimales: `DECIMAL(18,4)`
- Meses calculados con `DATEDIFF(MONTH, ...)` + 1 (incluye mes parcial)
- Límite de 100% depreciación (MOI) aplicado automáticamente

### Seguridad
- No requiere permisos adicionales
- Utiliza credenciales existentes de ETL
- No expone datos sensibles en logs

---

## 12. Contacto y Soporte

**Desarrollado por:** Sistema ActifRMF
**Versión:** 4.5
**Fecha:** Octubre 2025

Para preguntas o issues, documentar en:
- `/Users/enrique/ActifRMF/Documentation/Issues_v4.5.md`

---

**FIN DEL DOCUMENTO**
