# Diccionario de Datos - Sistema Actif

## Base de Datos: actif_web_CIMA_Dev

**Servidor:** dbdev.powerera.com

---

## Tablas Principales

### 1. activo

Tabla principal que almacena información de todos los activos fijos de la compañía.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_NUM_ACTIVO | int | 4 | ✓ | ✓ | No | ID único numérico autoincrementable del activo |
| ID_COMPANIA | smallint | 2 | | | Sí | Compañía a la que pertenece el activo |
| ID_ACTIVO | nvarchar | 80 | | | Sí | Código alfanumérico del activo (puede ser generado o manual) |
| ID_TIPO_ACTIVO | smallint | 2 | | | Sí | Clasificación principal del activo (ej: Maquinaria, Equipo, Mobiliario) |
| ID_SUBTIPO_ACTIVO | smallint | 2 | | | Sí | Subclasificación del activo |
| ID_CENTRO_COSTO | int | 4 | | | Sí | Centro de costo asignado al activo |
| ID_RESPONSABLE | int | 4 | | | Sí | ID del empleado responsable del activo |
| ID_MONEDA | smallint | 2 | | | Sí | Moneda en que se valuó el activo |
| ID_GRUPO_SIMULACION | smallint | 2 | | | Sí | Grupo para simulaciones |
| ID_SIGNIFICADO_ID | smallint | 2 | | | Sí | Significado del ID del activo |
| ID_ESTADO_ACTIVO | smallint | 2 | | | Sí | Estado del activo (Nuevo, Usado, etc.) |
| ID_RESPONSIVA | int | 4 | | | Sí | Número de responsiva asignada |
| ID_ACTIVO_MAESTRO | nvarchar | 40 | | | Sí | Activo maestro si forma parte de un conjunto |
| ID_PAIS | smallint | 2 | | | Sí | País donde se encuentra el activo |
| ID_EDIFICIO | smallint | 2 | | | Sí | Edificio/ubicación del activo |
| ID_PISO | smallint | 2 | | | Sí | Piso donde se ubica |
| ID_AREA | int | 4 | | | Sí | Área específica |
| ID_ZVI | smallint | 2 | | | Sí | Zona de Valor Inmobiliario |
| ID_SERIE | varchar | 80 | | | Sí | Número de serie del fabricante |
| DESCRIPCION | varchar | 600 | | | Sí | Descripción corta del activo |
| DESCR_LARGA | varchar | MAX | | | Sí | Descripción detallada |
| LUGAR_ESPECIFICO | nvarchar | 60 | | | Sí | Ubicación física específica |
| FECHA_BAJA | datetime | 8 | | | Sí | Fecha de baja del activo |
| FECHA_COMPRA | datetime | 8 | | | Sí | Fecha de adquisición/compra |
| FECHA_REVAL | datetime | 8 | | | Sí | Fecha de revaluación |
| FECHA_REEXP | datetime | 8 | | | Sí | Fecha de reexpresión |
| FECHA_INIC_DEPREC | datetime | 8 | | | Sí | Fecha inicio depreciación tipo 1 |
| FECHA_INIC_DEPREC2 | datetime | 8 | | | Sí | Fecha inicio depreciación tipo 2 |
| FECHA_INIC_DEPREC3 | datetime | 8 | | | Sí | Fecha inicio depreciación tipo 3 |
| FECHA_FORZA1 | datetime | 8 | | | Sí | Fecha forzada 1 (uso especial) |
| FECHA_FORZA2 | datetime | 8 | | | Sí | Fecha forzada 2 |
| FECHA_FORZA3 | datetime | 8 | | | Sí | Fecha forzada 3 |
| FECHA_FORZA4 | datetime | 8 | | | Sí | Fecha forzada 4 |
| COSTO_ADQUISICION | float | 8 | | | Sí | Costo original de adquisición |
| COSTO_REVALUADO | float | 8 | | | Sí | Costo después de revaluación |
| COSTO_REEXPRESADO | float | 8 | | | Sí | Costo reexpresado por inflación |
| PORCE_FORZA1 | float | 8 | | | Sí | Porcentaje forzado 1 |
| PORCE_FORZA2 | float | 8 | | | Sí | Porcentaje forzado 2 |
| MONTO_FORZA3 | float | 8 | | | Sí | Monto forzado 3 |
| MONTO_FORZA4 | float | 8 | | | Sí | Monto forzado 4 |
| PRECIO_VENTA | float | 8 | | | Sí | Precio de venta (si se dio de baja) |
| VIDA_UTIL | smallint | 2 | | | Sí | Vida útil en meses |
| VIDA_REMANENTE | smallint | 2 | | | Sí | Vida remanente en meses |
| **FLG_PROPIO** | **nvarchar** | **2** | | | **Sí** | **CRÍTICO: Indicador de ownership (S=Propio, N=Ajeno/Extranjero)** |
| FLG_IMPACT | nvarchar | 2 | | | Sí | Indicador de impacto |
| FLG_NOCAPITALIZABLE_1 | nvarchar | 2 | | | Sí | No capitalizable tipo 1 |
| FLG_NOCAPITALIZABLE_2 | nvarchar | 2 | | | Sí | No capitalizable tipo 2 |
| FLG_NOCAPITALIZABLE_3 | nvarchar | 2 | | | Sí | No capitalizable tipo 3 |
| STATUS | nvarchar | 2 | | | Sí | Estado: A=Activo, B=Baja, etc. |
| STATUS_MOVIM | nvarchar | 2 | | | Sí | Estado de movimiento |

