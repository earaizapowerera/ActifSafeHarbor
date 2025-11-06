# Reporte de Verificacion INPC - Sistema ActifRMF

**Fecha**: 2025-11-05
**Base de datos**: Actif_RMF en dbdev.powerera.com
**Usuario**: earaiza
**Stored Procedure Analizado**: sp_Actualizar_INPC_Nacionales v2.0

---

## PARTE 1: COMPARACION DE LOGICA INPC

### Algoritmo de Referencia: usp_CalculoINPCActivo (Sistema Actif Legacy)

Segun la documentacion del sistema legacy, la logica de calculo INPC debe implementar los siguientes casos:

1. **Antes de iniciar depreciacion**: Factor = 1.0, usar INPC_compra
2. **Completamente depreciado**:
   - Si tiene < 2 anos desde fin deprec: Usar tabla inpcdeprec con mes medio
   - Si tiene >= 2 anos: Usar INPC del mes de fin de depreciacion directamente
3. **Dado de baja**:
   - Si tiene < 2 anos desde baja: Usar tabla INPCbajas con mes anterior a la baja
   - Si tiene >= 2 anos: Usar INPC del mes anterior a la baja directamente
4. **Comprado en el ano actual**: Calcular mes medio con formula: `ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)`
5. **De anos anteriores, activo**: Usar tabla INPCSegunMes (diciembre → junio para Safe Harbor)

---

### Stored Procedure: sp_Actualizar_INPC_Nacionales

**Ubicacion**: `/Users/enrique/actifrmf/Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql`
**Version**: 2.0
**Lineas de codigo**: 346

---

## ANALISIS POR CASO

### CASO 1: Antes de iniciar depreciacion

**Requisito del algoritmo de referencia:**
- Condicion: El activo aun NO ha iniciado su depreciacion
- INPC a usar: INPC del mes de compra
- Factor: 1.0 (sin actualizacion)

**Implementacion en sp_Actualizar_INPC_Nacionales:**

```sql
-- Lineas 111-118
-- CASO 1: Antes de iniciar depreciacion
IF @Ano_Calculo < YEAR(@Fecha_Compra)
   OR (@Ano_Calculo = YEAR(@Fecha_Compra) AND 12 <= MONTH(@Fecha_Compra))
BEGIN
    SET @INPC_Utilizado = @INPC_Compra;
    SET @Factor = 1.0;
    SET @PasoINPC = 'inic';
END
```

**Status:** ✅ **IMPLEMENTADO CORRECTAMENTE**

**Analisis:**
- La condicion verifica si el ano de calculo es anterior al ano de compra
- O si estamos en el mismo ano de compra pero el activo se compro en diciembre o despues
- Asigna Factor = 1.0 como se requiere
- Usa INPC_Compra como INPC_Utilizado
- Marca el registro con 'inic' para identificacion

---

### CASO 2: Completamente depreciado

**Requisito del algoritmo de referencia:**
- Condicion: MOI = Dep_Acum_Inicio (totalmente depreciado)
- Si tiene < 2 anos desde fin deprec: Usar tabla `inpcdeprec` con mes medio
- Si tiene >= 2 anos: Usar INPC del mes de fin de depreciacion directamente

**Implementacion en sp_Actualizar_INPC_Nacionales:**

```sql
-- Lineas 119-155
-- CASO 2: Completamente depreciado
ELSE IF ABS(@MOI - @Dep_Acum_Inicio) < 1
BEGIN
    DECLARE @Mes_INPC_Utilizado INT;
    DECLARE @Ano_INPC_Utilizado INT;

    IF @Fecha_Baja IS NOT NULL
    BEGIN
        -- Usar mes anterior a la baja
        SET @Ano_INPC_Utilizado = YEAR(DATEADD(MONTH, -1, @Fecha_Baja));
        SET @Mes_INPC_Utilizado = MONTH(DATEADD(MONTH, -1, @Fecha_Baja));
        SET @PasoINPC = 'DepreciadoMesBaja';
    END
    ELSE
    BEGIN
        -- Usar junio del ano de calculo como mes medio
        SET @Ano_INPC_Utilizado = @Ano_Calculo;
        SET @Mes_INPC_Utilizado = 6;
        SET @PasoINPC = 'DepreciadoMesMedio';
    END

    SELECT @INPC_Utilizado = Indice
    FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
    WHERE Mes = @Mes_INPC_Utilizado
      AND Anio = @Ano_INPC_Utilizado
      AND Id_Pais = 1
      AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
END
```

