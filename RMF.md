# Documentación RMF - Cálculo de Impuestos sobre Activos Fijos

## Fuentes Consultadas

1. **Ley del Impuesto Sobre la Renta (LISR)** - Artículos 31-35
2. **Resolución Miscelánea Fiscal (RMF) 2024/2025** - SAT
3. **Código Fiscal de la Federación** - INPC

## 1. Marco Legal - LISR Artículo 31

### Artículo 31 - Deducciones Autorizadas para Inversiones

El Artículo 31 de la LISR establece las reglas generales para las deducciones de inversiones en activos fijos, gastos y cargos diferidos.

**Aspectos clave:**

- **Fracción I-III**: Define qué se considera inversión deducible (activos fijos, gastos diferidos, erogaciones realizadas en períodos preoperativos)
- **Fracción VI**: **CRÍTICO PARA ACTIVOS EXTRANJEROS** - Permite la deducción de inversiones en bienes de activo fijo, incluyendo:
  - Adaptaciones a instalaciones que impliquen adiciones o mejoras
  - **Construcciones en terrenos que no sean propiedad del contribuyente**
  - **Activos utilizados en territorio nacional pero de propiedad extranjera o de terceros**

### Aplicación a Activos Extranjeros

**Regla fundamental**: Los activos extranjeros utilizados en México son deducibles si cumplen:

1. Se utilicen en la actividad productiva del contribuyente en territorio nacional
2. Sean estrictamente indispensables para la actividad
3. Se registren contablemente
4. Se actualicen conforme al INPC

**Campo en base de datos**: `ID_PAIS`
- `ID_PAIS = 1` (México) → Activo Nacional
- `ID_PAIS > 1` (Otros países) → Activo Extranjero

## 2. Tasas de Depreciación - LISR Artículo 34

### Artículo 34 - Porcentajes Máximos de Deducción

El Artículo 34 establece los porcentajes máximos autorizados de depreciación fiscal anual:

| Tipo de Activo | Tasa Anual | Observaciones |
|----------------|------------|---------------|
| **Construcciones** | 5% - 10% | Varía según uso (administrativo vs industrial) |
| **Ferrocarriles** | 5% | Incluye vías férreas |
| **Mobiliario y Equipo de Oficina** | 10% | Incluye equipo de comunicación telefónica |
| **Equipo de Transporte** | 25% | Vehículos en general |
| **Equipo de Cómputo** | 30% | Hardware y periféricos |
| **Maquinaria y Equipo Industrial** | 10% - 35% | Varía según tipo de industria |
| **Dados, Troqueles, Moldes, Matrices** | 35% | Herramientas especializadas |
| **Comunicaciones Telefónicas** | 10% | Centrales, torres |
| **Comunicaciones Satelitales** | 10% | Equipos especializados |
| **Equipo de Radiocomunicación** | 25% | Incluye celular y radios |
| **Adaptaciones/Mejoras en Bienes Arrendados** | 100% | Se deprecia en el período que reste del contrato de arrendamiento |
| **Maquinaria y Equipo Generación Energía** | Varía | Depende de fuentes renovables vs convencionales |
| **Aviones** | Varía | Depende de uso (fumigación, carga, pasajeros) |
| **Embarcaciones** | Varía | Según tipo de uso |
| **Blindaje de Automóviles** | 25% | Mismo período que el vehículo |
| **Casas Prefabricadas Empleados** | 10% | Vivienda temporal |

### Artículo 35 - Tasas por Actividad Económica

El Artículo 35 establece porcentajes específicos según la actividad:

- **Industria Minera**: Varía según tipo de explotación (6% - 12%)
- **Industria Manufacturera**: 10% - 35% según maquinaria
- **Agricultura y Ganadería**: 10% - 100% (sistemas de riego hasta 100%)
- **Industria de la Construcción**: 10% - 35% para equipo especializado
- **Actividades de Transporte**: 25% equipo de transporte principal

**Campo en base de datos**: `ID_TIPO_DEP = 2` (Depreciación Fiscal)

## 3. Actualización de Valores con INPC

### ¿Qué es el INPC?

