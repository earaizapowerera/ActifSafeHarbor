# Hallazgos del Análisis del Excel - Preguntas para Confirmación

## 1. Estructura del Archivo Excel

### Hojas Encontradas:
1. **Ejemplo Reporte** - 18 filas x 29 columnas
2. **Activos Extranjeros** - 10 filas x 22 columnas (Art 182, fracción I, inciso a) LISR)
3. **Activos Mexicanos** - 16 filas x 31 columnas

## 2. Campos Identificados

### Datos Generales (ambas hojas):
- Tipo (AF = Activo Fijo)
- Fecha de adquisicion
- Fecha de baja
- **MOI** (Monto Original de Inversión)
- Anual Rate (Tasa anual de depreciación, ej: 0.08 = 8%)
- Month Rate (Tasa mensual, ej: 0.006666...)
- Deprec anual (Depreciación anual en pesos)

### Campos Temporales:
- **Meses de uso al ejercicio ant** / **al inicio del ejercicio** (60 meses en los ejemplos)
- **Meses de uso hasta la ½ del periodo** (6 meses)
- **Meses de uso en el ejercicio** (12 meses)

### Campos de Depreciación (Solo en Activos Mexicanos):
- **Dep Fiscal acumulada incio año** (Ejemplo: 400,000)

### Campos de Actualización INPC:
- **INPC Adqu** (INPC del mes de adquisición)
- **INPC ½ del ejercicio** (INPC a mitad del año fiscal - junio/julio?)
- **Factor Actualizacion** (fórmula calculada)

### Campos Calculados:
- **Saldo por deducir ISR al inicio año** (MOI - Depreciación Acumulada)
- **Saldo actualizado** (Saldo × Factor Actualización)
- **Depreciacion Fiscal del Ejercicio** (para el año 2024)

## 3. Observaciones Clave

### Sobre el "Residual" o Mínimo

**Pregunta:** Mencionaste que hay un "residual" o mínimo a tomar en cuenta sin importar cuánto esté depreciado.

**¿Dónde está este valor?**
- ¿Es un porcentaje del MOI? (ej: 10% mínimo)
- ¿Es un campo en las columnas que aún no he visto?
- ¿Se calcula de alguna forma especial?

### Sobre Dep Fiscal Acumulada

**Confirmación:** El campo "Dep Fiscal acumulada incio año" corresponde al campo `ACUMULADO_HISTORICA` de la tabla `calculo` en la base de datos.

**Ejemplo encontrado:**
- MOI: 1,000,000
- Dep Fiscal acumulada inicio año: 400,000
- Saldo por deducir: 600,000

**Pregunta:** Para obtener la depreciación acumulada al inicio del año 2024, ¿debo:
1. Buscar en tabla `calculo` WHERE ID_ANO = 2023 AND ID_MES = 12?
2. ¿O hay una forma diferente de obtenerlo?

### Sobre Activos que NO son Propios

**Tu comentario:** "creo que este cálculo va a ser solamente para activos que no son propios"

**Pregunta:** ¿Entonces el sistema SOLO debe calcular impuestos para:
- `FLG_PROPIO = 0` (No propios / Arrendados / Terceros)?
- ¿Independientemente de si ID_PAIS = 1 (México) o ID_PAIS > 1 (Extranjero)?

**Clarificación necesaria:** ¿El sistema debe generar:
- Reporte de activos extranjeros NO propios únicamente?
- O también activos mexicanos NO propios?

## 4. Artículo 182 LISR

La hoja "Activos Extranjeros" menciona:
> **Art 182, fracción I, inciso a) LISR**

Este artículo es del **RÉGIMEN DE LAS PERSONAS MORALES CON FINES NO LUCRATIVOS**.

**Pregunta:** ¿Es correcto este artículo? ¿O debería ser Art 31-34 que ya documentamos?

## 5. INPC a Mitad del Ejercicio

**Campo encontrado:** "INPC ½ del ejercicio"

**Pregunta:** ¿El INPC que debo usar para actualización es:
- El de **mitad del año fiscal** (junio si empieza en enero)?
- ¿O el de **diciembre del ejercicio**?

**Fórmula esperada:**
```
Factor Actualización = INPC_MitadEjercicio / INPC_Adquisicion
Saldo Actualizado = (MOI - Dep_Acum_Inicio_Año) × Factor_Actualización
```

¿Es correcta esta fórmula?

## 6. Depreciación del Ejercicio

**Campo:** "Depreciacion Fiscal del Ejercicio"