**Status:** ⚠️ **IMPLEMENTACION PARCIAL CON DIFERENCIAS**

**Problemas identificados:**

1. **NO usa la tabla `inpcdeprec`**: El algoritmo de referencia especifica que debe usar la tabla `inpcdeprec` para determinar el mes INPC a utilizar cuando el activo esta completamente depreciado.

2. **NO implementa la regla de 2 anos**: No verifica si han pasado 2 anos desde el fin de depreciacion para decidir si usar la tabla auxiliar o el INPC directo.

3. **Logica simplificada**: En lugar de calcular la fecha de fin de depreciacion y verificar el tiempo transcurrido, usa dos heurísticas:
   - Si tiene fecha de baja: usa mes anterior a la baja
   - Si NO tiene fecha de baja: usa junio (mes medio del ano de calculo)

**Recomendaciones:**
- Agregar calculo de fecha de fin de depreciacion basado en la tasa de depreciacion
- Implementar la verificacion de 2 anos: `DATEDIFF(YEAR, @Fecha_Fin_Deprec, @Fecha_Calculo) >= 2`
- Si < 2 anos: consultar tabla `inpcdeprec` usando el mes de fin de depreciacion
- Si >= 2 anos: usar INPC del mes de fin de depreciacion directamente

---

### CASO 3: Dado de baja

**Requisito del algoritmo de referencia:**
- Condicion: FECHA_BAJA IS NOT NULL en el ano de calculo
- Si tiene < 2 anos desde baja: Usar tabla `INPCbajas` con mes anterior a la baja
- Si tiene >= 2 anos: Usar INPC del mes anterior a la baja directamente

**Implementacion en sp_Actualizar_INPC_Nacionales:**

```sql
-- Lineas 156-195
-- CASO 3: Dado de baja en el ano
ELSE IF @Fecha_Baja IS NOT NULL AND YEAR(@Fecha_Baja) = @Ano_Calculo
BEGIN
    DECLARE @Mes_Anterior_Baja INT = MONTH(DATEADD(MONTH, -1, @Fecha_Baja));
    DECLARE @Ano_Baja_INPC INT;
    DECLARE @Id_MesINPC INT;

    -- Buscar en tabla INPCbajas
    SELECT @Ano_Baja_INPC = YEAR(DATEADD(MONTH, -1, @Fecha_Baja)) + AnoINPC,
           @Id_MesINPC = Id_MesINPC
    FROM dbo.INPCbajas
    WHERE Id_Mes = @Mes_Anterior_Baja;

    IF @Ano_Baja_INPC IS NOT NULL AND @Id_MesINPC IS NOT NULL
    BEGIN
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Anio = @Ano_Baja_INPC
          AND Mes = @Id_MesINPC
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);
    END
    ELSE
    BEGIN
        -- Si no hay en tabla, usar mes anterior directamente
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Mes = @Mes_Anterior_Baja
          AND Anio = YEAR(DATEADD(MONTH, -1, @Fecha_Baja))
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);
    END

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
    SET @PasoINPC = 'baja';
END
```

**Status:** ⚠️ **IMPLEMENTACION PARCIAL CON DIFERENCIAS**

**Analisis:**

**Correcto:**
- ✅ Verifica que la fecha de baja sea en el ano de calculo
- ✅ Calcula el mes anterior a la baja correctamente
- ✅ Consulta la tabla `INPCbajas` para obtener el mapeo
- ✅ Tiene un fallback si no encuentra en la tabla auxiliar

**Problemas:**

1. **NO implementa la regla de 2 anos**: El algoritmo de referencia especifica que SOLO debe usar la tabla `INPCbajas` si han pasado MENOS de 2 anos desde la baja. Si han pasado 2 anos o mas, debe usar el INPC del mes anterior a la baja directamente (sin consultar la tabla).

2. **Condicion limitada**: Solo procesa bajas del ano actual (`YEAR(@Fecha_Baja) = @Ano_Calculo`), pero el algoritmo de referencia debe considerar bajas de anos anteriores tambien, verificando el tiempo transcurrido.

**Recomendaciones:**
- Remover la condicion `AND YEAR(@Fecha_Baja) = @Ano_Calculo`
- Agregar calculo: `DATEDIFF(YEAR, @Fecha_Baja, DATEFROMPARTS(@Ano_Calculo, 12, 31)) < 2`
- Si < 2 anos: usar tabla `INPCbajas`
- Si >= 2 anos: usar INPC del mes anterior a la baja directamente (sin tabla)

---

### CASO 4: Comprado en el ano actual