**Relaciones:**
- Ninguna explícita en metadata (tabla principal)

**Notas importantes:**
- `FLG_PROPIO` es el campo clave para determinar si un activo es nacional o extranjero
- `COSTO_ADQUISICION` es la base para cálculos de impuestos
- Las fechas de depreciación pueden variar según el tipo (Contable, Fiscal, IFRS)

---

### 2. compania

Catálogo maestro de compañías/empresas en el sistema.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_COMPANIA | smallint | 2 | ✓ | ✓ | No | ID único de la compañía |
| NOMBRE | nvarchar | 120 | | | Sí | Nombre/razón social |
| RFC | nvarchar | 30 | | | Sí | Registro Federal de Contribuyentes |
| FECHA_INICIO_EJERC | datetime | 8 | | | Sí | Fecha de inicio del ejercicio fiscal |
| ID_POLIZA_SIG | int | 4 | | | Sí | Siguiente número de póliza |
| VALOR_CERO | smallint | 2 | | | Sí | Manejo de valores en cero |
| CALLE_NUMERO | nvarchar | 120 | | | Sí | Domicilio fiscal - calle y número |
| COLONIA | nvarchar | 120 | | | Sí | Colonia |
| DELEG_MPIO | nvarchar | 120 | | | Sí | Delegación o municipio |
| CODIGO_POSTAL | nvarchar | 10 | | | Sí | Código postal |
| ID_ESTADO | smallint | 2 | | | Sí | Estado/provincia |
| ID_SIG_RESPONSIVA | int | 4 | | | Sí | Siguiente número de responsiva |
| TELEFONO | nvarchar | 60 | | | Sí | Teléfono de contacto |
| CUENTA | nvarchar | 58 | | | Sí | Cuenta contable |
| ID_CONTABLE | nvarchar | 510 | | | Sí | Identificador contable |
| DIVISION | varchar | 250 | | | Sí | División de la empresa |
| Default_Id_Moneda | int | 4 | | | Sí | Moneda por defecto para nuevos activos |
| Default_Id_Pais | int | 4 | | | Sí | País por defecto |
| Default_TipoCambio | decimal | 9 (18,4) | | | Sí | Tipo de cambio por defecto |
| ID_TIPO_DEP_PRINCIPAL | int | 4 | | | Sí | Tipo de depreciación principal (1=Contable, 2=Fiscal, etc.) |
| rv | timestamp | 8 | | | No | Rowversion para control de concurrencia |
| RequerirDocumento | int | 4 | | | Sí | Bandera: requiere documento adjunto |
| RequerirAprobacion | int | 4 | | | Sí | Bandera: requiere aprobación de movimientos |
| PrefijoRFID | varchar | 50 | | | Sí | Prefijo para etiquetas RFID |

**Relaciones:**
- Padre de múltiples tablas (centro_costo, edificio, activo, etc.)

**Uso en ActifRMF:**
- Cada compañía tendrá configurado su propio connection string
- El sistema podrá procesar múltiples compañías en una sola ejecución

---

### 3. calculo

Tabla de cálculos históricos de depreciación. Almacena el cálculo mensual por cada activo, tipo de depreciación, mes y año.

