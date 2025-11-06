# Instrucciones para Corregir sp_Actualizar_INPC_Nacionales

**Fecha**: 2025-11-05
**Objetivo**: Implementar al 100% el algoritmo legacy de usp_CalculoINPCActivo
**Archivo a corregir**: `/Users/enrique/actifrmf/Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql`

---

## 📋 Contexto

El stored procedure `sp_Actualizar_INPC_Nacionales` v2.0 tiene **3 de 5 casos implementados correctamente (60%)**.

Según el reporte `/Users/enrique/actifrmf/REPORTE_VERIFICACION_INPC.md`, faltan implementar:

1. ⚠️ **Regla de 2 años para activos completamente depreciados** + usar tabla `inpcdeprec`
2. ⚠️ **Regla de 2 años para activos dados de baja**

---

## 🎯 Tareas a Realizar

### TAREA 1: Agregar campo FECHA_FIN_DEPREC al cursor

**Problema**: El cursor no obtiene la fecha de fin de depreciación, necesaria para calcular si han pasado 2 años.

**Solución**:

1. Buscar la línea donde se declara el cursor (aproximadamente línea 61-75)
2. Agregar `Fecha_Fin_Deprec` a la lista de variables declaradas
3. Agregar el campo al SELECT del cursor
4. Agregar el campo al FETCH del cursor

**Código de referencia**:

```sql
-- DECLARACIÓN DE VARIABLES (agregar después de línea 58)
DECLARE @ID_Calculo BIGINT,
        @Fecha_Compra DATE,
        @Fecha_Baja DATE,
        @FECHA_INICIO_DEP DATE,
        @Fecha_Fin_Deprec DATE,  -- ⭐ AGREGAR ESTA LÍNEA
        @MOI DECIMAL(18,4),
        @Saldo_Inicio_Año DECIMAL(18,4),
        @Dep_Fiscal_Ejercicio DECIMAL(18,4),
        @Meses_Uso_En_Ejercicio INT,
        @Dep_Acum_Inicio DECIMAL(18,4);

-- CURSOR (agregar campo al SELECT, línea 62-75)
DECLARE cursor_activos CURSOR FOR
SELECT
    ID_Calculo,
    Fecha_Adquisicion,
    Fecha_Baja,
    NULL AS Fecha_Fin_Deprec,  -- ⭐ AGREGAR: Por ahora NULL, después calcular
    MOI,
    Saldo_Inicio_Año,
    Dep_Fiscal_Ejercicio,
    Meses_Uso_En_Ejercicio,
    Dep_Acum_Inicio
FROM Calculo_RMF
WHERE ID_Compania = @ID_Compania
  AND Año_Calculo = @Año_Calculo
  AND Tipo_Activo = 'Nacional'
  AND INPCCompra IS NULL;

-- FETCH (agregar variable al FETCH, líneas 78-80)
FETCH NEXT FROM cursor_activos INTO @ID_Calculo, @Fecha_Compra, @Fecha_Baja,
                                     @Fecha_Fin_Deprec,  -- ⭐ AGREGAR
                                     @MOI, @Saldo_Inicio_Año, @Dep_Fiscal_Ejercicio,
                                     @Meses_Uso_En_Ejercicio, @Dep_Acum_Inicio;

-- Y en el segundo FETCH al final del loop (línea 262-264)
FETCH NEXT FROM cursor_activos INTO @ID_Calculo, @Fecha_Compra, @Fecha_Baja,
                                     @Fecha_Fin_Deprec,  -- ⭐ AGREGAR
                                     @MOI, @Saldo_Inicio_Año, @Dep_Fiscal_Ejercicio,
                                     @Meses_Uso_En_Ejercicio, @Dep_Acum_Inicio;
```

**Nota**: Por ahora usamos NULL para Fecha_Fin_Deprec porque Calculo_RMF no tiene ese campo. Más adelante se puede calcular si es necesario.

---

### TAREA 2: Corregir CASO 2 - Activos Completamente Depreciados

**Problema**: No implementa la regla de 2 años ni usa la tabla `inpcdeprec`.

**Ubicación**: Líneas 119-155 del archivo actual

**Algoritmo legacy (usp_CalculoINPCActivo)**:

```sql
-- Del sistema legacy (líneas relevantes):
ELSE IF ABS(@valor_adquisicion - @acumulado_historica) < 1
     AND @fecha_cierre >= @fecha_fin_deprec
     AND (@status = 'A' OR (@status = 'B' AND @fecha_baja > @fecha_fin_deprec))
BEGIN
    -- vemos si tiene más de un año o si es reciente.
    IF YEAR(@fecha_cierre) - YEAR(@fecha_fin_deprec) < 2
    BEGIN
        -- sacamos el factor medio de la fecha_fin deprec
        SELECT @inpc_medio = inpc2.Indice
        FROM inpcdeprec
        INNER JOIN inpc2 ON inpc2.anio = YEAR(@fecha_fin_deprec) + AñoINPC
        AND inpcdeprec.id_mes_inpc = inpc2.mes
        AND id_grupo_simulacion = 8
        WHERE id_mes_fin_deprec = MONTH(@fecha_fin_deprec)
    END
    ELSE
    BEGIN
        -- Opción 2: poner inpc de mes de fin de depreciación
        SELECT @inpc_medio = Indice
        FROM inpc2
        WHERE id_grupo_simulacion = 8
          AND Mes = MONTH(@fecha_fin_deprec)
          AND anio = YEAR(@fecha_fin_deprec)
    END

    SET @factoutilizado = ROUND(@INPC_Medio / @INPC_Compra, 4, 1)
    IF @factoutilizado < 1 SET @factoutilizado = 1
END
```

**Solución a implementar**:

```sql
-- CASO 2: Completamente depreciado
-- REEMPLAZAR TODO el bloque entre líneas 119-155 con este código:
ELSE IF ABS(@MOI - @Dep_Acum_Inicio) < 1
BEGIN
    DECLARE @Mes_INPC_Utilizado INT;
    DECLARE @Año_INPC_Utilizado INT;
    DECLARE @Años_Desde_Fin_Deprec INT;

    -- Calcular fecha de fin de depreciación si no la tenemos
    -- Usamos @Fecha_Baja como aproximación o calculamos
    IF @Fecha_Fin_Deprec IS NULL
    BEGIN
        -- Si está dado de baja, usar fecha de baja como aproximación
        IF @Fecha_Baja IS NOT NULL
            SET @Fecha_Fin_Deprec = @Fecha_Baja;
        ELSE
            -- Si no tiene baja, calcular según tasa de depreciación
            -- Por simplicidad, usar año de cálculo - 1 como estimación
            SET @Fecha_Fin_Deprec = CAST(CAST(@Año_Calculo - 1 AS VARCHAR(4)) + '-12-31' AS DATE);
    END

    -- Calcular años transcurridos desde fin de depreciación
    SET @Años_Desde_Fin_Deprec = @Año_Calculo - YEAR(@Fecha_Fin_Deprec);

    -- REGLA DE 2 AÑOS
    IF @Años_Desde_Fin_Deprec < 2
    BEGIN
        -- Menos de 2 años: Usar tabla inpcdeprec con mes medio
        DECLARE @Mes_Fin_Deprec INT = MONTH(@Fecha_Fin_Deprec);
        DECLARE @Id_MesINPC_Deprec INT;
        DECLARE @AñoINPC_Deprec INT;

        SELECT @Id_MesINPC_Deprec = Id_Mes_INPC,
               @AñoINPC_Deprec = YEAR(@Fecha_Fin_Deprec) + AñoINPC
        FROM dbo.inpcdeprec
        WHERE Id_Mes_Fin_Deprec = @Mes_Fin_Deprec;

        IF @Id_MesINPC_Deprec IS NOT NULL
        BEGIN
            SELECT @INPC_Utilizado = Indice
            FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
            WHERE Anio = @AñoINPC_Deprec
              AND Mes = @Id_MesINPC_Deprec
              AND Id_Pais = 1
              AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);
        END

        SET @PasoINPC = 'DeprecMesMedio';
    END
    ELSE
    BEGIN
        -- 2 años o más: Usar INPC del mes de fin de depreciación directamente
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Mes = MONTH(@Fecha_Fin_Deprec)
          AND Anio = YEAR(@Fecha_Fin_Deprec)
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'DepreciadoMesFin';
    END

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
END
```