**Requisito del algoritmo de referencia:**
- Condicion: YEAR(FECHA_COMPRA) = Ano_Calculo
- Formula del mes medio: `ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)`
- INPC a usar: Del mes medio calculado

**Implementacion en sp_Actualizar_INPC_Nacionales:**

```sql
-- Lineas 196-216
-- CASO 4: Adquirido en el ano actual
ELSE IF YEAR(@Fecha_Compra) = @Ano_Calculo
BEGIN
    -- Formula SAT: mes_medio = ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)
    DECLARE @Mes_Medio INT;
    SET @Mes_Medio = ROUND((12.0 - (MONTH(@Fecha_Compra) - 1)) / 2.0, 0, 1) + (MONTH(@Fecha_Compra) - 1);

    SELECT @INPC_Utilizado = Indice
    FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
    WHERE Anio = @Ano_Calculo
      AND Mes = @Mes_Medio
      AND Id_Pais = 1
      AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
    SET @PasoINPC = 'misomoano';
END
```

**Status:** ✅ **IMPLEMENTADO CORRECTAMENTE**

**Analisis:**
- La condicion verifica correctamente que la compra sea en el ano de calculo
- La formula del mes medio es EXACTAMENTE la especificada en el algoritmo de referencia
- Usa el parametro `0, 1` en ROUND para redondear hacia arriba (ROUND_UP en SQL Server)
- Obtiene el INPC del mes medio calculado
- Calcula el factor correctamente
- Asegura que el factor nunca sea menor a 1.0

**Ejemplos de mes medio:**
- Comprado en enero (mes 1): `ROUND((12-0)/2, 0, 1) + 0 = 6` → Junio
- Comprado en julio (mes 7): `ROUND((12-6)/2, 0, 1) + 6 = 9` → Septiembre
- Comprado en octubre (mes 10): `ROUND((12-9)/2, 0, 1) + 9 = 11` → Noviembre

**Nota:** Hay un typo en el codigo: `SET @PasoINPC = 'misomoano'` deberia ser `'mismoano'`

---

### CASO 5: De anos anteriores, activo normal

**Requisito del algoritmo de referencia:**
- Condicion: YEAR(FECHA_COMPRA) < Ano_Calculo
- Usar tabla `INPCSegunMes` para mapear el mes de calculo al mes INPC
- Para Safe Harbor anual (mes de calculo = diciembre): usar mes INPC = junio

**Implementacion en sp_Actualizar_INPC_Nacionales:**

```sql
-- Lineas 217-245
-- CASO 5: De anos anteriores, activo normal
ELSE IF YEAR(@Fecha_Compra) < @Ano_Calculo
BEGIN
    DECLARE @MesINPC_SegunTabla INT;
    DECLARE @AnoINPC_SegunTabla INT;

    -- Buscar en tabla INPCSegunMes (para diciembre Safe Harbor = mes 6 = junio)
    SELECT @MesINPC_SegunTabla = MesINPC,
           @AnoINPC_SegunTabla = @Ano_Calculo + AnoINPC
    FROM dbo.INPCSegunMes
    WHERE MesCalculo = 12;  -- Safe Harbor anual usa diciembre

    IF @MesINPC_SegunTabla IS NOT NULL
    BEGIN
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Anio = @AnoINPC_SegunTabla
          AND Mes = @MesINPC_SegunTabla
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        IF @INPC_Utilizado IS NOT NULL
        BEGIN
            SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
            IF ISNULL(@Factor, 0) < 1 SET @Factor = 1;
        END
    END
    SET @PasoINPC = 'AnosAnteriores';
END
```

**Status:** ✅ **IMPLEMENTADO CORRECTAMENTE**

**Analisis:**
- Verifica correctamente que la compra sea de anos anteriores
- Consulta la tabla `INPCSegunMes` con MesCalculo = 12 (para Safe Harbor anual)
- La tabla devuelve MesINPC = 6 (junio) y AnoINPC = 0 (mismo ano de calculo)
- Calcula el ano INPC correctamente: `@Ano_Calculo + AnoINPC`
- Obtiene el INPC de junio del ano de calculo
- Calcula el factor correctamente
- Asegura que el factor nunca sea menor a 1.0

**Validacion con tabla INPCSegunMes:**
```
MesCalculo = 12 → MesINPC = 6, AnoINPC = 0
Resultado: Usa INPC de junio del mismo ano de calculo
```

---

## RESUMEN DE CASOS IMPLEMENTADOS