**Pregunta:** ¿Esta es:
- La depreciación calculada para el año 2024 completo (12 meses)?
- ¿Se calcula sobre el MOI original o sobre el saldo actualizado?

**Fórmula esperada:**
```
Depreciacion_Ejercicio = MOI × Tasa_Anual × (Meses_Uso_Ejercicio / 12)
```

¿O es:
```
Depreciacion_Ejercicio = Saldo_Actualizado × Tasa_Anual × (Meses_Uso_Ejercicio / 12)
```

## 7. Casos Especiales

### Activo con Baja en el Ejercicio

**Ejemplo encontrado (Fila 5):**
- ID: 48483
- Fecha adquisición: 20/08/2018
- **Fecha de baja: 20/08/2024**
- MOI: 400,000

**Pregunta:** ¿Cómo se calcula la depreciación para un activo que se da de baja a mitad del ejercicio?
- ¿Solo se deprecia hasta el mes de baja?
- ¿Se hace un cálculo especial del residual?

### Terrenos (No Depreciables)

**Ejemplo encontrado (Fila 6):**
- ID: 48484
- Tipo: Terreno
- Anual Rate: 0
- Month Rate: 0
- Deprec anual: 0

**Confirmación:** Los terrenos NO se deprecian fiscalmente, correcto?

## 8. Columnas Faltantes por Ver

El Excel tiene hasta **31 columnas** en la hoja "Activos Mexicanos" pero solo pude ver hasta la columna 20.

**Columnas que faltan por revisar (20-31):**
- ¿Hay fórmulas de cálculo en esas columnas?
- ¿Hay el campo del "residual/mínimo" ahí?
- ¿Hay más campos INPC?

## 9. Base de Datos de Origen

**Tu confirmación:** "la base de datos de origen va a ser actif_web_cima_dev"

**Actualización necesaria:**
- Cambiar connection string default
- Confirmar que siempre será esta BD o si será configurable por compañía

## 10. Resumen de Fórmula Pendiente

Basado en lo que vi, parece que la fórmula para **Activos No Propios** es:

```
1. Obtener datos del activo:
   - MOI (Monto Original Inversión) = COSTO_ADQUISICION
   - Fecha Adquisición = FECHA_COMPRA
   - Tasa Depreciación = según ID_TIPO_ACTIVO

2. Obtener Depreciación Acumulada al inicio del ejercicio:
   - Query: SELECT ACUMULADO_HISTORICA
     FROM calculo
     WHERE ID_NUM_ACTIVO = X
       AND ID_ANO = 2023
       AND ID_MES = 12
       AND ID_TIPO_DEP = 2  -- Fiscal

3. Calcular Saldo por Deducir Inicial:
   Saldo_Inicial = MOI - Dep_Acum_Inicio_Año

4. Obtener INPC:
   - INPC_Adquisicion = obtener de INPC2 WHERE Año/Mes = Fecha Adquisición
   - INPC_Mitad_Ejercicio = obtener de INPC2 WHERE Año = 2024, Mes = 6 (?)

5. Calcular Factor Actualización:
   Factor = INPC_Mitad_Ejercicio / INPC_Adquisicion

6. Calcular Saldo Actualizado:
   Saldo_Actualizado = Saldo_Inicial × Factor

7. Calcular Depreciación del Ejercicio:
   Dep_Ejercicio = ??? (FALTA CONFIRMAR FÓRMULA)

8. Aplicar Residual Mínimo:
   ??? (FALTA DEFINIR)
```

## Preguntas Críticas para Continuar:

1. ✅ **Depreciación Acumulada:** Confirmado usar ACUMULADO_HISTORICA de tabla calculo
2. ✅ **Año anterior:** Dic 2023 para inicio de 2024
3. ❓ **¿Qué es el "residual" o mínimo?** ¿Dónde lo veo en el Excel?
4. ❓ **¿Solo activos NO propios?** (FLG_PROPIO = 0)
5. ❓ **¿INPC de mitad de año o fin de año?**
6. ❓ **¿Depreciación sobre MOI o sobre Saldo Actualizado?**
7. ❓ **¿Artículo 182 es correcto o debería ser Art 31-34?**
8. ❓ **¿Cómo ver las columnas 21-31 del Excel para encontrar las fórmulas completas?**

---

**Siguiente paso:** Necesito ver las FÓRMULAS exactas de las celdas calculadas (Factor Actualización, Saldo Actualizado, Depreciación del Ejercicio) para documentar correctamente el cálculo.