El **Índice Nacional de Precios al Consumidor (INPC)** es publicado mensualmente por el INEGI y se utiliza para actualizar los valores de activos fijos conforme a la inflación.

### Fórmula de Actualización

```
Valor Actualizado = Valor Original × (INPC Mes Actual / INPC Mes Adquisición)
```

### Reglas de Actualización (CFF Art. 17-A)

1. **Costo de Adquisición**: Se actualiza desde el mes de adquisición hasta el mes de cierre del ejercicio
2. **Depreciación Acumulada**: Se actualiza desde el mes en que se realizó cada deducción hasta el mes de cierre
3. **Valor Neto**: Costo actualizado menos depreciación acumulada actualizada
4. **Ganancia/Pérdida en Venta**: Se calcula con valores actualizados

### Tabla INPC2 en Base de Datos

```sql
SELECT * FROM INPC2
WHERE Id_Pais = @ID_PAIS
  AND Anio = @ANO
  AND Mes = @MES
  AND Id_Tipo_Dep = 2  -- Fiscal
```

**Campos clave:**
- `Anio`: Año del índice
- `Mes`: Mes del índice (1-12)
- `Id_Pais`: País (1=México)
- `Indice`: Valor del INPC
- `Id_Tipo_Dep`: 2 = Fiscal

## 4. Casos de Uso y Fórmulas

### Caso 1: Activo Nacional - Propio

**Criterios:**
- `ID_PAIS = 1` (México)
- `FLG_PROPIO = 1` (Propiedad de la empresa)

**Fórmula:**

```
1. Costo Actualizado = COSTO_ADQUISICION × (INPC_Actual / INPC_Compra)

2. Depreciación Anual = Costo Actualizado × Tasa_Depreciacion

3. Depreciación Acumulada Actualizada = Σ(Depreciación_Mensual × (INPC_Actual / INPC_Mes_Depreciacion))

4. Valor Neto = Costo Actualizado - Depreciación Acumulada Actualizada
```

### Caso 2: Activo Extranjero - Propio (Usado en México)

**Criterios:**
- `ID_PAIS > 1` (Extranjero)
- `FLG_PROPIO = 1`
- Utilizado en territorio nacional

**Fórmula:**

```
1. Convertir a Pesos MXN:
   Costo_MXN = COSTO_ADQUISICION × Tipo_Cambio_Histórico

2. Costo Actualizado = Costo_MXN × (INPC_Actual / INPC_Compra)

3. Depreciación = Costo Actualizado × Tasa_Depreciacion

4. Valor Neto = Costo Actualizado - Depreciación Acumulada Actualizada
```

**IMPORTANTE:** Se aplican las mismas tasas del Artículo 34 LISR, sin importar el país de origen.

### Caso 3: Activo Extranjero - Terceros (Arrendado/Comodato)

**Criterios:**
- `ID_PAIS > 1`
- `FLG_PROPIO = 0` (No es propiedad)
- Mejoras o adaptaciones realizadas

**Fórmula según Artículo 31 Fracción VI:**

```
1. Costo de Mejoras Actualizado = COSTO_MEJORAS × (INPC_Actual / INPC_Mejora)

2. Depreciación = Costo Mejoras Actualizado × 100% / Meses_Restantes_Contrato

3. Deducción Mensual = Depreciación / 12

4. Valor Neto = Costo Actualizado - Depreciación Acumulada
```

**Caso especial**: Si el contrato termina, el remanente se deduce al 100% en el último período.

### Caso 4: Activo Nacional - Terceros (Mejoras en Arrendamiento)

**Criterios:**
- `ID_PAIS = 1`
- `FLG_PROPIO = 0`
- Adaptaciones en inmuebles arrendados

**Fórmula:**

Igual que Caso 3, pero sin conversión de moneda.

## 5. Campos Críticos en Base de Datos

### Tabla `activo`