| Caso | Requisito | Implementacion | Status |
|------|-----------|---------------|--------|
| 1. Antes de iniciar depreciacion | Factor = 1.0, INPC_compra | Correcto | ✅ |
| 2. Completamente depreciado | Tabla inpcdeprec, regla 2 anos | Simplificado, falta regla 2 anos | ⚠️ |
| 3. Dado de baja | Tabla INPCbajas, regla 2 anos | Usa tabla pero falta regla 2 anos | ⚠️ |
| 4. Comprado en ano actual | Formula mes medio SAT | Correcto | ✅ |
| 5. Anos anteriores activo | Tabla INPCSegunMes diciembre→junio | Correcto | ✅ |

---

## HALLAZGOS ADICIONALES

### 1. Orden de Evaluacion de Casos

**Problema**: El orden de evaluacion de casos puede causar conflictos.

**Ejemplo**: Un activo dado de baja en el ano actual Y completamente depreciado:
- Entraria primero al CASO 2 (completamente depreciado) en lugar del CASO 3 (dado de baja)
- Esto porque los IF-ELSE se evaluan en orden y CASO 2 viene antes

**Solucion**: El orden deberia ser:
1. Antes de iniciar depreciacion
2. **Dado de baja** (mas especifico)
3. Completamente depreciado
4. Comprado en ano actual
5. Anos anteriores

### 2. Falta de Fecha de Fin de Depreciacion

**Problema**: El SP recibe `@Dep_Acum_Inicio` pero NO recibe `FECHA_FIN_DEPREC` de la tabla `Calculo_RMF`.

**Impacto**: No puede calcular correctamente:
- Fecha de fin de depreciacion para el caso de activos completamente depreciados
- Tiempo transcurrido desde fin de depreciacion

**Solucion**: Agregar al query del cursor:
```sql
SELECT
    ID_Calculo,
    Fecha_Adquisicion,
    Fecha_Baja,
    FECHA_INICIO_DEP,  -- Ya existe
    FECHA_FIN_DEPREC,  -- AGREGAR ESTO
    MOI,
    ...
```

### 3. Manejo de Errores

**Correcto:**
- ✅ Valida que INPC_Compra exista antes de continuar
- ✅ Incrementa contador de errores cuando no se encuentra INPC
- ✅ Usa GOTO para saltar al siguiente registro en caso de error

**Podria mejorar:**
- Registrar en una tabla de log los errores especificos
- Incluir el ID_NUM_ACTIVO en los mensajes de error

### 4. Calculo del Factor

**Correcto:**
- ✅ Usa ROUND con 4 decimales: `ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1)`
- ✅ Asegura que el factor nunca sea menor a 1.0: `IF @Factor < 1 SET @Factor = 1`
- ✅ El parametro `1` en ROUND fuerza redondeo hacia arriba

### 5. Recalculo de Valores

**Correcto:**
- ✅ Actualiza Factor_Actualizacion_Saldo y Factor_Actualizacion_Dep
- ✅ Recalcula Saldo_Actualizado = Saldo_Inicio_Ano * Factor
- ✅ Recalcula Dep_Actualizada = Dep_Fiscal_Ejercicio * Factor
- ✅ Recalcula Valor_Promedio con la formula correcta
- ✅ Recalcula Proporcion
- ✅ Aplica la regla del 10% MOI en Valor_Reportable_MXN
- ✅ Marca Aplica_10_Pct correctamente

---

## PARTE 2: VERIFICACION DE TABLAS AUXILIARES

### Base de Datos
- **Servidor**: dbdev.powerera.com
- **Base de datos**: Actif_RMF
- **Usuario**: earaiza
- **Fecha de verificacion**: 2025-11-05

---

### 1. Tabla: INPCbajas

**Proposito**: Mapea el mes anterior a la baja al mes INPC a utilizar para activos dados de baja.

**Estado**: ✅ **EXISTE Y TIENE DATOS**

**Estructura:**
```
COLUMN_NAME         DATA_TYPE
-------------------  ----------
Id_Mes              int
Id_MesINPC          int
AnoINPC             int
```

**Total de registros**: 12

**Registros completos:**

