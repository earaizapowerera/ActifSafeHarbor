# Cálculo de Depreciación - Sistema de Activos Fijos

## Índice

1. [Visión Macro](#1-visión-macro)
2. [Conceptos Fundamentales](#2-conceptos-fundamentales)
3. [Proceso de Cálculo](#3-proceso-de-cálculo)
4. [Fórmulas y Algoritmos](#4-fórmulas-y-algoritmos)
5. [Casos Especiales](#5-casos-especiales)
6. [Detalles de Implementación](#6-detalles-de-implementación)

---

## 1. Visión Macro

### 1.1 Propósito del Sistema

El sistema calcula la **depreciación mensual** de activos fijos para múltiples compañías, permitiendo depreciar el mismo activo bajo **4 esquemas diferentes simultáneamente**:

1. **Financiera** (Libros contables internos)
2. **Fiscal** (Declaraciones de impuestos)
3. **USGAAP/Revaluada** (Reportes corporativos internacionales)
4. **Cálculo 4** (Análisis especiales, inflación, etc.)

### 1.2 Flujo General

```
┌─────────────────┐
│  Catálogos y    │
│  Configuración  │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Registro de     │
│ Activos         │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Stored Procedure│
│ usp_calculo     │
│ enrique         │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Tabla calculo   │
│ (Resultados)    │
└─────────────────┘
```

### 1.3 Ejecución Mensual

El proceso se ejecuta **una vez por mes** para cada tipo de depreciación:

```
Enero 2024, Tipo Dep. Financiera → Calcula todos los activos
Enero 2024, Tipo Dep. Fiscal     → Calcula todos los activos
Enero 2024, Tipo Dep. USGAAP     → Calcula todos los activos
Enero 2024, Tipo Dep. Cálculo 4  → Calcula todos los activos

Febrero 2024, Tipo Dep. Financiera → ...
```

### 1.4 Resultado

Para cada activo en cada mes se genera un registro en la tabla `calculo` con:

- **Depreciación del mes** (MENSUAL_HISTORICA)
- **Depreciación acumulada del ejercicio** (EJERCICIO_HISTORICA)
- **Depreciación acumulada total** (ACUMULADO_HISTORICA)
- Valor de adquisición, factores, ajustes, etc.

---

## 2. Conceptos Fundamentales

### 2.1 Sistema de Slots (AplicaFiscal)

Cada tipo de depreciación tiene un valor `AplicaFiscal` (0-3) que determina qué "slot" de campos utilizar:

| AplicaFiscal | Slot | Campos de Costo | Campos de % | Fecha Inicio |
|--------------|------|-----------------|-------------|--------------|
| 0 | 1 | COSTO_ADQUISICION | DEPR_FINANCIERA_1/2 | FECHA_INIC_DEPREC |
| 1 | 2 | COSTO_REVALUADO | DEPR_FISCAL_1/2 | FECHA_INIC_DEPREC2 |
| 2 | 3 | COSTO_REEXPRESADO | DEPR_REVALUADA_1/2 | FECHA_INIC_DEPREC3 |
| 3 | 4 | COSTO_CALCULO4 | DEPR_CALCULO4_1/2 | FECHA_INIC_DEPREC4 |

### 2.2 Porcentaje de Depreciación

El porcentaje puede venir de **dos fuentes**:

#### A) Porcentaje Individual del Activo
Si el activo tiene un valor > 0 en:
- `DEPR_FINANCIERA_1` / `DEPR_FINANCIERA_2` (para AplicaFiscal=0)
- `DEPR_FISCAL_1` / `DEPR_FISCAL_2` (para AplicaFiscal=1)
- `DEPR_REVALUADA_1` / `DEPR_REVALUADA_2` (para AplicaFiscal=2)
- `DEPR_CALCULO4_1` / `DEPR_CALCULO4_2` (para AplicaFiscal=3)

Se usa ese porcentaje.

#### B) Porcentaje de la Tabla Catálogo
Si el activo tiene 0 o NULL en los campos anteriores, se busca en la tabla `porcentaje_depreciacion`:

```sql
SELECT PORC_BENEFICIO, PORC_SEGUNDO_ANO
FROM porcentaje_depreciacion
WHERE ID_TIPO_DEP = @ID_TIPO_DEP
  AND ID_TIPO_ACTIVO = activo.ID_TIPO_ACTIVO
  AND ID_SUBTIPO_ACTIVO = activo.ID_SUBTIPO_ACTIVO
  AND FECHA_INICIO <= @FechaActual
  AND (FECHA_FIN IS NULL OR FECHA_FIN >= @FechaActual)
```

- **PORC_BENEFICIO**: Se usa en el primer año de vida del activo
- **PORC_SEGUNDO_ANO**: Se usa del segundo año en adelante

### 2.3 Valor Base de Depreciación

Según el slot (AplicaFiscal), se toma uno de los costos:

```sql
CASE
    WHEN @AplicaFiscal = 0 THEN activo.COSTO_ADQUISICION
    WHEN @AplicaFiscal = 1 THEN activo.COSTO_REVALUADO
    WHEN @AplicaFiscal = 2 THEN activo.COSTO_REEXPRESADO
    WHEN @AplicaFiscal = 3 THEN activo.COSTO_CALCULO4
END
```

### 2.4 Valor Residual

Si se activa el parámetro `@AplicaResidual = 1`, se resta el valor residual del costo base:

```
Valor a Depreciar = Costo Base - Valor Residual
```

Si `@AplicaResidual = 0`, se deprecia el costo base completo.

### 2.5 Depreciación Acumulada

El cálculo mensual debe considerar la depreciación acumulada hasta el mes anterior:

```
Depreciación Acumulada Anterior = calculo.ACUMULADO_HISTORICA (mes anterior)
                                + ajustes.importeajuste (si hay)
```

---

## 3. Proceso de Cálculo

### 3.1 Parámetros de Entrada

El stored procedure `usp_CALCULOENRIQUE` recibe:

```sql
@IdCompania         INT,        -- Compañía a calcular
@ID_TIPO_DEP        INT,        -- Tipo de depreciación (1=Financiera, 2=Fiscal, etc.)
@Anio               INT,        -- Año del cálculo (ej: 2024)
@Mes                INT,        -- Mes del cálculo (1-12)
@Id_Grupo_Simulacion INT,       -- Grupo de simulación (para escenarios)
@AplicaResidual     INT,        -- 1=Aplica valor residual, 0=No aplica
@AplicaPerpetua     INT,        -- 1=Deprecia perpetuamente, 0=Detiene al llegar a 100%
@AplicaFiscal       INT         -- Slot a utilizar (0-3)
```

### 3.2 Validaciones Iniciales

1. **Obtener AplicaFiscal del tipo de depreciación**:
   ```sql
   SELECT @aplicafiscal = AplicaFiscal
   FROM tipo_depreciacion
   WHERE id_tipo_dep = @id_tipo_dep
   ```

2. **Verificar periodos cerrados**:
   - No se puede calcular un mes/año que ya está cerrado contablemente
   ```sql
   SELECT @AnioCierre = MAX(anio) FROM PeriodosCerrados WHERE id_compania = @idcompania
   SELECT @MesCierre = MAX(mes) FROM PeriodosCerrados WHERE anio = @AnioCierre ...

   IF @aniocierre > @anio OR (@aniocierre = @anio AND @mescierre >= @Mes)
       RETURN  -- No calcular
   ```

3. **Calcular fechas del periodo**:
   ```sql
   @FechaCorriente = '2024-03-01'  -- Primer día del mes
   @ULTDIAMESANT   = '2024-02-29'  -- Último día del mes anterior
   @ULTDIA         = '2024-03-31'  -- Último día del mes actual
   ```

### 3.3 Paso 1: Acumulados del Mes Anterior

Se ejecuta `usp_actif_acumMesAnterior` para asegurar que los acumulados del mes anterior estén correctos.

### 3.4 Paso 2: Detección de Ajustes Automáticos

Se detectan activos que requieren recálculo automático por:

#### A) Cambio en el Monto Original de Inversión (MOI)

Si el valor de adquisición cambió entre el mes anterior y el mes actual:

```sql
abs(activo.COSTO_xxx - calculo_mes_anterior.VALOR_ADQUISICION) > 0.05
```

**Excepciones**: No se recalcula si:
- El cambio fue por un **split** del activo
- Existe una fecha de forzamiento en el mes actual

**Acción**: Se ejecuta `usp_chedRecalcula` para ajustar retroactivamente.

#### B) Activos Capturados Retroactivamente

Activos que:
- Se capturaron este mes (FECHA_ALTA = mes actual)
- Pero su fecha de inicio de depreciación es anterior al mes actual
- Y no tienen forzamiento

**Acción**: Se recalcula retroactivamente.

### 3.5 Paso 3: Detección de Cambio de Porcentaje

Se ejecuta `usp_detectaCambioPorcentaje` para identificar activos cuyo porcentaje de depreciación cambió (por cambio en la tabla `porcentaje_depreciacion`).

### 3.6 Paso 4: Borrar Cálculos Previos del Mes

```sql
DELETE calculo
WHERE ID_ANO = @ANIO
  AND ID_MES = @MES
  AND ID_TIPO_DEP = @ID_TIPO_DEP
  AND ID_COMPANIA = @IdCompania
  AND activo.id_grupo_simulacion = @id_grupo_simulacion
```

Esto permite recalcular el mes sin duplicados.

### 3.7 Paso 5: Inserción del Cálculo Principal

Se inserta un registro en `calculo` por cada activo, con la fórmula de depreciación mensual.

---

## 4. Fórmulas y Algoritmos

### 4.1 Fórmula de Depreciación Mensual

La depreciación mensual se calcula como el **menor** entre:

1. **Remanente por depreciar**
2. **Depreciación calculada del mes**

```
MENSUAL_HISTORICA = MIN(Remanente, Depreciacion_Del_Mes)
```

### 4.2 Cálculo del Remanente

```sql
Remanente = Valor_A_Depreciar - Acumulado_Anterior - Ajustes

Donde:
  Valor_A_Depreciar = CASE
                        WHEN @AplicaResidual = 1
                          THEN Costo_Base - Valor_Residual
                        ELSE Costo_Base
                      END

  Costo_Base = CASE @AplicaFiscal
                 WHEN 0 THEN COSTO_ADQUISICION
                 WHEN 1 THEN COSTO_REVALUADO
                 WHEN 2 THEN COSTO_REEXPRESADO
                 WHEN 3 THEN COSTO_CALCULO4
               END

  Acumulado_Anterior = ISNULL(calculo_mes_anterior.ACUMULADO_HISTORICA, 0)

  Ajustes = ISNULL(ajustes.importeajuste, 0)
```

### 4.3 Cálculo de la Depreciación del Mes

```sql
Depreciacion_Del_Mes = (Porcentaje_Anual / 12 / 100) * Base_Calculo

Donde:
  Porcentaje_Anual = CASE
                       WHEN activo.DEPR_xxx_1 IS NOT NULL AND activo.DEPR_xxx_1 > 0
                         THEN activo.DEPR_xxx_1  -- Porcentaje individual
                       ELSE
                         porcentaje_depreciacion.PORC_SEGUNDO_ANO  -- Catálogo
                     END

  Base_Calculo = CASE
                   WHEN @AplicaResidual = 1
                     THEN Costo_Base - Valor_Residual
                   ELSE Costo_Base
                 END
```

**Nota**: El porcentaje se divide entre 12 para obtener la depreciación mensual, y entre 100 para convertir de porcentaje a decimal.

### 4.4 Lógica MIN(Remanente, Depreciacion_Del_Mes)

```sql
CASE
  WHEN Remanente < Depreciacion_Del_Mes
    THEN Remanente  -- Ya casi está totalmente depreciado
  ELSE
    Depreciacion_Del_Mes  -- Depreciación normal del mes
END
```

Esta lógica asegura que:
- No se deprecie más del 100% del activo
- El último mes de depreciación solo deprecie lo que falta

### 4.5 Ejemplo Numérico

**Datos del Activo**:
- Costo: $100,000
- Porcentaje anual: 25%
- Depreciación mensual normal: $100,000 × 25% / 12 = $2,083.33
- Vida útil: 4 años (48 meses)

**Mes 1**:
```
Remanente = $100,000 - $0 = $100,000
Depreciacion_Del_Mes = $2,083.33
MENSUAL = MIN($100,000, $2,083.33) = $2,083.33
ACUMULADO = $2,083.33
```

**Mes 2**:
```
Remanente = $100,000 - $2,083.33 = $97,916.67
Depreciacion_Del_Mes = $2,083.33
MENSUAL = MIN($97,916.67, $2,083.33) = $2,083.33
ACUMULADO = $4,166.66
```

**Mes 47**:
```
Remanente = $100,000 - $95,833.33 = $4,166.67
Depreciacion_Del_Mes = $2,083.33
MENSUAL = MIN($4,166.67, $2,083.33) = $2,083.33
ACUMULADO = $97,916.66
```

**Mes 48 (último)**:
```
Remanente = $100,000 - $97,916.66 = $2,083.34
Depreciacion_Del_Mes = $2,083.33
MENSUAL = MIN($2,083.34, $2,083.33) = $2,083.33
ACUMULADO = $100,000.00 (totalmente depreciado)
```

### 4.6 Depreciación Acumulada Total

```sql
ACUMULADO_HISTORICA = ACUMULADO_MES_ANTERIOR + MENSUAL_HISTORICA + AJUSTES
```

### 4.7 Depreciación del Ejercicio

```sql
EJERCICIO_HISTORICA = Suma de MENSUAL_HISTORICA del año actual
```

Se calcula sumando las depreciaciones mensuales desde Enero hasta el mes actual del año en curso.

---

## 5. Casos Especiales

### 5.1 Valor Residual

Si `@AplicaResidual = 1` y el activo tiene `VALOR_RESIDUAL`:

```
Ejemplo:
- Costo: $100,000
- Valor Residual: $10,000
- Valor a Depreciar: $90,000

La depreciación se calcula sobre $90,000, no sobre $100,000.
El activo nunca depreciará los últimos $10,000.
```

### 5.2 Forzamientos (FECHA_FORZA / MONTO_FORZA)

Si el activo tiene una fecha de forzamiento en el mes actual:

```sql
FECHA_FORZA1 = '2024-03-15'  (para AplicaFiscal = 0)
```

El sistema **NO** aplica ajustes automáticos por cambio de MOI, respetando el ajuste manual.

El forzamiento permite:
- Ajustar manualmente la depreciación de un activo
- Corregir errores sin recalcular todo el histórico
- Aplicar reglas especiales en fechas específicas

### 5.3 Splits de Activos

Cuando un activo se divide en varios (split):

```
Activo Original: ID=1000, Costo=$100,000, Dep.Acum=$50,000

Split en 2 activos:
- Activo A: ID=1001, Costo=$60,000, Dep.Acum=$30,000 (60% del original)
- Activo B: ID=1002, Costo=$40,000, Dep.Acum=$20,000 (40% del original)
```

El sistema:
1. Registra en `actif_activossplits` la relación
2. Distribuye la depreciación acumulada proporcionalmente
3. No aplica ajustes automáticos a los activos del split

### 5.4 Activos sin Inicio de Depreciación

Si el activo no tiene `FECHA_INIC_DEPREC` (según el slot):

```sql
activo.FECHA_INIC_DEPREC IS NULL  -- para AplicaFiscal=0
```

**No se deprecia ese mes**. El registro en `calculo` se crea con `MENSUAL_HISTORICA = 0`.

### 5.5 Activos con Fecha Inicio de Depreciación Futura

Si la fecha de inicio de depreciación es posterior al mes actual:

```sql
activo.FECHA_INIC_DEPREC > @ULTDIA  -- '2024-05-01' > '2024-03-31'
```

**No se deprecia ese mes**. Se esperará hasta que llegue el mes de inicio.

### 5.6 Activos Totalmente Depreciados

Cuando un activo ya alcanzó el 100% de depreciación:

```sql
ACUMULADO_HISTORICA >= (Costo_Base - Valor_Residual)
```

Si `@AplicaPerpetua = 0`:
- **No se deprecia más**
- `MENSUAL_HISTORICA = 0`

Si `@AplicaPerpetua = 1`:
- Continúa depreciando (puede superar el 100%)
- Útil para ciertos análisis fiscales

### 5.7 Depreciación con INPC (Inflación)

Para cálculos de reexpresión (común en COSTO_REEXPRESADO):

```sql
Valor_Reexpresado = Costo_Original × (INPC_Actual / INPC_Compra)

Depreciacion_Reexpresada = Depreciacion_Normal × Factor_INPC
```

Los campos relevantes en `calculo`:
- `INPC_COMPRA`: INPC a la fecha de compra
- `INPC_UTILIZADO`: INPC utilizado en el mes actual
- `INPCInicDeprec`: INPC al inicio de depreciación
- `INPCMedio`: INPC promedio del periodo

### 5.8 Primer Año vs. Años Siguientes

**Primer año de vida**:
- Se usa `DEPR_xxx_1` o `PORC_BENEFICIO`
- Puede tener un porcentaje diferente (ej: beneficio fiscal del 50% en año 1)

**Años siguientes**:
- Se usa `DEPR_xxx_2` o `PORC_SEGUNDO_ANO`
- Porcentaje normal (ej: 25% anual)

La distinción se hace comparando:
```sql
DATEDIFF(YEAR, FECHA_INIC_DEPREC, @FechaCorriente) = 0  -- Primer año
```

---

## 6. Detalles de Implementación

### 6.1 Estructura del Stored Procedure

```
usp_CALCULOENRIQUE
│
├─ 1. Validaciones
│   ├─ Obtener AplicaFiscal
│   ├─ Verificar periodos cerrados
│   └─ Calcular fechas del periodo
│
├─ 2. Acumulados mes anterior
│   └─ exec usp_actif_acumMesAnterior
│
├─ 3. Ajustes automáticos por cambio MOI
│   ├─ Detectar cambios en valor de adquisición
│   ├─ Excluir splits
│   ├─ Excluir forzamientos
│   └─ exec usp_chedRecalcula (para cada activo)
│
├─ 4. Ajustes por cambio de porcentaje
│   └─ exec usp_detectaCambioPorcentaje
│
├─ 5. Borrar cálculos previos
│   └─ DELETE FROM calculo WHERE ...
│
├─ 6. Insertar nuevos cálculos
│   └─ INSERT INTO calculo (SELECT ...)
│       ├─ Calcular MENSUAL_HISTORICA
│       ├─ Calcular ACUMULADO_HISTORICA
│       └─ Calcular EJERCICIO_HISTORICA
│
└─ 7. Post-procesos
    ├─ Actualizar flags
    └─ Generar bitácora
```

### 6.2 Query Principal de Inserción

La parte más importante del stored procedure es el INSERT masivo:

```sql
INSERT INTO calculo (
    ID_NUM_ACTIVO, ID_COMPANIA, ID_ANO, ID_MES, ID_TIPO_DEP,
    MENSUAL_HISTORICA, ACUMULADO_HISTORICA, EJERCICIO_HISTORICA,
    VALOR_ADQUISICION, FECHA_CORTE, ...
)
SELECT
    a.id_num_activo,
    a.id_compania,
    @ANIO,
    @MES,
    @id_tipo_dep,

    -- MENSUAL_HISTORICA
    CEILING(100 * CASE
        WHEN (Valor_A_Depreciar - Acumulado_Anterior - Ajustes) < Depreciacion_Del_Mes
            THEN (Valor_A_Depreciar - Acumulado_Anterior - Ajustes)
        ELSE
            ROUND(Depreciacion_Del_Mes, 2)
    END) / 100,

    -- ACUMULADO_HISTORICA
    ROUND(Acumulado_Anterior + Ajustes + MENSUAL_HISTORICA, 2),

    -- EJERCICIO_HISTORICA
    CASE
        WHEN @MES = 1 THEN MENSUAL_HISTORICA
        ELSE Ejercicio_Anterior + MENSUAL_HISTORICA
    END,

    -- VALOR_ADQUISICION
    CASE
        WHEN @aplicafiscal = 0 THEN a.COSTO_ADQUISICION
        WHEN @aplicafiscal = 1 THEN a.COSTO_REVALUADO
        WHEN @aplicafiscal = 2 THEN a.COSTO_REEXPRESADO
        WHEN @aplicafiscal = 3 THEN a.COSTO_CALCULO4
    END,

    @ULTDIA,  -- FECHA_CORTE
    ...

FROM activo a
LEFT JOIN (
    SELECT id_num_activo, ACUMULADO_HISTORICA, EJERCICIO_HISTORICA
    FROM calculo
    WHERE id_tipo_dep = @ID_TIPO_DEP
      AND id_ano = @ANIO
      AND id_mes = @MES - 1
) ACUM ON a.id_num_activo = ACUM.id_num_activo
LEFT JOIN (
    SELECT id_num_activo, SUM(importeajuste) as importeajuste
    FROM ajustes
    WHERE id_tipo_dep = @ID_TIPO_DEP
      AND id_ano = @ANIO
      AND id_mes = @MES
) ajustes ON a.id_num_activo = ajustes.id_num_activo
LEFT JOIN porcentaje_depreciacion pd ON ...
WHERE a.ID_COMPANIA = @IdCompania
  AND a.id_grupo_simulacion = @id_grupo_simulacion
```

### 6.3 Funciones Auxiliares

#### usp_chedRecalcula

Recalcula retroactivamente un activo cuando hubo un cambio en el MOI:

```sql
exec usp_chedRecalcula
    @id_num_activo = 12345,
    @fecha_hasta = '2024-03-31',
    @id_tipo_dep = 1,
    @motivo = 'Cambio de MOI',
    @metodo = 3
```

**Proceso**:
1. Borra los cálculos desde la fecha del cambio hasta @fecha_hasta
2. Recalcula mes por mes
3. Registra ajuste en tabla `ajustes`

#### usp_detectaCambioPorcentaje

Detecta activos cuyo porcentaje en `porcentaje_depreciacion` cambió:

```sql
exec usp_detectaCambioPorcentaje
    @Anio = 2024,
    @Mes = 3,
    @IdTipoDep = 1,
    @IdCompania = 1,
    @UltDiaMesAnt = '2024-02-29',
    @IdEdificio = NULL,
    @IdNumActivo = NULL
```

**Proceso**:
1. Compara porcentaje usado en mes anterior vs. porcentaje actual en catálogo
2. Si cambió, marca el activo para recálculo
3. Ejecuta `usp_chedRecalcula`

#### usp_actif_acumMesAnterior

Asegura que los acumulados del mes anterior estén correctos:

```sql
exec usp_actif_acumMesAnterior
    @idcompania = 1,
    @ID_TIPO_DEP = 1,
    @anio = 2024,
    @mes = 3,
    @IdEdificio = NULL,
    @IdNumActivo = NULL
```

**Proceso**:
1. Lee los cálculos del mes anterior
2. Verifica sumas y acumulados
3. Corrige inconsistencias si las hay

### 6.4 Tabla de Ajustes

La tabla `ajustes` almacena correcciones manuales o automáticas:

| Campo | Descripción |
|-------|-------------|
| id_num_activo | Activo ajustado |
| id_tipo_dep | Tipo de depreciación |
| id_ano | Año del ajuste |
| id_mes | Mes del ajuste |
| importeajuste | Monto del ajuste (puede ser negativo) |
| motivo | Razón del ajuste |
| metodo | Tipo de ajuste (1=Manual, 2=Split, 3=Retro/CambioMOI) |

### 6.5 Control de Concurrencia

El sistema usa:
- Campo `rv` (timestamp) en todas las tablas para detectar cambios concurrentes
- Locks optimistas
- Transacciones para garantizar consistencia

### 6.6 Bitácora

Cada ejecución del stored procedure registra en tabla `bitacora`:

```sql
INSERT INTO bitacora (data, fechacaptura)
VALUES (
    CONCAT('USP_Calculo_ENRIQUE tipodep=', @id_tipo_dep,
           ',id_aplicafiscal', @aplicafiscal,
           ' Id_Compania=', @idcompania,
           ' Id_Mes=', @mes),
    GETDATE()
)
```

---

## 7. Flujo Completo - Ejemplo Detallado

### Escenario

**Compañía**: CIMA (ID=1)
**Tipo de Depreciación**: Financiera (ID=1, AplicaFiscal=0)
**Periodo**: Marzo 2024
**Activo**: Computadora HP (ID_NUM_ACTIVO=12345)

### Datos del Activo

```
ID_NUM_ACTIVO: 12345
ID_TIPO_ACTIVO: 2813 (Equipo de Cómputo)
ID_SUBTIPO_ACTIVO: 2813
COSTO_ADQUISICION: $25,000.00
FECHA_INIC_DEPREC: 01/01/2024
DEPR_FINANCIERA_1: NULL (usa catálogo)
DEPR_FINANCIERA_2: NULL (usa catálogo)
VALOR_RESIDUAL: $0
```

### Datos del Catálogo

```sql
SELECT * FROM porcentaje_depreciacion
WHERE ID_TIPO_DEP = 1  -- Financiera
  AND ID_TIPO_ACTIVO = 2813
  AND ID_SUBTIPO_ACTIVO = 2813

Resultado:
PORC_BENEFICIO: 25.00
PORC_SEGUNDO_ANO: 25.00
```

### Ejecución

```sql
EXEC usp_CALCULOENRIQUE
    @IdCompania = 1,
    @ID_TIPO_DEP = 1,
    @Anio = 2024,
    @Mes = 3,
    @Id_Grupo_Simulacion = 0,
    @AplicaResidual = 0,
    @AplicaPerpetua = 0,
    @AplicaFiscal = 0
```

### Paso a Paso

#### 1. Validaciones
```
✓ AplicaFiscal = 0 (del tipo_depreciacion ID=1)
✓ No hay periodos cerrados que impidan calcular Marzo 2024
✓ Fechas:
  - @FechaCorriente = 2024-03-01
  - @ULTDIAMESANT = 2024-02-29
  - @ULTDIA = 2024-03-31
```

#### 2. Acumulados Mes Anterior (Febrero 2024)

Buscar en `calculo`:
```sql
SELECT ACUMULADO_HISTORICA, EJERCICIO_HISTORICA
FROM calculo
WHERE ID_NUM_ACTIVO = 12345
  AND ID_TIPO_DEP = 1
  AND ID_ANO = 2024
  AND ID_MES = 2

Resultado:
ACUMULADO_HISTORICA: $4,166.66
EJERCICIO_HISTORICA: $4,166.66
```

#### 3. Detección de Cambios

No hay cambios en:
- Valor de adquisición (sigue siendo $25,000)
- Porcentaje (sigue siendo 25%)

No se aplican ajustes.

#### 4. Cálculo del Mes Actual

**Porcentaje a usar**:
```
DEPR_FINANCIERA_1 = NULL
→ Usar porcentaje_depreciacion.PORC_SEGUNDO_ANO = 25%
  (no es primer año porque DATEDIFF(MONTH, 2024-01-01, 2024-03-01) >= 12 meses → FALSE)

Espera, es 2024-01-01 a 2024-03-01 = 2 meses, SÍ es primer año.
→ Usar PORC_BENEFICIO = 25%
```

**Depreciación del mes**:
```
Depreciacion_Del_Mes = ($25,000 × 25% / 12)
                     = ($25,000 × 0.25 / 12)
                     = $520.83
```

**Remanente**:
```
Remanente = $25,000 - $4,166.66 - $0 (sin ajustes)
          = $20,833.34
```

**MENSUAL_HISTORICA**:
```
MENSUAL_HISTORICA = MIN($20,833.34, $520.83) = $520.83
```

**ACUMULADO_HISTORICA**:
```
ACUMULADO_HISTORICA = $4,166.66 + $520.83 = $4,687.49
```

**EJERCICIO_HISTORICA**:
```
EJERCICIO_HISTORICA = $4,166.66 + $520.83 = $4,687.49
(Enero + Febrero + Marzo del 2024)
```

#### 5. Inserción en Tabla calculo

```sql
INSERT INTO calculo (
    ID_NUM_ACTIVO, ID_COMPANIA, ID_ANO, ID_MES, ID_TIPO_DEP,
    MENSUAL_HISTORICA, ACUMULADO_HISTORICA, EJERCICIO_HISTORICA,
    VALOR_ADQUISICION, FECHA_CORTE, ...
) VALUES (
    12345,
    1,
    2024,
    3,
    1,
    520.83,
    4687.49,
    4687.49,
    25000.00,
    '2024-03-31',
    ...
)
```

#### 6. Resultado Final

| Mes | MENSUAL | ACUMULADO | EJERCICIO |
|-----|---------|-----------|-----------|
| Enero 2024 | $520.83 | $520.83 | $520.83 |
| Febrero 2024 | $520.83 | $1,041.66 | $1,041.66 |
| **Marzo 2024** | **$520.83** | **$4,687.49** | **$4,687.49** |
| ... | ... | ... | ... |
| Diciembre 2024 | $520.83 | $6,250.00 | $6,250.00 |
| Enero 2025 | $520.83 | $6,770.83 | $520.83 |

**Nota**: En Enero 2025, EJERCICIO_HISTORICA se reinicia porque es un nuevo ejercicio fiscal.

---

## 8. Consideraciones de Performance

### 8.1 Optimizaciones Aplicadas

1. **Inserción masiva**: Un solo INSERT con todos los activos de la compañía
2. **LEFT JOINs eficientes**: Uso de subconsultas indexadas
3. **Desnormalización**: Campos como ID_CENTRO_COSTO, ID_EDIFICIO en `calculo`
4. **Cálculo incremental**: Solo se calcula un mes a la vez, usando el mes anterior

### 8.2 Índices Recomendados

```sql
-- Tabla calculo
CREATE INDEX IX_calculo_lookup
ON calculo(ID_NUM_ACTIVO, ID_TIPO_DEP, ID_ANO, ID_MES)

-- Tabla activo
CREATE INDEX IX_activo_compania_grupo
ON activo(ID_COMPANIA, id_grupo_simulacion)

-- Tabla porcentaje_depreciacion
CREATE INDEX IX_porcen_lookup
ON porcentaje_depreciacion(ID_TIPO_DEP, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO)
```

### 8.3 Tiempos de Ejecución Esperados

Para una compañía con **10,000 activos**:
- Cálculo normal (sin ajustes): **5-10 segundos**
- Cálculo con ajustes automáticos (100 activos): **15-30 segundos**
- Recálculo retroactivo completo: **1-2 minutos**

---

## 9. Casos de Uso Comunes

### 9.1 Alta de Activo Nuevo

```
1. Capturar activo en tabla activo
2. Establecer COSTO_ADQUISICION = $X
3. Establecer FECHA_INIC_DEPREC = fecha de inicio
4. Ejecutar usp_CALCULOENRIQUE para el mes actual
5. El activo aparecerá en calculo desde este mes en adelante
```

### 9.2 Cambio de Valor de Activo

```
1. Actualizar COSTO_ADQUISICION (u otro costo según slot)
2. Ejecutar usp_CALCULOENRIQUE
3. El sistema detectará el cambio automáticamente
4. Ejecutará usp_chedRecalcula retroactivamente
5. Recalculará desde el mes del cambio hasta ahora
```

### 9.3 Corrección Manual con Forzamiento

```
1. Establecer FECHA_FORZA1 = fecha del ajuste
2. Establecer PORCE_FORZA1 o MONTO_FORZA1 = ajuste deseado
3. Ejecutar usp_CALCULOENRIQUE
4. El sistema NO aplicará ajustes automáticos
5. Respetará el forzamiento manual
```

### 9.4 Cierre de Mes

```
1. Ejecutar usp_CALCULOENRIQUE para todas las compañías y tipos de dep.
2. Revisar reportes de depreciación
3. Validar totales
4. Insertar registro en PeriodosCerrados
5. A partir de ese momento, ese mes no se puede recalcular
```

### 9.5 Split de Activo

```
1. Crear nuevos activos (A y B) a partir del original
2. Establecer costos proporcionalmente
3. Registrar en actif_activossplits:
   - IdNumActivoAnt = ID del activo original
   - IdNumActivoNuevo = ID del nuevo activo
   - Proporcion_Split = porcentaje del split
4. Ejecutar usp_CALCULOENRIQUE
5. Los nuevos activos tendrán depreciación proporcional desde el split
```

---

## 10. Troubleshooting

### 10.1 Activo No Aparece en Cálculo

**Posibles causas**:
- No tiene `FECHA_INIC_DEPREC` configurada
- La fecha de inicio es posterior al mes actual
- No tiene costo base (COSTO_xxx = NULL o 0)
- Pertenece a un `id_grupo_simulacion` diferente

**Solución**: Verificar estos campos en la tabla `activo`.

### 10.2 Depreciación Incorrecta

**Posibles causas**:
- Porcentaje incorrecto en `porcentaje_depreciacion` o en `activo.DEPR_xxx`
- Cambio de MOI no detectado
- Ajustes manuales en tabla `ajustes`
- Valor residual configurado

**Solución**: Revisar bitácora, tabla ajustes, y ejecutar con forzamiento si es necesario.

### 10.3 Recálculo No Se Ejecuta

**Posible causa**: Periodo ya cerrado en `PeriodosCerrados`

**Solución**: Abrir el periodo o contactar a administrador.

### 10.4 Depreciación Acumulada > 100%

**Posible causa**: `@AplicaPerpetua = 1` configurado

**Solución**: Cambiar a `@AplicaPerpetua = 0` si no se desea depreciar más del 100%.

---

## 11. Resumen Ejecutivo

### Cálculo en 3 Pasos

1. **Determinar el porcentaje**: Individual del activo o del catálogo
2. **Calcular depreciación mensual**: (Costo × % / 12) limitado por el remanente
3. **Actualizar acumulados**: Mensual, Ejercicio, Total

### Fórmula Simplificada

```
Depreciación Mensual = MIN(
    Remanente por Depreciar,
    (Costo Base × Porcentaje Anual / 12)
)
```

### Ejecución

```sql
EXEC usp_CALCULOENRIQUE @IdCompania, @ID_TIPO_DEP, @Anio, @Mes, ...
```

### Resultado

Registro en tabla `calculo` con:
- Depreciación del mes
- Acumulado total
- Acumulado del ejercicio
- Metadatos del cálculo

---

**Versión**: 1.0
**Fecha**: 2025-10-18
**Base de Datos**: actif_web_cima_dev
**Stored Procedure**: usp_CALCULOENRIQUE