| Campo | Uso en Cálculo | Observaciones |
|-------|----------------|---------------|
| `ID_NUM_ACTIVO` | Identificador único | PK |
| `ID_PAIS` | **Determina si es nacional/extranjero** | 1=México, >1=Extranjero |
| `ID_COMPANIA` | Agrupación por empresa | Para reportes |
| `COSTO_ADQUISICION` | Base del cálculo | En moneda original |
| `ID_MONEDA` | Conversión a MXN | Si no es peso mexicano |
| `FECHA_COMPRA` | Mes/Año para INPC inicial | Crítico para actualización |
| `FLG_PROPIO` | Indica propiedad | 1=Propio, 0=Terceros |
| `FECHA_INICIO_DEP` | Inicio de depreciación | Puede diferir de FECHA_COMPRA |
| `ID_TIPO_ACTIVO` | Determina tasa Artículo 34 | Vincula con catálogo de tasas |

### Tabla `calculo`

| Campo | Uso | Observaciones |
|-------|-----|---------------|
| `ID_TIPO_DEP` | **Debe ser 2** | 2=Fiscal |
| `ID_ANO`, `ID_MES` | Período del cálculo | PK compuesto |
| `DEPRECIACION_FISCAL` | Monto depreciación del mes | Actualizado con INPC |
| `DEPRECIACION_ACUM_FISCAL` | Acumulado | Suma actualizada |

### Tabla `INPC2`

| Campo | Uso | Observaciones |
|-------|-----|---------------|
| `Anio`, `Mes` | Período | Para búsqueda |
| `Id_Pais` | País del índice | 1=México |
| `Indice` | Valor INPC | Base 100 |
| `Id_Tipo_Dep` | **Debe ser 2** | 2=Fiscal |

## 6. Proceso de Cálculo Recomendado

### Paso 1: Identificar Tipo de Activo

```sql
SELECT
    ID_NUM_ACTIVO,
    ID_PAIS,
    FLG_PROPIO,
    CASE
        WHEN ID_PAIS = 1 AND FLG_PROPIO = 1 THEN 'Nacional Propio'
        WHEN ID_PAIS = 1 AND FLG_PROPIO = 0 THEN 'Nacional Arrendado/Mejoras'
        WHEN ID_PAIS > 1 AND FLG_PROPIO = 1 THEN 'Extranjero Propio'
        WHEN ID_PAIS > 1 AND FLG_PROPIO = 0 THEN 'Extranjero Arrendado/Mejoras'
    END AS TipoActivo
FROM activo
WHERE ID_COMPANIA = @CompaniaID
```

### Paso 2: Obtener INPC

```sql
-- INPC del mes de compra
SELECT Indice AS INPC_Compra
FROM INPC2
WHERE Anio = YEAR(@FechaCompra)
  AND Mes = MONTH(@FechaCompra)
  AND Id_Pais = 1  -- México
  AND Id_Tipo_Dep = 2  -- Fiscal

-- INPC del mes actual
SELECT Indice AS INPC_Actual
FROM INPC2
WHERE Anio = @AnoCalculo
  AND Mes = @MesCalculo
  AND Id_Pais = 1
  AND Id_Tipo_Dep = 2
```

### Paso 3: Actualizar Costo

```csharp
decimal costoActualizado = costoAdquisicion * (inpcActual / inpcCompra);
```

### Paso 4: Calcular Depreciación

```csharp
decimal tasaDepreciacion = ObtenerTasaPorTipoActivo(idTipoActivo); // Del catálogo Art. 34
decimal depreciacionAnual = costoActualizado * tasaDepreciacion;
decimal depreciacionMensual = depreciacionAnual / 12;
```

### Paso 5: Actualizar Depreciación Acumulada

```csharp
decimal depreciacionAcumuladaActualizada = 0;

foreach (var mesDepreciacion in historicoDepreciaciones)
{
    decimal inpcMesDepreciacion = ObtenerINPC(mesDepreciacion.Ano, mesDepreciacion.Mes);
    decimal factorActualizacion = inpcActual / inpcMesDepreciacion;
    depreciacionAcumuladaActualizada += mesDepreciacion.Monto * factorActualizacion;
}
```

### Paso 6: Calcular Valor Neto

```csharp
decimal valorNeto = costoActualizado - depreciacionAcumuladaActualizada;
```

## 7. Reportes Requeridos

### Reporte 1: Resumen Activos Nacionales

**Agrupación:** Por ID_COMPANIA
**Filtro:** `ID_PAIS = 1`