**Primary Key compuesta:** (ID_COMPANIA, ID_ANO, ID_MES, ID_TIPO_DEP, ID_NUM_ACTIVO)

| Campo | Tipo | Tamaño | PK | Nulo | Descripción |
|-------|------|--------|-------|------|-------------|
| ID_COMPANIA | smallint | 2 | ✓ | No | Compañía |
| ID_ANO | smallint | 2 | ✓ | No | Año del cálculo (ej: 2024) |
| ID_MES | smallint | 2 | ✓ | No | Mes del cálculo (1-12) |
| ID_TIPO_DEP | smallint | 2 | ✓ | No | Tipo depreciación: 1=Contable, 2=Fiscal, 3=IFRS, etc. |
| ID_NUM_ACTIVO | int | 4 | ✓ | No | Activo al que corresponde |
| VALOR | smallint | 2 | | Sí | Valor especial |
| FACTOR | float | 8 | | Sí | Factor de cálculo |
| FACTO2 | float | 8 | | Sí | Factor 2 |
| FACTO3 | float | 8 | | Sí | Factor 3 |
| NUMERO | smallint | 2 | | Sí | Número auxiliar |
| FECHA_CORTE | datetime | 8 | | Sí | Fecha de corte del cálculo |
| VALOR_ADQUISICION | decimal | 9 (18,2) | | Sí | Valor de adquisición (snapshot) |
| VALOR_QUINTO | float | 8 | | Sí | Valor quinto (uso específico) |
| MENSUAL_HISTORICA | decimal | 9 (18,2) | | Sí | Depreciación mensual en costo histórico |
| MENSUAL_QUINTO | float | 8 | | Sí | Depreciación mensual quinto |
| ACUMULADO_HISTORICA | decimal | 9 (18,2) | | Sí | Depreciación acumulada histórica |
| ACUMULADO_QUINTO | float | 8 | | Sí | Depreciación acumulada quinto |
| EJERCICIO_HISTORICA | decimal | 9 (18,2) | | Sí | Depreciación del ejercicio histórica |
| EJERCICIO_QUINTO | float | 8 | | Sí | Depreciación del ejercicio quinto |
| FACTOR2 | float | 8 | | Sí | Factor 2 |
| FACTOR_ANT | float | 8 | | Sí | Factor anterior |
| NUMERO2 | smallint | 2 | | Sí | Número 2 |
| MENSUAL_CALCU | float | 8 | | Sí | Depreciación mensual calculada |
| EJERCICIO_CALCU | float | 8 | | Sí | Depreciación del ejercicio calculada |
| ACUMULADO_CALCU | float | 8 | | Sí | Depreciación acumulada calculada |
| FACTOR_UDIS | float | 8 | | Sí | Factor UDIS |
| FACTOR_UDAN | float | 8 | | Sí | Factor UDA anterior |
| ID_CENTRO_COSTO | int | 4 | | Sí | Centro de costo (snapshot del momento) |
| ID_EDIFICIO | int | 4 | | Sí | Edificio (snapshot) |
| ID_TIPO_ACTIVO | int | 4 | | Sí | Tipo de activo (snapshot) |
| ID_SUBTIPO_ACTIVO | int | 4 | | Sí | Subtipo de activo (snapshot) |
| STATUS | varchar | 1 | | Sí | Estado del cálculo |
| INPC_COMPRA | decimal | 9 (18,6) | | Sí | INPC (Índice Nacional de Precios al Consumidor) de compra |
| INPC_UTILIZADO | money | 8 (19,4) | | Sí | INPC utilizado en el cálculo |
| Paso | varchar | 5 | | Sí | Indicador de paso del proceso |
| Id_Activo | varchar | 40 | | Sí | ID alfanumérico del activo |
| AjusteAcumulado | decimal | 9 (18,2) | | Sí | Ajuste acumulado |
| AjusteEjercicio | decimal | 9 (18,2) | | Sí | Ajuste del ejercicio |
| FechaCaptura | datetime | 8 | | Sí | Fecha de captura del cálculo |
| INPCCompra | decimal | 9 (18,4) | | Sí | INPC de compra |
| INPCInicDeprec | decimal | 9 (18,4) | | Sí | INPC inicio depreciación |
| INPCMedio | decimal | 9 (18,4) | | Sí | INPC promedio |
| PasoINPC | varchar | 20 | | Sí | Paso del cálculo INPC |

**Relaciones:**
- `ID_COMPANIA` → compania.ID_COMPANIA