| Id_Mes | Id_MesINPC | AnoINPC | Interpretacion |
|--------|------------|---------|----------------|
| 1 | 1 | 0 | Baja en Feb → usar INPC de Enero del mismo ano |
| 2 | 1 | 0 | Baja en Mar → usar INPC de Enero del mismo ano |
| 3 | 1 | 0 | Baja en Abr → usar INPC de Enero del mismo ano |
| 4 | 2 | 0 | Baja en May → usar INPC de Febrero del mismo ano |
| 5 | 2 | 0 | Baja en Jun → usar INPC de Febrero del mismo ano |
| 6 | 3 | 0 | Baja en Jul → usar INPC de Marzo del mismo ano |
| 7 | 3 | 0 | Baja en Ago → usar INPC de Marzo del mismo ano |
| 8 | 4 | 0 | Baja en Sep → usar INPC de Abril del mismo ano |
| 9 | 4 | 0 | Baja en Oct → usar INPC de Abril del mismo ano |
| 10 | 5 | 0 | Baja en Nov → usar INPC de Mayo del mismo ano |
| 11 | 5 | 0 | Baja en Dic → usar INPC de Mayo del mismo ano |
| 12 | 6 | 0 | Baja en Ene (ano sig) → usar INPC de Junio del mismo ano |

**Logica de mapeo**: Agrupa los meses de baja en pares y los mapea a los primeros 6 meses del ano.

**Ejemplo de uso:**
- Activo dado de baja el 15 de marzo de 2024
- Mes anterior a la baja: febrero (mes 2)
- Buscar en tabla: `WHERE Id_Mes = 2` → `Id_MesINPC = 1, AnoINPC = 0`
- INPC a usar: Enero 2024 (mes 1 del ano 2024)

---

### 2. Tabla: INPCSegunMes

**Proposito**: Mapea el mes de calculo (Safe Harbor) al mes INPC a utilizar para activos de anos anteriores.

**Estado**: ✅ **EXISTE Y TIENE DATOS**

**Estructura:**
```
COLUMN_NAME         DATA_TYPE
-------------------  ----------
MesCalculo          int
MesINPC             int
AnoINPC             int
```

**Total de registros**: 12

**Registros completos:**

| MesCalculo | MesINPC | AnoINPC | Interpretacion |
|------------|---------|---------|----------------|
| 1 | 1 | 0 | Calculo en Enero → usar INPC de Enero del mismo ano |
| 2 | 1 | 0 | Calculo en Febrero → usar INPC de Enero del mismo ano |
| 3 | 1 | 0 | Calculo en Marzo → usar INPC de Enero del mismo ano |
| 4 | 2 | 0 | Calculo en Abril → usar INPC de Febrero del mismo ano |
| 5 | 2 | 0 | Calculo en Mayo → usar INPC de Febrero del mismo ano |
| 6 | 3 | 0 | Calculo en Junio → usar INPC de Marzo del mismo ano |
| 7 | 3 | 0 | Calculo en Julio → usar INPC de Marzo del mismo ano |
| 8 | 4 | 0 | Calculo en Agosto → usar INPC de Abril del mismo ano |
| 9 | 4 | 0 | Calculo en Septiembre → usar INPC de Abril del mismo ano |
| 10 | 5 | 0 | Calculo en Octubre → usar INPC de Mayo del mismo ano |
| 11 | 5 | 0 | Calculo en Noviembre → usar INPC de Mayo del mismo ano |
| 12 | 6 | 0 | **Calculo en Diciembre → usar INPC de Junio del mismo ano** |

**Logica de mapeo**: Safe Harbor usa regla bimestral. El mes de calculo se mapea al primer mes del bimestre correspondiente.

**Ejemplo de uso (Safe Harbor Anual):**
- Calculo de Safe Harbor para el ano 2024 (se calcula en diciembre)
- MesCalculo = 12
- Buscar en tabla: `WHERE MesCalculo = 12` → `MesINPC = 6, AnoINPC = 0`
- INPC a usar: Junio 2024 (mes 6 del ano 2024)

**Validacion**: ✅ El registro para `MesCalculo = 12` devuelve `MesINPC = 6` como se requiere para Safe Harbor.

---

### 3. Tabla: inpcdeprec

**Proposito**: Mapea el mes de fin de depreciacion al mes INPC a utilizar para activos completamente depreciados.

**Estado**: ✅ **EXISTE Y TIENE DATOS**

**Estructura:**
```
COLUMN_NAME           DATA_TYPE
---------------------  ----------
Id_Mes_Fin_Deprec     int
Id_Mes_INPC           int
AnoINPC               int
```

**Total de registros**: 12

**Registros completos:**