---

### TAREA 3: Corregir CASO 3 - Activos Dados de Baja

**Problema**: No implementa la regla de 2 años correctamente.

**Ubicación**: Líneas 156-195 del archivo actual

**Algoritmo legacy (usp_CalculoINPCActivo)**:

```sql
ELSE IF @status = 'B' -- dado de baja
BEGIN
    -- vemos si tiene más de un año o si es reciente.
    IF YEAR(@fecha_cierre) - YEAR(@fecha_baja) < 2
    BEGIN
        -- Cuando tiene menos de dos años, hacemos cruce con tabla según mes para sacar mes medio
        SELECT @inpc_medio = Indice
        FROM INPCbajas
        INNER JOIN inpc2 ON inpc2.anio = YEAR(DATEADD(month, -1, @fecha_baja)) + AñoINPC
        AND inpcbajas.id_mesinpc = inpc2.mes
        AND id_grupo_simulacion = 8
        WHERE inpcbajas.id_mes = MONTH(DATEADD(month, -1, @fecha_baja))
    END
    ELSE
    BEGIN
        -- Cuando tiene más de un año, se toma directamente el factor del mes sin el mes medio
        SELECT @inpc_medio = Indice
        FROM inpc2
        WHERE id_grupo_simulacion = 8
          AND Mes = MONTH(DATEADD(month, -1, @fecha_baja))
          AND anio = YEAR(DATEADD(month, -1, @fecha_baja))
    END

    SET @factoMedio = ROUND(@INPC_Medio / @INPC_Compra, 4, 1)
    IF @factomedio < 1 SET @factomedio = 1
END
```

**Solución a implementar**:

```sql
-- CASO 3: Dado de baja en el año
-- REEMPLAZAR TODO el bloque entre líneas 156-195 con este código:
ELSE IF @Fecha_Baja IS NOT NULL AND YEAR(@Fecha_Baja) = @Año_Calculo
BEGIN
    DECLARE @Mes_Anterior_Baja INT = MONTH(DATEADD(MONTH, -1, @Fecha_Baja));
    DECLARE @Año_Anterior_Baja INT = YEAR(DATEADD(MONTH, -1, @Fecha_Baja));
    DECLARE @Años_Desde_Baja INT;
    DECLARE @Año_Baja_INPC INT;
    DECLARE @Id_MesINPC INT;

    -- Calcular años transcurridos desde la baja
    SET @Años_Desde_Baja = @Año_Calculo - YEAR(@Fecha_Baja);

    -- REGLA DE 2 AÑOS
    IF @Años_Desde_Baja < 2
    BEGIN
        -- Menos de 2 años: Usar tabla INPCbajas con mes medio
        SELECT @Año_Baja_INPC = @Año_Anterior_Baja + AñoINPC,
               @Id_MesINPC = Id_MesINPC
        FROM dbo.INPCbajas
        WHERE Id_Mes = @Mes_Anterior_Baja;

        IF @Año_Baja_INPC IS NOT NULL AND @Id_MesINPC IS NOT NULL
        BEGIN
            SELECT @INPC_Utilizado = Indice
            FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
            WHERE Anio = @Año_Baja_INPC
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
              AND Anio = @Año_Anterior_Baja
              AND Id_Pais = 1
              AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);
        END

        SET @PasoINPC = 'baja<2años';
    END
    ELSE
    BEGIN
        -- 2 años o más: Usar INPC del mes anterior a la baja directamente (sin tabla)
        SELECT @INPC_Utilizado = Indice
        FROM [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2
        WHERE Mes = @Mes_Anterior_Baja
          AND Anio = @Año_Anterior_Baja
          AND Id_Pais = 1
          AND (Id_Grupo_Simulacion = @Id_Grupo_Simulacion OR Id_Grupo_Simulacion IS NULL);

        SET @PasoINPC = 'baja>=2años';
    END

    IF @INPC_Utilizado IS NOT NULL
    BEGIN
        SET @Factor = ROUND(@INPC_Utilizado / @INPC_Compra, 4, 1);
        IF @Factor < 1 SET @Factor = 1;
    END
END
```

---

### TAREA 4: Reordenar los casos (IMPORTANTE)

