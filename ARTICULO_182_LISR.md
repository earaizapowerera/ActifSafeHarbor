# Artículo 182 LISR - Regla del 10% para Activos en Maquiladoras

## Fuente Legal

**Ley del Impuesto Sobre la Renta (LISR)**
**Artículo 182, Fracción I, Inciso a)**

**Título VI:** De los Regímenes Fiscales Preferentes y de las Empresas Multinacionales
**Capítulo II:** De las Empresas Multinacionales y de las Operaciones Celebradas entre Partes Relacionadas

---

## Texto de la Disposición Clave

> **"En ningún caso la deducción pendiente será inferior al 10% del monto de adquisición de los bienes."**

### Traducción al Inglés:
> "In no case shall the pending deduction be less than 10% of the acquisition amount of the goods."

---

## Contexto del Artículo 182

El Artículo 182 de la LISR establece las condiciones bajo las cuales las empresas que llevan a cabo operaciones de maquila cumplen con las obligaciones en materia de precios de transferencia y bajo las cuales los residentes en el extranjero por cuenta de quienes actúan no se consideran con establecimiento permanente en México (**Safe Harbor** para maquiladoras).

### Cálculo Safe Harbor:

La maquiladora debe determinar su ingreso fiscal como el resultado de aplicar el porcentaje que corresponda sobre el total de los costos y gastos de operación incurridos en el ejercicio:

1. **6.9%** del valor total de los activos utilizados en la operación de maquila durante el ejercicio fiscal
2. **6.5%** del total de los costos y gastos de operación

Se utiliza **el mayor** de ambos resultados.

---

## Aplicación de la Regla del 10% MOI

### Para qué aplica:

La regla del 10% del Monto Original de Inversión (MOI) se aplica específicamente a:

1. **Activos utilizados en operaciones de maquila**
2. **Activos arrendados** (de partes relacionadas en territorio nacional o no relacionadas en el extranjero)
3. **Activos que no son propiedad de la maquiladora** pero que utiliza en su operación

### Interpretación Fiscal:

**"Deducción pendiente" (Pending deduction)** se refiere al saldo por deducir del activo después de aplicar la depreciación acumulada.

**La regla establece:**

```
IF Saldo_Por_Deducir_ISR < (MOI × 0.10) THEN
    Valor_Mínimo_Deducible = MOI × 0.10
ELSE
    Valor_Mínimo_Deducible = Saldo_Por_Deducir_ISR
END IF
```

### Ejemplo Práctico:

| Concepto | Valor |
|----------|-------|
| Monto Original de Inversión (MOI) | $1,000,000 |
| Depreciación Acumulada | $950,000 |
| Saldo por Deducir ISR | $50,000 |
| **10% del MOI** | **$100,000** |
| **Valor para Cálculo** | **$100,000** ← Se usa el mayor |

En este caso, aunque el saldo real por deducir sea $50,000, se utiliza **$100,000** (10% del MOI) para el cálculo del Safe Harbor.

---

## Relación con Activos Extranjeros y No Propios

### Contexto del Excel "Propuesta reporte Calculo AF.xlsx"

El Excel de referencia utiliza esta regla para calcular el valor de activos utilizados en operaciones de maquila:

1. **Activos Extranjeros No Propios** (FLG_PROPIO = 0, ID_PAIS > 1)
2. **Activos Mexicanos No Propios** (FLG_PROPIO = 0, ID_PAIS = 1)

Estos activos, aunque no son propiedad de la empresa, se utilizan en la operación productiva y deben incluirse en el cálculo del Safe Harbor bajo el Artículo 182.

### Cálculo en el Contexto de Maquiladoras:

```
1. Calcular Saldo por Deducir ISR al inicio del año:
   Saldo_Inicio = MOI - Depreciación_Acumulada_Inicio_Año

2. Calcular Depreciación del Ejercicio:
   Dep_Ejercicio = MOI × Tasa_Anual × (Meses_Uso / 12)

3. Calcular Monto Pendiente al final del período:
   Monto_Pendiente = Saldo_Inicio - Dep_Ejercicio

4. Aplicar Regla del 10% (Art 182):
   Prueba_10_Pct = MOI × 0.10

   IF Monto_Pendiente < Prueba_10_Pct OR Monto_Pendiente <= 0 THEN
       Valor_Para_Safe_Harbor = Prueba_10_Pct
   ELSE
       Valor_Para_Safe_Harbor = Monto_Pendiente
   END IF

5. Para Safe Harbor, calcular:
   Base_Safe_Harbor = SUM(Valor_Para_Safe_Harbor de todos los activos)
   Ingreso_Fiscal = Base_Safe_Harbor × 0.069  (6.9%)
```