| Id_Mes_Fin_Deprec | Id_Mes_INPC | AnoINPC | Interpretacion |
|-------------------|-------------|---------|----------------|
| 1 | 6 | -1 | Fin deprec en Enero → usar INPC de Junio del ano ANTERIOR |
| 2 | 1 | 0 | Fin deprec en Febrero → usar INPC de Enero del mismo ano |
| 3 | 1 | 0 | Fin deprec en Marzo → usar INPC de Enero del mismo ano |
| 4 | 2 | 0 | Fin deprec en Abril → usar INPC de Febrero del mismo ano |
| 5 | 2 | 0 | Fin deprec en Mayo → usar INPC de Febrero del mismo ano |
| 6 | 3 | 0 | Fin deprec en Junio → usar INPC de Marzo del mismo ano |
| 7 | 3 | 0 | Fin deprec en Julio → usar INPC de Marzo del mismo ano |
| 8 | 4 | 0 | Fin deprec en Agosto → usar INPC de Abril del mismo ano |
| 9 | 4 | 0 | Fin deprec en Septiembre → usar INPC de Abril del mismo ano |
| 10 | 5 | 0 | Fin deprec en Octubre → usar INPC de Mayo del mismo ano |
| 11 | 5 | 0 | Fin deprec en Noviembre → usar INPC de Mayo del mismo ano |
| 12 | 6 | 0 | Fin deprec en Diciembre → usar INPC de Junio del mismo ano |

**Logica de mapeo**: Similar a INPCSegunMes, pero con caso especial para enero (usa junio del ano anterior).

**Ejemplo de uso:**
- Activo termino de depreciarse en mayo de 2024
- Id_Mes_Fin_Deprec = 5
- Buscar en tabla: `WHERE Id_Mes_Fin_Deprec = 5` → `Id_Mes_INPC = 2, AnoINPC = 0`
- INPC a usar: Febrero 2024 (mes 2 del ano 2024)

**Caso especial:**
- Activo termino de depreciarse en enero de 2024
- Id_Mes_Fin_Deprec = 1
- Buscar en tabla: `WHERE Id_Mes_Fin_Deprec = 1` → `Id_Mes_INPC = 6, AnoINPC = -1`
- INPC a usar: Junio 2023 (mes 6 del ano 2024 - 1 = 2023)

**Nota**: ⚠️ Esta tabla NO esta siendo utilizada por el SP actual en el Caso 2 (Completamente depreciado).

---

### 4. Tabla: inpc2 en actif_web_cima_dev (Base de datos origen)

**Proposito**: Tabla maestra de indices INPC por mes, ano, pais y grupo de simulacion.

**Estado**: ✅ **EXISTE Y TIENE DATOS**

**Base de datos**: actif_web_cima_dev
**Schema**: dbo
**Tabla**: inpc2

**Estadisticas:**
- **Total de registros para Mexico (Id_Pais = 1)**: 2,378
- **Total para grupo 1 (real) o NULL**: 974

**Ultimos 12 meses disponibles** (ordenados por mas reciente):

| Ano | Mes | Indice |
|-----|-----|--------|
| 2030 | 12 | 135.467000 |
| 2030 | 11 | 135.467000 |
| 2030 | 10 | 135.467000 |
| 2030 | 9 | 135.467000 |
| 2030 | 8 | 135.467000 |
| 2030 | 7 | 135.467000 |
| 2030 | 6 | 135.467000 |
| 2030 | 5 | 135.467000 |
| 2030 | 4 | 135.467000 |
| 2030 | 3 | 135.467000 |
| 2030 | 2 | 135.467000 |
| 2030 | 1 | 135.467000 |

**Observacion**: Los datos para 2030 parecen ser valores proyectados o de prueba (todos tienen el mismo indice).

**Query utilizado por el SP:**
```sql
SELECT Indice
FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
WHERE Mes = @Mes
  AND Anio = @Ano
  AND Id_Pais = 1
  AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL)
```

**Validacion**: ✅ La tabla esta accesible via linked server y contiene datos suficientes para calculos historicos y futuros.

---

## PARTE 3: CONCLUSIONES Y RECOMENDACIONES

### Resumen Ejecutivo

El stored procedure `sp_Actualizar_INPC_Nacionales` implementa **3 de 5 casos correctamente** (60%) segun el algoritmo de referencia `usp_CalculoINPCActivo` del sistema Actif legacy.

**Casos correctos:**
1. ✅ Antes de iniciar depreciacion
2. ✅ Comprado en el ano actual (con formula SAT correcta)
3. ✅ De anos anteriores activo (con tabla INPCSegunMes)

**Casos con problemas:**
1. ⚠️ Completamente depreciado: NO usa tabla `inpcdeprec`, falta regla de 2 anos
2. ⚠️ Dado de baja: Usa tabla `INPCbajas` pero falta regla de 2 anos