**Notas importantes:**
- Esta tabla es CRÍTICA para reportes fiscales
- Contiene el detalle mensual de depreciaciones
- Permite diferenciar entre tipos de depreciación (Contable vs Fiscal vs IFRS)
- Guarda snapshots de centro_costo y edificio del momento del cálculo

---

### 4. centro_costo

Catálogo de centros de costo por compañía.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_CENTRO_COSTO | int | 4 | ✓ | ✓ | No | ID único del centro de costo |
| ID_COMPANIA | smallint | 2 | | | Sí | Compañía (FK) |
| CODIGO | varchar | 10 | | | Sí | Código del centro de costo |
| DESCRIPCION | varchar | 250 | | | Sí | Nombre/descripción |
| RESPONSABLE | varchar | 250 | | | Sí | Responsable del centro de costo |
| STATUS | smallint | 2 | | | Sí | Estado (Activo/Inactivo) |
| CTA1 - CTA6 | nvarchar | 12 | | | Sí | Cuentas contables 1-6 |
| PRORRA | smallint | 2 | | | Sí | Prorrateo |
| TRANS_ENTRA | float | 8 | | | Sí | Transferencias que entran |
| TRANS_SALE | float | 8 | | | Sí | Transferencias que salen |
| BAJAS | float | 8 | | | Sí | Bajas del centro de costo |
| ALTAS | float | 8 | | | Sí | Altas del centro de costo |
| CTA11 - CTA16 | nvarchar | 12 | | | Sí | Cuentas contables adicionales |
| rv | timestamp | 8 | | | No | Rowversion |

**Relaciones:**
- `ID_COMPANIA` → compania.ID_COMPANIA (desde vista metadata)

---

### 5. edificio

Catálogo de edificios/ubicaciones físicas.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_COMPANIA | smallint | 2 | | | Sí | Compañía (FK) |
| ID_EDIFICIO | int | 4 | ✓ | ✓ | No | ID único del edificio |
| (Campos adicionales por consultar) | | | | | | |

**Relaciones:**
- `ID_COMPANIA` → compania.ID_COMPANIA (desde vista metadata)

---

### 6. moneda

Catálogo de monedas.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_MONEDA | smallint | 2 | ✓ | ✓ | No | ID único de la moneda |
| ID_PAIS | int | 4 | | | Sí | País asociado (FK) |
| NOMBRE | nvarchar | 40 | | | Sí | Nombre de la moneda (Peso, Dólar, Euro) |
| SIMBOLO | nvarchar | 8 | | | Sí | Símbolo ($, USD, EUR) |
| rv | timestamp | 8 | | | No | Rowversion |

**Relaciones:**
- `ID_PAIS` → pais.ID_PAIS (desde vista metadata)

---

### 7. pais

Catálogo de países.

| Campo | Tipo | Tamaño | PK | Identity | Nulo | Descripción |
|-------|------|--------|----|----|------|-------------|
| ID_PAIS | int | 4 | ✓ | ✓ | No | ID único del país |
| NOMBRE | nvarchar | 40 | | | Sí | Nombre del país (México, Estados Unidos, etc.) |

**Relaciones:**
- Padre de moneda

---

### 8. porcentaje_depreciacion

(Tabla aún no consultada en detalle - por documentar)

Probablemente contiene los porcentajes de depreciación aplicables por tipo de activo y tipo de depreciación.

---

## Diagrama de Relaciones (Simplificado)

```
compania (1) ----< (N) centro_costo
    |
    +----< (N) edificio
    |
    +----< (N) activo
                  |
                  +----< (N) calculo

pais (1) ----< (N) moneda
```

## Vistas Importantes

### vMetaData

Vista de sistema que expone metadatos de todas las tablas y sus columnas.

**Uso:**
```sql
SELECT * FROM vMetaData
WHERE TableName = 'activo'
ORDER BY Columna
```

**Columnas principales:**
- Column_Name: Nombre de la columna
- Type: Tipo de dato
- TableName: Tabla
- length: Tamaño
- Identitys: 1 si es Identity
- ForeignTable: Tabla relacionada (si aplica)
- CampoRelacion: Campo de relación
- CampoBusqueda: Campo de búsqueda en tabla relacionada
- PK: 1 si es primary key
- PermiteNulos: 1 si permite NULL
- Description: Descripción de extended properties

---

**Actualizado:** 2025-10-12
