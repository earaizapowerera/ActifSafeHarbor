# Cambios Safe Harbor - Activos Nacionales

**Fecha:** 2025-11-13
**Version SP:** v5.0-SAFE-HARBOR

---

## Resumen Ejecutivo

Se implementaron cálculos **Safe Harbor** paralelos a los cálculos **Fiscales ISR** para activos nacionales en el sistema ActifRMF. La diferencia clave es que Safe Harbor utiliza **INPC de junio (fijo)** mientras que Fiscal ISR usa **INPC variable según lógica SAT**.

---

## Cambios Realizados

### 1. Tabla `Calculo_RMF` - 9 Columnas Nuevas

Se agregaron las siguientes columnas para almacenar cálculos Safe Harbor:

| # | Columna | Tipo | Descripción |
|---|---------|------|-------------|
| 1 | `INPC_SH_Junio` | DECIMAL(18,6) | INPC de junio del año de cálculo (fijo) |
| 2 | `Factor_SH` | DECIMAL(18,10) | Factor de actualización: INPC_Junio / INPC_Compra |
| 3 | `Saldo_SH_Actualizado` | DECIMAL(18,4) | Saldo inicio × Factor_SH |
| 4 | `Dep_SH_Actualizada` | DECIMAL(18,4) | Depreciación ejercicio × Factor_SH |
| 5 | `Valor_SH_Promedio` | DECIMAL(18,4) | Saldo_SH - (Dep_SH × 50%) |
| 6 | `Proporcion_SH` | DECIMAL(18,4) | (Valor_SH_Promedio / 12) × Meses |
| 7 | `Saldo_SH_Fiscal_Hist` | DECIMAL(18,4) | MOI - Dep_Acum - Dep_Ejercicio |
| 8 | `Saldo_SH_Fiscal_Act` | DECIMAL(18,4) | Saldo_Fiscal_Hist × Factor_SH |
| 9 | `Valor_SH_Reportable` | DECIMAL(18,4) | MAX(Proporcion_SH, 10% MOI) |

**Script ejecutado:**
```sql
Database/ALTER_Calculo_RMF_Add_SafeHarbor_Columns.sql
```

---

### 2. Stored Procedure `sp_Calcular_RMF_Activos_Nacionales`

**Archivo actualizado:**
```
Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales_v5_SH.sql
```

**Versión:** v5.0-SAFE-HARBOR

#### Nuevas Secciones Agregadas:

**A. Obtener INPC de Junio (fijo para Safe Harbor)**

```sql
SELECT @INPC_Junio = Indice
FROM INPC2
WHERE Anio = @Año_Calculo
  AND Mes = 6  -- JUNIO - FIJO
  AND Id_Pais = 1
  AND Id_Grupo_Simulacion = 8;
```

**B. Obtener INPC de Compra**

```sql
UPDATE ac
SET ac.INPCCompra = inpc.Indice
FROM #ActivosCalculo ac
LEFT JOIN INPC2 inpc
    ON YEAR(ac.FECHA_COMPRA) = inpc.Anio
    AND MONTH(ac.FECHA_COMPRA) = inpc.Mes
    AND inpc.Id_Pais = 1
    AND inpc.Id_Grupo_Simulacion = 8;
```

**C. Cálculos Safe Harbor**

1. Factor SH = INPC_Junio / INPC_Compra
2. Saldo SH = Saldo_Inicio × Factor_SH
3. Dep SH = Dep_Ejercicio × Factor_SH
4. Valor Promedio SH = Saldo_SH - (Dep_SH × 50%)
5. Proporción SH = (Valor_Promedio_SH / 12) × Meses
6. Valor Reportable SH = MAX(Proporción_SH, 10% MOI)

---

## Diferencias: Fiscal vs Safe Harbor

| Aspecto | FISCAL ISR | SAFE HARBOR |
|---------|------------|-------------|
| **INPC Utilizado** | Variable según lógica SAT | **Junio (fijo)** |
| **Actualizado por** | Programa `ActualizarINPC` externo | **SP mismo** |
| **Factor** | INPCUtilizado / INPCCompra | **INPC_Junio / INPCCompra** |
| **Columnas** | Factor_Actualizacion_*, Saldo_Actualizado, etc. | **Factor_SH, Saldo_SH_*, etc.** |
| **Resultado** | Valor_Reportable_MXN | **Valor_SH_Reportable** |

### Lógica INPC Fiscal (variable):

**Caso 1 - Bajas:** INPC del mes **anterior** al mes de baja
**Caso 2 - Adquiridos en año:** INPC del "**mes medio**" calculado
**Caso 3 - Todo el año:** INPC de **junio**

### Lógica INPC Safe Harbor (fijo):

**Todos los casos:** INPC de **JUNIO** del año de cálculo

---

## Tabla INPC2 Local

**Estructura identificada:**

```sql
Id_INPC INT
Anio INT
Mes INT
Id_Grupo_Simulacion INT  -- Usar valor 8
Id_Pais INT             -- Usar valor 1 (México)
Indice DECIMAL(18,6)
```

**IMPORTANTE:** La tabla local `INPC2` **NO tiene** la columna `Id_Tipo_Dep` que existe en la BD origen `actif_web_cima_dev.dbo.inpc2`.

---

## Archivos Creados/Modificados

### Creados

1. `/Database/ALTER_Calculo_RMF_Add_SafeHarbor_Columns.sql`
   - Script para agregar 9 columnas Safe Harbor
   - Ejecutado exitosamente