**Tablas auxiliares:**
- ✅ Todas las tablas existen y tienen datos correctos
- ✅ 12 registros en cada tabla con mapeos bimestrales
- ✅ Tabla `inpc2` accesible con 974 registros para grupo real

---

### Recomendaciones de Mejora

#### 1. Implementar regla de 2 anos para activos completamente depreciados

**Cambio en lineas 119-155:**

```sql
-- CASO 2: Completamente depreciado
ELSE IF ABS(@MOI - @Dep_Acum_Inicio) < 1
BEGIN
    DECLARE @Fecha_Fin_Deprec DATE;
    DECLARE @Años_Desde_Fin_Deprec INT;

    -- Calcular fecha de fin de depreciacion
    -- (asumiendo que se agrega este campo al query del cursor)
    -- O calcularlo dinamicamente si no esta disponible

    SET @Años_Desde_Fin_Deprec = DATEDIFF(YEAR, @Fecha_Fin_Deprec,
                                           DATEFROMPARTS(@Ano_Calculo, 12, 31));

    IF @Años_Desde_Fin_Deprec < 2
    BEGIN
        -- Usar tabla inpcdeprec
        DECLARE @Mes_INPC_Deprec INT;
        DECLARE @Ano_INPC_Deprec INT;

        SELECT @Mes_INPC_Deprec = Id_Mes_INPC,
               @Ano_INPC_Deprec = YEAR(@Fecha_Fin_Deprec) + AnoINPC
        FROM dbo.inpcdeprec
        WHERE Id_Mes_Fin_Deprec = MONTH(@Fecha_Fin_Deprec);

        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Anio = @Ano_INPC_Deprec
          AND Mes = @Mes_INPC_Deprec
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'DeprecMenos2años';
    END
    ELSE
    BEGIN
        -- Usar INPC del mes de fin de depreciacion directamente
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Mes = MONTH(@Fecha_Fin_Deprec)
          AND Anio = YEAR(@Fecha_Fin_Deprec)
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'DeprecMas2años';
    END

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
END
```

#### 2. Implementar regla de 2 anos para activos dados de baja

**Cambio en lineas 156-195:**

```sql
-- CASO 3: Dado de baja (MOVER ANTES DEL CASO 2)
ELSE IF @Fecha_Baja IS NOT NULL
BEGIN
    DECLARE @Mes_Anterior_Baja INT = MONTH(DATEADD(MONTH, -1, @Fecha_Baja));
    DECLARE @Ano_Baja_INPC INT;
    DECLARE @Id_MesINPC INT;
    DECLARE @Años_Desde_Baja INT;

    SET @Años_Desde_Baja = DATEDIFF(YEAR, @Fecha_Baja,
                                     DATEFROMPARTS(@Ano_Calculo, 12, 31));

    IF @Años_Desde_Baja < 2
    BEGIN
        -- Buscar en tabla INPCbajas
        SELECT @Ano_Baja_INPC = YEAR(DATEADD(MONTH, -1, @Fecha_Baja)) + AnoINPC,
               @Id_MesINPC = Id_MesINPC
        FROM dbo.INPCbajas
        WHERE Id_Mes = @Mes_Anterior_Baja;

        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Anio = @Ano_Baja_INPC
          AND Mes = @Id_MesINPC
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'BajaMenos2años';
    END
    ELSE
    BEGIN
        -- Usar mes anterior a la baja directamente
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Mes = @Mes_Anterior_Baja
          AND Anio = YEAR(DATEADD(MONTH, -1, @Fecha_Baja))
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'BajaMas2años';
    END

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
END
```

#### 3. Agregar campo FECHA_FIN_DEPREC al cursor

**Cambio en lineas 61-75:**

```sql
DECLARE cursor_activos CURSOR FOR
SELECT
    ID_Calculo,
    Fecha_Adquisicion,
    Fecha_Baja,
    FECHA_INICIO_DEP,
    FECHA_FIN_DEPREC,  -- AGREGAR
    MOI,
    Saldo_Inicio_Ano,
    Dep_Fiscal_Ejercicio,
    Meses_Uso_En_Ejercicio,
    Dep_Acum_Inicio
FROM Calculo_RMF
WHERE ID_Compania = @ID_Compania
  AND Ano_Calculo = @Ano_Calculo
  AND Tipo_Activo = 'Nacional'
  AND INPCCompra IS NULL;
```

#### 4. Reordenar casos para evitar conflictos