---

## Implicaciones Fiscales

### Ventajas de la Regla del 10%:

1. **Garantiza una base mínima** para el cálculo del Safe Harbor, incluso cuando los activos estén casi completamente depreciados
2. **Evita que la base imponible sea cercana a cero** para activos viejos
3. **Proporciona certeza fiscal** a las maquiladoras sobre su cálculo de utilidad fiscal

### Activos Totalmente Depreciados:

**Observación del Excel:** "Activo en uso prueba 10% MOI"

- Un activo completamente depreciado (Dep. Acum = 100% del MOI)
- Saldo por deducir ISR = $0
- **Se utiliza el 10% del MOI** como valor para el cálculo del Safe Harbor
- Esto asegura que los activos en uso, independientemente de su depreciación contable, contribuyan a la base del cálculo

### Activos Casi Depreciados:

Si el saldo por deducir es menor al 10% del MOI (por ejemplo, 5% o 8%), se "aumenta" artificialmente al 10% para efectos del cálculo del Safe Harbor.

---

## Diferencia con Depreciación Normal (Artículos 31-35 LISR)

| Concepto | Depreciación Normal | Artículo 182 (Maquiladoras) |
|----------|---------------------|------------------------------|
| **Aplica a** | Todas las empresas | Solo maquiladoras |
| **Propósito** | Calcular deducción anual | Calcular base para Safe Harbor |
| **Regla 10%** | No aplica | **SÍ aplica** |
| **Activos totalmente depreciados** | Valor = $0 | Valor mínimo = 10% MOI |
| **Base legal** | Arts. 31-35 | Art. 182 |

---

## Campos en Base de Datos para Aplicación

### Filtros para Identificar Activos Sujetos a Art. 182:

```sql
SELECT *
FROM activo
WHERE ID_COMPANIA = @IdCompania
  AND FLG_PROPIO = 0  -- No propios (arrendados/terceros)
  AND STATUS = 'A'    -- Activos
  -- Opcional: filtrar por tipo de empresa maquiladora
```

### Cálculo del 10% MOI:

```sql
SELECT
    a.ID_NUM_ACTIVO,
    a.COSTO_ADQUISICION AS MOI,
    COALESCE(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio,
    a.COSTO_ADQUISICION - COALESCE(c.ACUMULADO_HISTORICA, 0) AS Saldo_Por_Deducir,
    a.COSTO_ADQUISICION * 0.10 AS Prueba_10_Pct_MOI,
    CASE
        WHEN (a.COSTO_ADQUISICION - COALESCE(c.ACUMULADO_HISTORICA, 0)) < (a.COSTO_ADQUISICION * 0.10)
        THEN a.COSTO_ADQUISICION * 0.10
        ELSE a.COSTO_ADQUISICION - COALESCE(c.ACUMULADO_HISTORICA, 0)
    END AS Valor_Para_Calculo
FROM activo a
LEFT JOIN calculo c ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_ANO = @AñoAnterior
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
WHERE a.FLG_PROPIO = 0
  AND a.ID_COMPANIA = @IdCompania
```

---

## Referencias

1. **Ley del Impuesto Sobre la Renta (LISR)** - Artículo 182, Fracción I, Inciso a)
2. **Justia México** - [Artículos 179-184 LISR](https://mexico.justia.com/federales/leyes/ley-del-impuesto-sobre-la-renta/titulo-vi/capitulo-ii/)
3. **Cámara de Diputados** - [LISR PDF Oficial](https://www.diputados.gob.mx/LeyesBiblio/pdf/LISR.pdf)
4. **Excel de Referencia** - "Propuesta reporte Calculo AF.xlsx" (hojas: Activos Extranjeros y Activos Mexicanos)

---

## Resumen Ejecutivo

✅ **El 10% del MOI** es una regla específica del **Artículo 182 LISR** para maquiladoras
✅ Aplica a activos **no propios** utilizados en la operación
✅ Establece un **valor mínimo deducible** para el cálculo del Safe Harbor
✅ **"En ningún caso la deducción pendiente será inferior al 10% del monto de adquisición de los bienes"**
✅ Se aplica incluso a activos **totalmente depreciados** si aún están en uso

---

**Fecha de documento:** 2025-10-12
**Versión:** 1.0
**Actualizado para:** Ejercicio fiscal 2024-2025