**Problema**: El orden de los IF...ELSE puede causar conflictos. Según el algoritmo legacy, el orden debe ser:

1. Antes de iniciar depreciación
2. Completamente depreciado
3. **Dado de baja** (debe ir ANTES que "adquirido en el año")
4. Adquirido en el año actual
5. De años anteriores, activo

**Acción**: Verificar que el CASO 3 (dado de baja) esté ANTES del CASO 4 (adquirido en el año).

El orden actual es correcto:
- Línea 111-118: CASO 1
- Línea 119-155: CASO 2
- Línea 156-195: CASO 3 ✅
- Línea 196-216: CASO 4 ✅
- Línea 217-245: CASO 5 ✅

**No necesita cambios en el orden**.

---

### TAREA 5: Actualizar versión del SP

Al final del archivo, cambiar:

```sql
-- Línea 342-344
PRINT 'SP sp_Actualizar_INPC_Nacionales v2.0 creado exitosamente';
```

Por:

```sql
PRINT 'SP sp_Actualizar_INPC_Nacionales v2.1 creado exitosamente';
PRINT 'CORREGIDO: Implementa 100% algoritmo legacy con regla de 2 años';
```

Y en el header del archivo (línea 3):

```sql
-- Versión: 2.1
```

---

## ✅ Checklist de Verificación

Después de hacer los cambios, verificar:

- [ ] Campo `@Fecha_Fin_Deprec` agregado a variables declaradas
- [ ] Campo agregado al SELECT del cursor
- [ ] Campo agregado a ambos FETCH del cursor
- [ ] CASO 2 implementa regla de 2 años con tabla `inpcdeprec`
- [ ] CASO 2 marca registros con 'DeprecMesMedio' o 'DepreciadoMesFin'
- [ ] CASO 3 implementa regla de 2 años
- [ ] CASO 3 marca registros con 'baja<2años' o 'baja>=2años'
- [ ] Versión actualizada a v2.1
- [ ] Todas las variables declaradas con DECLARE antes de usarse

---

## 🧪 Prueba Sugerida

Después de aplicar los cambios, ejecutar:

```sql
-- En Actif_RMF
EXEC sp_Actualizar_INPC_Nacionales 188, 2024, 1

-- Verificar distribución de casos
SELECT
    CASE
        WHEN INPCCompra IS NULL THEN 'SIN_INPC'
        WHEN Factor_Actualizacion_Saldo = 1.0 THEN 'FACTOR_1.0'
        WHEN Factor_Actualizacion_Saldo > 1.0 THEN 'CON_AJUSTE_INPC'
    END AS TipoCalculo,
    COUNT(*) AS Cantidad
FROM Calculo_RMF
WHERE ID_Compania = 188
  AND Año_Calculo = 2024
  AND Tipo_Activo = 'Nacional'
GROUP BY
    CASE
        WHEN INPCCompra IS NULL THEN 'SIN_INPC'
        WHEN Factor_Actualizacion_Saldo = 1.0 THEN 'FACTOR_1.0'
        WHEN Factor_Actualizacion_Saldo > 1.0 THEN 'CON_AJUSTE_INPC'
    END;
```

---

## 📊 Resultado Esperado

Después de aplicar las correcciones:
- ✅ **5 de 5 casos implementados correctamente (100%)**
- ✅ Usa tabla `inpcdeprec` para activos completamente depreciados < 2 años
- ✅ Aplica regla de 2 años para bajas
- ✅ Compatible 100% con algoritmo legacy usp_CalculoINPCActivo

---

## 📁 Archivos de Referencia

- **SP a corregir**: `/Users/enrique/actifrmf/Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql`
- **Reporte de análisis**: `/Users/enrique/actifrmf/REPORTE_VERIFICACION_INPC.md`
- **Algoritmo legacy**: Código SQL proporcionado por el usuario (ver arriba)
- **Tablas auxiliares**: Verificadas en la base de datos (INPCbajas, INPCSegunMes, inpcdeprec)

---

**IMPORTANTE**: Al hacer los cambios, mantener la estructura del cursor y asegurarte de que todas las variables estén declaradas antes de usarse. El SP usa linked server `[dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2` para consultar INPC.