**Orden sugerido:**
1. CASO 1: Antes de iniciar depreciacion
2. **CASO 3: Dado de baja** (mover antes del caso 2)
3. CASO 2: Completamente depreciado
4. CASO 4: Comprado en el ano actual
5. CASO 5: De anos anteriores

#### 5. Corregir typo en PasoINPC

**Linea 215:**
```sql
SET @PasoINPC = 'mismoano';  -- Cambiar de 'misomoano'
```

#### 6. Agregar logging de errores detallado

```sql
-- Crear tabla de log
CREATE TABLE Log_INPC_Errores (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    ID_Calculo BIGINT,
    ID_NUM_ACTIVO VARCHAR(50),
    Fecha_Compra DATE,
    Fecha_Baja DATE,
    Ano_Calculo INT,
    Mensaje_Error NVARCHAR(500),
    Fecha_Log DATETIME DEFAULT GETDATE()
);

-- Insertar errores en el SP
IF @INPC_Compra IS NULL
BEGIN
    INSERT INTO Log_INPC_Errores (ID_Calculo, Ano_Calculo, Mensaje_Error)
    VALUES (@ID_Calculo, @Ano_Calculo,
            'INPC Compra no encontrado para ' +
            CAST(YEAR(@Fecha_Compra) AS VARCHAR(4)) + '-' +
            RIGHT('0' + CAST(MONTH(@Fecha_Compra) AS VARCHAR(2)), 2));
END
```

---

### Impacto de las Mejoras

**Sin las mejoras (actual):**
- Activos completamente depreciados: pueden usar INPC incorrecto (no usa tabla inpcdeprec)
- Activos dados de baja hace mas de 2 anos: usan tabla cuando no deberian
- Posibles conflictos entre caso 2 y caso 3

**Con las mejoras:**
- ✅ 100% de casos implementados correctamente
- ✅ Cumplimiento total con el algoritmo de referencia
- ✅ Calculo de INPC conforme a la logica fiscal del SAT
- ✅ Trazabilidad completa con logs de errores

---

### Prioridad de Implementacion

1. **Alta prioridad**: Implementar regla de 2 anos (casos 2 y 3)
2. **Media prioridad**: Agregar campo FECHA_FIN_DEPREC al cursor
3. **Media prioridad**: Reordenar casos
4. **Baja prioridad**: Corregir typo
5. **Baja prioridad**: Agregar logging detallado

---

## ANEXO: Documentacion de Tablas Auxiliares

### Tabla INPCbajas - Detalle Completo

```
Id_Mes = Mes ANTERIOR a la fecha de baja (1-12)
Id_MesINPC = Mes del INPC a utilizar (1-6)
AnoINPC = Ajuste de ano (0 = mismo ano)

Mapeo bimestral:
- Bajas en Feb-Mar → INPC Ene
- Bajas en Abr-May → INPC Feb
- Bajas en Jun-Jul → INPC Mar
- Bajas en Ago-Sep → INPC Abr
- Bajas en Oct-Nov → INPC May
- Bajas en Dic-Ene → INPC Jun
```

### Tabla INPCSegunMes - Detalle Completo

```
MesCalculo = Mes en que se hace el calculo Safe Harbor (1-12)
MesINPC = Mes del INPC a utilizar (1-6)
AnoINPC = Ajuste de ano (0 = mismo ano)

Mapeo bimestral:
- Calc en Ene-Feb-Mar → INPC Ene
- Calc en Abr-May → INPC Feb
- Calc en Jun-Jul → INPC Mar
- Calc en Ago-Sep → INPC Abr
- Calc en Oct-Nov → INPC May
- Calc en Dic → INPC Jun (Safe Harbor)
```

### Tabla inpcdeprec - Detalle Completo

```
Id_Mes_Fin_Deprec = Mes de fin de depreciacion (1-12)
Id_Mes_INPC = Mes del INPC a utilizar (1-6)
AnoINPC = Ajuste de ano (-1, 0)

Mapeo bimestral (con caso especial enero):
- Fin en Ene → INPC Jun del ano anterior
- Fin en Feb-Mar → INPC Ene
- Fin en Abr-May → INPC Feb
- Fin en Jun-Jul → INPC Mar
- Fin en Ago-Sep → INPC Abr
- Fin en Oct-Nov → INPC May
- Fin en Dic → INPC Jun
```

---

**Fin del reporte**

Generado el: 2025-11-05
Por: Claude Code
Stored Procedure analizado: sp_Actualizar_INPC_Nacionales v2.0
Lineas de codigo: 346
Base de datos: Actif_RMF en dbdev.powerera.com