```
Total Activos Nacionales: {count}
Costo Original Total: {sum(COSTO_ADQUISICION)}
Costo Actualizado Total: {sum(CostoActualizado)}
Depreciación Acumulada: {sum(DepreciacionAcumulada)}
Valor Neto Total: {sum(ValorNeto)}
```

### Reporte 2: Resumen Activos Extranjeros

**Agrupación:** Por ID_COMPANIA
**Filtro:** `ID_PAIS > 1`

```
Total Activos Extranjeros: {count}
Por País:
  - USA: {count where ID_PAIS=2} - Valor Neto: {sum}
  - Otros: ...
Costo Original Total (MXN): {sum(COSTO_ADQUISICION × TipoCambio)}
Costo Actualizado Total: {sum(CostoActualizado)}
Valor Neto Total: {sum(ValorNeto)}
```

### Reporte 3: Detalle Activos Extranjeros

**Columnas:**
- ID_NUM_ACTIVO
- Descripción
- País de Origen (nombre desde tabla `pais`)
- FLG_PROPIO (Propio/Arrendado)
- Fecha Compra
- Costo Original (Moneda Extranjera)
- Tipo Cambio Histórico
- Costo Original MXN
- INPC Compra
- INPC Actual
- Factor Actualización
- Costo Actualizado
- Tasa Depreciación
- Depreciación Acumulada Actualizada
- Valor Neto Actualizado

### Reporte 4: Detalle Activos Nacionales

Similar a Reporte 3 pero sin columnas de tipo de cambio.

## 8. Consideraciones Especiales

### 8.1 Activos en Moneda Extranjera

1. **Tipo de Cambio Histórico**: Se usa el TC del día de adquisición (campo `FECHA_COMPRA`)
2. **No Fluctuación Cambiaria**: Una vez convertido a MXN, no se ajusta el TC, solo se actualiza con INPC
3. **Campo ID_MONEDA**: Indica la moneda original del activo

### 8.2 Activos Totalmente Depreciados

- `Valor Neto = 0`
- Se mantienen en registros contables
- No generan más deducción fiscal
- Importante para auditorías

### 8.3 Activos en Construcción

- No se deprecian hasta que estén en uso (`FECHA_INICIO_DEP`)
- Pueden tener fecha de compra distinta a fecha de inicio de depreciación
- Verificar campo `FLG_EN_USO` o similar

### 8.4 Venta o Baja de Activos

**Cálculo de Ganancia/Pérdida:**

```
Precio Venta Actualizado = Precio_Venta × (INPC_Cierre / INPC_Venta)
Valor Neto Actualizado = (cálculo descrito arriba)

Ganancia/Pérdida = Precio Venta Actualizado - Valor Neto Actualizado
```

## 9. Referencias Legales

- **LISR Artículo 31**: Deducciones autorizadas
- **LISR Artículo 32**: Monto original de la inversión
- **LISR Artículo 33**: Porcientos máximos
- **LISR Artículo 34**: Por cientos de deducción (tabla de tasas)
- **LISR Artículo 35**: Por cientos por actividad económica
- **CFF Artículo 17-A**: Actualización de valores con INPC
- **RMF 2024/2025 Capítulo 2.1**: Deducciones de inversiones
- **RMF Regla 3.3.1.25**: Procedimiento para activos de terceros en territorio nacional

## 10. Validaciones Recomendadas

1. ✅ Verificar que `ID_TIPO_DEP = 2` (Fiscal)
2. ✅ Validar que existe INPC para mes de compra y mes de cálculo
3. ✅ Confirmar que `ID_PAIS` es válido (existe en tabla `pais`)
4. ✅ Validar tasa de depreciación según `ID_TIPO_ACTIVO` y Artículo 34
5. ✅ Para activos extranjeros: verificar `ID_MONEDA` y tipo de cambio
6. ✅ Fecha inicio depreciación <= Fecha actual
7. ✅ Depreciación acumulada <= Costo actualizado
8. ✅ Valor neto >= 0

---

**Documento generado para:** ActifRMF - Sistema de Cálculo de Impuestos sobre Activos Fijos
**Fecha:** 2025-10-12
**Versión:** 1.0
**Base Legal:** LISR 2024/2025, RMF 2024/2025