2. `/Database/StoredProcedures/sp_Calcular_RMF_Activos_Nacionales_v5_SH.sql`
   - Nueva versión del SP con cálculos SH
   - Ejecutado exitosamente

3. `/CAMBIOS_SAFE_HARBOR.md` (este archivo)
   - Documentación de cambios

### Modificados

- **Tabla `Calculo_RMF`:** 9 columnas agregadas
- **SP `sp_Calcular_RMF_Activos_Nacionales`:** Actualizado a v5.0

---

## Commits GitHub

**Repositorio:** `earaizapowerera/ActifSafeHarbor`

**Commit 1:**
```
d615b8d - Agregar cálculos Safe Harbor con INPC de junio
- ALTER TABLE script para agregar 9 columnas Safe Harbor
- SP v5 actualizado con cálculo paralelo Fiscal + Safe Harbor
```

**Commit 2:**
```
5663124 - Fix: Corregir filtros INPC2 en SP Safe Harbor
- Eliminar filtro Id_Tipo_Dep (columna no existe en INPC2)
- Agregar filtro Id_Grupo_Simulacion = 8
```

---

## Ejecución en Base de Datos

**Base de datos:** `Actif_RMF` en `dbdev.powerera.com`

### Paso 1: Columnas agregadas ✅

```sql
sqlcmd -i ALTER_Calculo_RMF_Add_SafeHarbor_Columns.sql
```

**Resultado:**
```
Columna INPC_SH_Junio agregada
Columna Factor_SH agregada
Columna Saldo_SH_Actualizado agregada
Columna Dep_SH_Actualizada agregada
Columna Valor_SH_Promedio agregada
Columna Proporcion_SH agregada
Columna Saldo_SH_Fiscal_Hist agregada
Columna Saldo_SH_Fiscal_Act agregada
Columna Valor_SH_Reportable agregada
```

### Paso 2: SP actualizado ✅

```sql
sqlcmd -i sp_Calcular_RMF_Activos_Nacionales_v5_SH.sql
```

**Resultado:**
```
SP sp_Calcular_RMF_Activos_Nacionales v5.0-SAFE-HARBOR actualizado
```

---

## Próximos Pasos

### Para usar el nuevo cálculo:

1. **Ejecutar ETL** (sin cambios):
   ```bash
   cd ETL_NET/ActifRMF.ETL
   dotnet run 188 2024
   ```

2. **Ejecutar cálculo de Nacionales** (ahora incluye Safe Harbor):
   ```sql
   EXEC sp_Calcular_RMF_Activos_Nacionales 188, 2024
   ```

3. **Ejecutar actualización INPC Fiscal** (opcional, solo actualiza columnas fiscales):
   ```bash
   cd Database/ActualizarINPC
   dotnet run 188 2024
   ```

4. **Consultar resultados:**
   ```sql
   -- Ver columnas FISCALES
   SELECT TOP 10
       ID_NUM_ACTIVO,
       Valor_Reportable_MXN,  -- Fiscal
       INPCUtilizado,         -- Variable según SAT
       Factor_Actualizacion_Saldo
   FROM Calculo_RMF
   WHERE Tipo_Activo = 'Nacional';

   -- Ver columnas SAFE HARBOR
   SELECT TOP 10
       ID_NUM_ACTIVO,
       Valor_SH_Reportable,   -- Safe Harbor
       INPC_SH_Junio,         -- Junio (fijo)
       Factor_SH
   FROM Calculo_RMF
   WHERE Tipo_Activo = 'Nacional';
   ```

---

## Comparación de Resultados

**Ejemplo esperado para activo TODO EL AÑO:**

| Campo | Fiscal | Safe Harbor | ¿Igual? |
|-------|--------|-------------|---------|
| INPC utilizado | Junio (tabla INPCSegunMes) | Junio (directo) | ✅ SÍ |
| Factor | INPCUtilizado / INPCCompra | INPC_Junio / INPCCompra | ✅ SÍ |
| Resultado | Similar | Similar | ✅ SÍ |

**Ejemplo esperado para activo DADO DE BAJA en Agosto:**

| Campo | Fiscal | Safe Harbor | ¿Igual? |
|-------|--------|-------------|---------|
| INPC utilizado | Julio (mes anterior) | Junio (fijo) | ❌ NO |
| Factor | INPC_Jul / INPC_Compra | INPC_Jun / INPC_Compra | ❌ NO |
| Resultado | Menor actualización | Mayor actualización | ❌ NO |

**Ejemplo esperado para activo ADQUIRIDO en Marzo:**

| Campo | Fiscal | Safe Harbor | ¿Igual? |
|-------|--------|-------------|---------|
| INPC utilizado | Agosto (mes medio) | Junio (fijo) | ❌ NO |
| Factor | INPC_Ago / INPC_Mar | INPC_Jun / INPC_Mar | ❌ NO |
| Resultado | Mayor actualización | Menor actualización | ❌ NO |

---

## Notas Técnicas

1. **No se modificaron columnas fiscales existentes** - Los cálculos fiscales siguen funcionando igual
2. **Cálculos se ejecutan en paralelo** - Un solo SP calcula ambos (Fiscal + Safe Harbor)
3. **Safe Harbor es autónomo** - No depende del programa `ActualizarINPC`
4. **INPC de tabla local** - Usa `INPC2` local, no `actif_web_cima_dev`
5. **Id_Grupo_Simulacion = 8** - Filtro necesario para INPC2

---

**Fin del documento**
