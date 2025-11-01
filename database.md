# Diccionario de Datos - Sistema de Activos y Depreciación

Base de datos: `actif_web_cima_dev`
Servidor: `dbdev.powerera.com`

## Índice
1. [Tabla Principal: activo](#tabla-activo)
2. [Tablas de Catálogos](#tablas-de-catálogos)
3. [Tabla de Configuración: tipo_depreciacion](#tabla-tipo_depreciacion)
4. [Tabla de Porcentajes: porcentaje_depreciacion](#tabla-porcentaje_depreciacion)
5. [Tabla de Cálculos: calculo](#tabla-calculo)
6. [Sistema de Slots (AplicaFiscal)](#sistema-de-slots)

---

## Tabla: activo

Tabla principal que almacena la información de todos los activos fijos de la compañía.

### Campos de Identificación

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_NUM_ACTIVO | int | NO | **Llave primaria**. Identificador único numérico del activo |
| ID_ACTIVO | nvarchar(40) | YES | Código alfanumérico del activo (visible para usuarios) |
| ID_COMPANIA | smallint | YES | FK a tabla compania. Empresa a la que pertenece el activo |
| ID_TIPO_ACTIVO | smallint | YES | FK a tabla tipo_activo. Clasificación principal del activo |
| ID_SUBTIPO_ACTIVO | smallint | YES | FK a tabla subtipo_activo. Subclasificación del activo |
| ID_ESTADO_ACTIVO | smallint | YES | Estado actual del activo (Activo, Baja, etc.) |
| STATUS | nvarchar(1) | YES | Estado general del registro |
| STATUS_MOVIM | nvarchar(1) | YES | Estado de movimientos |

### Campos de Ubicación

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_CENTRO_COSTO | int | YES | FK a tabla centro_costo. Centro de costo asignado |
| ID_EDIFICIO | smallint | YES | FK a tabla edificio. Edificio donde se ubica |
| ID_PISO | smallint | YES | Piso dentro del edificio |
| ID_AREA | int | YES | FK a tabla area. Área específica dentro del edificio/piso |
| LUGAR_ESPECIFICO | nvarchar(30) | YES | Descripción adicional de ubicación |

### Campos de Responsabilidad

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_RESPONSABLE | int | YES | Persona responsable del activo |
| ID_RESPONSIVA | int | YES | Documento de responsiva |

### Campos Descriptivos

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| DESCRIPCION | varchar(600) | YES | Descripción corta del activo |
| DESCR_LARGA | varchar(MAX) | YES | Descripción detallada del activo |
| ID_SERIE | varchar(80) | YES | Número de serie del activo |

### Campos Financieros y de Moneda

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_MONEDA | smallint | YES | FK a tabla moneda. Moneda en que se registró el activo |
| ID_PAIS | smallint | YES | FK a tabla pais. País de origen/ubicación |

### **Campos de Costo (Sistema de Slots)**

Los costos se manejan en 4 "slots" diferentes, cada uno correspondiente a un tipo de depreciación (ver Sistema de Slots):

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **COSTO_ADQUISICION** | float | YES | **Slot 1** | **0** | Costo original de adquisición (Financiera) |
| **COSTO_REVALUADO** | float | YES | **Slot 2** | **1** | Costo revaluado (Fiscal) |
| **COSTO_REEXPRESADO** | float | YES | **Slot 3** | **2** | Costo reexpresado (USGAAP/Revaluada) |
| **COSTO_CALCULO4** | decimal | YES | **Slot 4** | **3** | Costo para cálculo 4 (Pesos Rev.Lineal u otros) |

### **Fechas de Inicio de Depreciación (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **FECHA_INIC_DEPREC** | datetime | YES | **Slot 1** | **0** | Fecha inicio depreciación financiera |
| **FECHA_INIC_DEPREC2** | datetime | YES | **Slot 2** | **1** | Fecha inicio depreciación fiscal |
| **FECHA_INIC_DEPREC3** | datetime | YES | **Slot 3** | **2** | Fecha inicio depreciación revaluada |
| **FECHA_INIC_DEPREC4** | date | YES | **Slot 4** | **3** | Fecha inicio depreciación cálculo 4 |

### **Fechas de Fin de Depreciación (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **Fecha_Fin_Deprec_1** | date | YES | **Slot 1** | **0** | Fecha fin depreciación financiera |
| **Fecha_Fin_Deprec_2** | date | YES | **Slot 2** | **1** | Fecha fin depreciación fiscal |
| **Fecha_Fin_Deprec_3** | date | YES | **Slot 3** | **2** | Fecha fin depreciación revaluada |
| **Fecha_Fin_Deprec_4** | date | YES | **Slot 4** | **3** | Fecha fin depreciación cálculo 4 |

### **Porcentajes de Depreciación Individuales (Sistema de Slots)**

Cuando estos campos están vacíos o en cero, el sistema toma los valores de la tabla `porcentaje_depreciacion` según el tipo/subtipo de activo.

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Año | Descripción |
|-------|------|------|------|--------------|-----|-------------|
| **DEPR_FINANCIERA_1** | decimal | YES | **Slot 1** | **0** | 1° año | Porcentaje depreciación financiera primer año |
| **DEPR_FINANCIERA_2** | decimal | YES | **Slot 1** | **0** | 2°+ años | Porcentaje depreciación financiera años siguientes |
| **DEPR_FISCAL_1** | decimal | YES | **Slot 2** | **1** | 1° año | Porcentaje depreciación fiscal primer año |
| **DEPR_FISCAL_2** | decimal | YES | **Slot 2** | **1** | 2°+ años | Porcentaje depreciación fiscal años siguientes |
| **DEPR_REVALUADA_1** | decimal | YES | **Slot 3** | **2** | 1° año | Porcentaje depreciación revaluada primer año |
| **DEPR_REVALUADA_2** | decimal | YES | **Slot 3** | **2** | 2°+ años | Porcentaje depreciación revaluada años siguientes |
| **DEPR_CALCULO4_1** | decimal | YES | **Slot 4** | **3** | 1° año | Porcentaje depreciación cálculo 4 primer año |
| **DEPR_CALCULO4_2** | decimal | YES | **Slot 4** | **3** | 2°+ años | Porcentaje depreciación cálculo 4 años siguientes |

### **Fechas de Forzamiento (Sistema de Slots)**

Fechas en las que se fuerza un ajuste manual al costo del activo.

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **FECHA_FORZA1** | datetime | YES | **Slot 1** | **0** | Fecha forzamiento financiera |
| **FECHA_FORZA2** | datetime | YES | **Slot 2** | **1** | Fecha forzamiento fiscal |
| **FECHA_FORZA3** | datetime | YES | **Slot 3** | **2** | Fecha forzamiento revaluada |
| **FECHA_FORZA4** | datetime | YES | **Slot 4** | **3** | Fecha forzamiento cálculo 4 |
| **FECHA_FORZA_CALCULO4** | date | YES | **Slot 4** | **3** | Fecha forzamiento cálculo 4 (alternativo) |

### **Montos de Forzamiento (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **PORCE_FORZA1** | float | YES | **Slot 1** | **0** | Porcentaje/Monto forzamiento 1 |
| **PORCE_FORZA2** | float | YES | **Slot 2** | **1** | Porcentaje/Monto forzamiento 2 |
| **MONTO_FORZA3** | float | YES | **Slot 3** | **2** | Monto forzamiento 3 |
| **MONTO_FORZA4** | float | YES | **Slot 4** | **3** | Monto forzamiento 4 |
| **MONTO_FORZA_CALCULO4** | decimal | YES | **Slot 4** | **3** | Monto forzamiento cálculo 4 (alternativo) |

### **Flags de No Capitalizable (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **FLG_NOCAPITALIZABLE_1** | nvarchar(1) | YES | **Slot 1** | **0** | Flag no capitalizable financiera |
| **FLG_NOCAPITALIZABLE_2** | nvarchar(1) | YES | **Slot 2** | **1** | Flag no capitalizable fiscal |
| **FLG_NOCAPITALIZABLE_3** | nvarchar(1) | YES | **Slot 3** | **2** | Flag no capitalizable revaluada |
| **FLG_NOCAPITALIZABLE_4** | varchar(1) | YES | **Slot 4** | **3** | Flag no capitalizable cálculo 4 |
| **FLG_NOCAPITALIZABLE_5** | varchar(1) | YES | - | - | Flag no capitalizable adicional |

### **Ajustes Automáticos (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **AJUSTE_AUTOMATICO_1** | bit | YES | **Slot 1** | **0** | Activa ajuste automático financiera |
| **AJUSTE_AUTOMATICO_2** | bit | YES | **Slot 2** | **1** | Activa ajuste automático fiscal |
| **AJUSTE_AUTOMATICO_3** | bit | YES | **Slot 3** | **2** | Activa ajuste automático revaluada |
| **AJUSTE_AUTOMATICO_4** | bit | YES | **Slot 4** | **3** | Activa ajuste automático cálculo 4 |

### **Tipos de Cambio (Sistema de Slots)**

| Campo | Tipo | Nulo | Slot | AplicaFiscal | Descripción |
|-------|------|------|------|--------------|-------------|
| **TIPO_CAMBIO1** | decimal | YES | **Slot 1** | **0** | Tipo de cambio financiera |
| **TIPO_CAMBIO2** | decimal | YES | **Slot 2** | **1** | Tipo de cambio fiscal |
| **TIPO_CAMBIO3** | decimal | YES | **Slot 3** | **2** | Tipo de cambio revaluada |
| **TIPO_CAMBIO4** | decimal | YES | **Slot 4** | **3** | Tipo de cambio cálculo 4 |

### Otras Fechas Importantes

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| FECHA_COMPRA | datetime | YES | Fecha de compra del activo |
| FECHA_BAJA | datetime | YES | Fecha de baja del activo |
| FECHA_REVAL | datetime | YES | Fecha de revaluación |
| FECHA_REVAL2 | datetime | YES | Fecha de segunda revaluación |
| FECHA_REEXP | datetime | YES | Fecha de reexpresión |
| FECHA_ACELERA | datetime | YES | Fecha de aceleración de depreciación |
| FECHA_ALTA | date | YES | Fecha de alta en el sistema |
| FECHACAPTURA | datetime | YES | Fecha y hora de captura del registro |

### Control de Depreciación

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| MES_DEPRECIADO | int | YES | Último mes depreciado |
| ANO_DEPRECIADO | int | YES | Último año depreciado |
| VIDA_UTIL | smallint | YES | Vida útil en meses |
| VIDA_REMANENTE | smallint | YES | Vida remanente en meses |
| VALOR_RESIDUAL | float | YES | Valor residual del activo al final de su vida útil |
| PRECIO_VENTA | float | YES | Precio de venta (si aplica) |

### Campos Adicionales de Costo

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| COSTO_REVALUADO2 | decimal | YES | Segunda revaluación de costo |

### Campos de Simulación y Agrupación

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_GRUPO_SIMULACION | smallint | YES | Grupo de simulación para escenarios |
| ID_SIGNIFICADO_ID | smallint | YES | Significado del ID del activo |
| ID_ZVI | smallint | YES | Zona de Valor Inmobiliario |

### Campos de Relación con Otros Activos

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_ACTIVO_MAESTRO | nvarchar(20) | YES | ID del activo maestro (si es componente) |
| ID_NUM_ACTIVO2 | int | YES | Relación con otro activo |
| Id_Num_Activo_Anterior | int | YES | ID del activo anterior (cambios) |
| Id_num_activo_origen_split | int | YES | ID del activo origen en caso de split |
| Fecha_Split | date | YES | Fecha en que se realizó el split |
| Proporcion_Split | decimal | YES | Proporción del split |

### Campos de Control y Auditoría

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| ID_USUARIO_CAPTURA | int | YES | Usuario que capturó el registro |
| Id_Edificio_Alta | int | YES | Edificio donde se dio de alta |
| RFID | varchar(250) | YES | Código RFID del activo |
| rv | timestamp | NO | Timestamp de SQL Server para control de concurrencia |

### Campos de Propósito General (CONTROL1-40)

El sistema incluye 40 campos genéricos (CONTROL1 a CONTROL40) tipo varchar para almacenar información adicional configurable:

| Campos | Tipo | Longitud |
|--------|------|----------|
| CONTROL1-CONTROL6 | varchar | 250 |
| CONTROL7-CONTROL10 | varchar | 500 |
| CONTROL11-CONTROL30 | varchar | 250 |
| Control31-Control40 | varchar | 250 |

### Flags y Características

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| FLG_PROPIO | nvarchar(1) | YES | Indica si el activo es propio o arrendado |
| FLG_IMPACT | nvarchar(1) | YES | Indica si impacta en ciertos cálculos |
| ID_SUBTIPO_MOV | smallint | YES | Subtipo de movimiento |

### Campo Memo

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| CAMPO_MEMO | varchar(MAX) | YES | Campo de texto libre para notas adicionales |

---

## Tablas de Catálogos

### Tabla: compania

Define las compañías o empresas que forman parte del sistema.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_COMPANIA** | smallint | NO | **PK**. Identificador único de la compañía |
| NOMBRE | nvarchar(60) | YES | Nombre de la compañía |
| RFC | nvarchar(15) | YES | Registro Federal de Contribuyentes |
| FECHA_INICIO_EJERC | datetime | YES | Fecha de inicio del ejercicio fiscal |
| ID_POLIZA_SIG | int | YES | Siguiente número de póliza |
| ID_SIG_RESPONSIVA | int | YES | Siguiente número de responsiva |
| VALOR_CERO | smallint | YES | Valor por defecto para ciertos cálculos |

#### Campos de Dirección

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| CALLE_NUMERO | nvarchar(60) | YES | Calle y número |
| COLONIA | nvarchar(60) | YES | Colonia |
| DELEG_MPIO | nvarchar(60) | YES | Delegación o Municipio |
| CODIGO_POSTAL | nvarchar(5) | YES | Código Postal |
| ID_ESTADO | smallint | YES | Estado de la República |
| TELEFONO | nvarchar(30) | YES | Teléfono de contacto |

#### Campos Contables

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| CUENTA | nvarchar(29) | YES | Cuenta contable principal |
| ID_CONTABLE | nvarchar(255) | YES | Identificador contable |
| DIVISION | varchar(250) | YES | División de la compañía |

#### Configuración por Defecto

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| Default_Id_Moneda | int | YES | Moneda por defecto |
| Default_Id_Pais | int | YES | País por defecto |
| Default_TipoCambio | decimal | YES | Tipo de cambio por defecto |
| **ID_TIPO_DEP_PRINCIPAL** | int | YES | **Tipo de depreciación principal de la compañía** |

#### Configuración de Workflow

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| RequerirDocumento | int | YES | Indica si requiere documentos adjuntos |
| RequerirAprobacion | int | YES | Indica si requiere aprobación |

#### RFID

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| PrefijoRFID | varchar(50) | YES | Prefijo para códigos RFID |

#### Control

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: centro_costo

Define los centros de costo para la asignación de activos y gastos.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_CENTRO_COSTO** | int | NO | **PK**. Identificador único del centro de costo |
| ID_COMPANIA | smallint | YES | FK a compania |
| CODIGO | varchar(10) | YES | Código corto del centro de costo |
| DESCRIPCION | varchar(250) | YES | Descripción del centro de costo |
| RESPONSABLE | varchar(250) | YES | Responsable del centro de costo |
| STATUS | smallint | YES | Estado (Activo/Inactivo) |

#### Cuentas Contables

El centro de costo puede tener múltiples cuentas contables asociadas para diferentes tipos de movimientos:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| CTA1-CTA6 | nvarchar(6) | Cuentas contables para depreciación |
| CTA11-CTA16 | nvarchar(6) | Cuentas contables adicionales |

#### Configuración de Movimientos

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| PRORRA | smallint | YES | Configuración de prorrateo |
| TRANS_ENTRA | float | YES | Transferencias que entran |
| TRANS_SALE | float | YES | Transferencias que salen |
| BAJAS | float | YES | Valor de bajas |
| ALTAS | float | YES | Valor de altas |

#### Control

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: tipo_activo

Clasificación principal de los activos (ej: Mobiliario, Equipo de Cómputo, Vehículos, etc.)

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_TIPO_ACTIVO** | smallint | NO | **PK**. Identificador único del tipo de activo |
| ID_COMPANIA | smallint | YES | FK a compania (puede ser NULL para tipos genéricos) |
| DESCRIPCION | varchar(250) | YES | Descripción del tipo de activo |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: subtipo_activo

Subclasificación de los activos dentro de cada tipo.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_SUBTIPO_ACTIVO** | int | NO | **PK**. Identificador único del subtipo |
| **ID_TIPO_ACTIVO** | smallint | NO | **FK** a tipo_activo. Tipo al que pertenece |
| DESCRIPCION | nvarchar(40) | YES | Descripción del subtipo |
| Codigo | varchar(6) | YES | Código corto del subtipo |
| ACTUALIZAR | nvarchar(1) | YES | Flag de actualización |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: pais

Catálogo de países.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_PAIS** | int | NO | **PK**. Identificador único del país |
| NOMBRE | nvarchar(20) | YES | Nombre del país |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: moneda

Catálogo de monedas.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_MONEDA** | smallint | NO | **PK**. Identificador único de la moneda |
| ID_PAIS | int | YES | FK a pais. País de la moneda |
| NOMBRE | nvarchar(20) | YES | Nombre de la moneda (ej: Peso Mexicano, Dólar) |
| SIMBOLO | nvarchar(4) | YES | Símbolo de la moneda (ej: $, USD) |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: edificio

Catálogo de edificios o ubicaciones físicas principales.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_EDIFICIO** | int | NO | **PK**. Identificador único del edificio |
| ID_COMPANIA | smallint | YES | FK a compania |
| DESCRIPCION | nvarchar(200) | YES | Nombre/descripción del edificio |

#### Dirección

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| CALLE_NUMERO | nvarchar(60) | YES | Calle y número |
| COLONIA | nvarchar(60) | YES | Colonia |
| CIUDAD | varchar(250) | YES | Ciudad |
| DELEG_MPIO | nvarchar(60) | YES | Delegación o Municipio |
| CODIGO_POSTAL | nvarchar(5) | YES | Código Postal |
| ID_ESTADO | smallint | YES | Estado de la República |
| TELEFONO | nvarchar(30) | YES | Teléfono |

#### Cuentas Contables

| Campo | Tipo | Descripción |
|-------|------|-------------|
| CTA1-CTA6 | nvarchar(6) | Cuentas contables para el edificio |

#### Control

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| INACTIVO | int | YES | Indica si el edificio está inactivo |
| Id_Edificio_Orig | int | YES | ID original (para migraciones) |
| Id_Compania_Orig | int | YES | Compañía original (para migraciones) |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

### Tabla: area

Áreas o departamentos dentro de un edificio.

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_AREA** | int | NO | **PK**. Identificador único del área |
| ID_COMPANIA | int | YES | FK a compania |
| ID_EDIFICIO | int | YES | FK a edificio |
| ID_PISO | int | YES | Piso dentro del edificio |
| DESCRIPCION | nvarchar(40) | YES | Descripción del área |

#### Cuentas Contables

| Campo | Tipo | Descripción |
|-------|------|-------------|
| CTA1-CTA6 | nvarchar(6) | Cuentas contables para el área |

#### Control

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| Id_Area_Orig | int | YES | ID original (para migraciones) |
| rv | timestamp | NO | Timestamp para control de concurrencia |

---

## Tabla: tipo_depreciacion

Define los diferentes tipos de depreciación que se pueden aplicar a los activos. **Esta tabla es fundamental para el sistema de slots.**

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_TIPO_DEP** | smallint | NO | **PK**. Identificador único del tipo de depreciación |
| DESCRIPCION | nvarchar(20) | YES | Descripción del tipo de depreciación |
| MES_INI | smallint | YES | Mes de inicio del ejercicio fiscal |
| **AplicaFiscal** | int | YES | **Campo crítico que determina qué slot utiliza (0-3)** |

### Valores de AplicaFiscal y Slots

| AplicaFiscal | Slot | Nombre Común | Campos de Costo | Campos de % | Descripción |
|--------------|------|--------------|-----------------|-------------|-------------|
| **0** | **1** | Financiera / Adquisición | COSTO_ADQUISICION | DEPR_FINANCIERA_1/2 | Depreciación financiera basada en costo de adquisición |
| **1** | **2** | Fiscal | COSTO_REVALUADO | DEPR_FISCAL_1/2 | Depreciación fiscal basada en costo revaluado |
| **2** | **3** | USGAAP / Revaluada | COSTO_REEXPRESADO | DEPR_REVALUADA_1/2 | Depreciación bajo normas USGAAP o revaluada |
| **3** | **4** | Cálculo 4 / Pesos Rev. | COSTO_CALCULO4 | DEPR_CALCULO4_1/2 | Cálculo adicional (Pesos Revaluados Lineal u otros) |

### Ejemplos de Registros

```
ID_TIPO_DEP | DESCRIPCION            | MES_INI | AplicaFiscal
------------|------------------------|---------|-------------
1           | Updated 638959999370   | 1       | 0
2           | Fiscal Lineal          | 1       | 1
3           | Pesos Lineal           | 0       | 0
6           | USGAAP                 | 1       | 2
7           | Pesos Rev.Lineal       | 0       | 3
8           | USGAAP Lineal          | 1       | 2
```

---

## Tabla: porcentaje_depreciacion

Define los porcentajes de depreciación por defecto para cada combinación de tipo de activo, subtipo y tipo de depreciación.

**Cuando los campos DEPR_xxx_1 y DEPR_xxx_2 del activo están vacíos o en cero, el sistema toma los valores de esta tabla.**

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_PORCEN** | int | NO | **PK**. Identificador único del registro de porcentaje |
| **ID_TIPO_DEP** | smallint | YES | **FK** a tipo_depreciacion |
| **ID_TIPO_ACTIVO** | smallint | YES | **FK** a tipo_activo |
| **ID_SUBTIPO_ACTIVO** | smallint | YES | **FK** a subtipo_activo |
| DESCRIPCION | nvarchar(35) | YES | Descripción del porcentaje |
| **PORC_BENEFICIO** | decimal | YES | **Porcentaje a aplicar en el primer año** |
| **PORC_SEGUNDO_ANO** | decimal | YES | **Porcentaje a aplicar del segundo año en adelante** |
| NUM_ANOS_DEPRECIAR | smallint | YES | Número de años para depreciar completamente |
| FECHA_INICIO | datetime | YES | Fecha de inicio de vigencia |
| FECHA_FIN | datetime | YES | Fecha de fin de vigencia (NULL = vigente) |
| upsize_ts | timestamp | YES | Timestamp de actualización |

### Lógica de Aplicación

1. **Si el activo tiene** `DEPR_xxx_1` **o** `DEPR_xxx_2` **con valor > 0**:
   - Se usa el porcentaje individual del activo

2. **Si el activo NO tiene** estos valores (NULL o 0):
   - Se busca en `porcentaje_depreciacion` por:
     - `ID_TIPO_DEP` (del tipo de depreciación actual)
     - `ID_TIPO_ACTIVO` (del activo)
     - `ID_SUBTIPO_ACTIVO` (del activo)
     - Que la fecha actual esté entre `FECHA_INICIO` y `FECHA_FIN`
   - Se usa `PORC_BENEFICIO` para el primer año
   - Se usa `PORC_SEGUNDO_ANO` para los años siguientes

### Ejemplo de Código en Stored Procedure

```sql
-- Selección de porcentaje según si el activo tiene valor individual o no
CASE
    WHEN @AplicaFiscal = 0 THEN NULLIF(a.DEPR_FINANCIERA_1, 0)
    WHEN @AplicaFiscal = 1 THEN NULLIF(a.DEPR_FISCAL_1, 0)
    WHEN @AplicaFiscal = 2 THEN NULLIF(a.DEPR_REVALUADA_1, 0)
    WHEN @AplicaFiscal = 3 THEN NULLIF(a.DEPR_CALCULO4_1, 0)
END

-- Si es NULL, entonces se usa porcentaje_depreciacion.PORC_BENEFICIO o PORC_SEGUNDO_ANO
```

---

## Tabla: calculo

Almacena los cálculos de depreciación mensual para cada activo. **Esta es la tabla de resultados donde se guardan todas las depreciaciones calculadas.**

### Llaves Compuestas (PK)

La tabla se identifica por la combinación de:

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ID_COMPANIA** | smallint | NO | **PK**. Compañía |
| **ID_ANO** | smallint | NO | **PK**. Año del cálculo |
| **ID_MES** | smallint | NO | **PK**. Mes del cálculo (1-12) |
| **ID_TIPO_DEP** | smallint | NO | **PK**. Tipo de depreciación aplicado |
| **ID_NUM_ACTIVO** | int | NO | **PK**. Activo sobre el cual se calculó |

### Campos de Identificación Adicional

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| Id_Activo | varchar(40) | YES | Código alfanumérico del activo (desnormalizado) |
| ID_CENTRO_COSTO | int | YES | Centro de costo del activo (desnormalizado) |
| ID_EDIFICIO | int | YES | Edificio del activo (desnormalizado) |
| ID_TIPO_ACTIVO | int | YES | Tipo de activo (desnormalizado) |
| ID_SUBTIPO_ACTIVO | int | YES | Subtipo de activo (desnormalizado) |
| STATUS | varchar(1) | YES | Estado del cálculo |

### Campos de Control de Fecha

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| FECHA_CORTE | datetime | YES | Fecha de corte del cálculo (último día del mes) |
| FechaCaptura | datetime | YES | Fecha y hora en que se realizó el cálculo |

### Campos de Valor del Activo

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| VALOR | smallint | YES | Valor de control |
| VALOR_ADQUISICION | decimal | YES | Valor de adquisición del activo en ese momento |
| VALOR_QUINTO | float | YES | Valor relacionado con cálculos fiscales |

### Campos de Depreciación Mensual

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **MENSUAL_HISTORICA** | decimal | YES | **Depreciación del mes actual** |
| MENSUAL_QUINTO | float | YES | Depreciación mensual en quinto método |
| MENSUAL_CALCU | float | YES | Depreciación mensual calculada |

### Campos de Depreciación Acumulada

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **ACUMULADO_HISTORICA** | decimal | YES | **Depreciación acumulada total hasta este mes** |
| ACUMULADO_QUINTO | float | YES | Depreciación acumulada en quinto método |
| ACUMULADO_CALCU | float | YES | Depreciación acumulada calculada |

### Campos de Depreciación del Ejercicio

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| **EJERCICIO_HISTORICA** | decimal | YES | **Depreciación acumulada en el ejercicio actual** |
| EJERCICIO_QUINTO | float | YES | Depreciación del ejercicio en quinto método |
| EJERCICIO_CALCU | float | YES | Depreciación del ejercicio calculada |

### Campos de Ajustes

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| AjusteAcumulado | decimal | YES | Ajuste acumulado aplicado |
| AjusteEjercicio | decimal | YES | Ajuste del ejercicio actual |

### Factores de Cálculo

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| FACTOR | float | YES | Factor principal de cálculo |
| FACTO2 | float | YES | Factor secundario |
| FACTO3 | float | YES | Factor terciario |
| FACTOR2 | float | YES | Factor 2 |
| FACTOR_ANT | float | YES | Factor anterior |
| FACTOR_UDIS | float | YES | Factor UDIS |
| FACTOR_UDAN | float | YES | Factor UDAN |

### Campos Numéricos de Control

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| NUMERO | smallint | YES | Número de control |
| NUMERO2 | smallint | YES | Número de control secundario |

### Campos de INPC (Índice Nacional de Precios al Consumidor)

Para cálculos de reexpresión inflacionaria:

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| INPC_COMPRA | decimal | YES | INPC a la fecha de compra |
| INPCCompra | decimal | YES | INPC a la fecha de compra (duplicado) |
| INPC_UTILIZADO | money | YES | INPC utilizado en el cálculo |
| INPCInicDeprec | decimal | YES | INPC al inicio de depreciación |
| INPCMedio | decimal | YES | INPC medio del periodo |

### Campos de Paso/Proceso

| Campo | Tipo | Nulo | Descripción |
|-------|------|------|-------------|
| Paso | varchar(5) | YES | Indicador del paso del proceso |
| PasoINPC | varchar(20) | YES | Indicador del paso de cálculo INPC |

### Interpretación de Campos Principales

**Ejemplo para un activo en Enero 2024:**

- `MENSUAL_HISTORICA`: Depreciación de Enero 2024 = $1,000
- `EJERCICIO_HISTORICA`: Depreciación acumulada del año 2024 = $1,000 (solo enero)
- `ACUMULADO_HISTORICA`: Depreciación total desde que inició la depreciación = $25,000

**Ejemplo para el mismo activo en Febrero 2024:**

- `MENSUAL_HISTORICA`: Depreciación de Febrero 2024 = $1,000
- `EJERCICIO_HISTORICA`: Depreciación acumulada del año 2024 = $2,000 (enero + febrero)
- `ACUMULADO_HISTORICA`: Depreciación total desde que inició = $26,000

---

## Sistema de Slots (AplicaFiscal)

El sistema maneja **4 "slots" o espacios paralelos** para calcular la depreciación de diferentes formas simultáneamente sobre el mismo activo. Cada slot tiene sus propios campos en la tabla `activo`.

### Concepto

Un mismo activo puede depreciarse de 4 formas distintas al mismo tiempo:
1. **Slot 1 (AplicaFiscal=0)**: Depreciación Financiera
2. **Slot 2 (AplicaFiscal=1)**: Depreciación Fiscal
3. **Slot 3 (AplicaFiscal=2)**: Depreciación USGAAP/Revaluada
4. **Slot 4 (AplicaFiscal=3)**: Depreciación Cálculo 4

Cada slot utiliza:
- Su propio **costo base**
- Su propia **fecha de inicio de depreciación**
- Sus propios **porcentajes de depreciación**
- Sus propias **fechas y montos de forzamiento**
- Sus propios **tipos de cambio**
- Sus propios **flags de configuración**

### Mapeo Completo de Campos por Slot

| Concepto | Slot 1 (AF=0) | Slot 2 (AF=1) | Slot 3 (AF=2) | Slot 4 (AF=3) |
|----------|---------------|---------------|---------------|---------------|
| **Nombre Común** | Financiera | Fiscal | Revaluada | Cálculo 4 |
| **Costo Base** | COSTO_ADQUISICION | COSTO_REVALUADO | COSTO_REEXPRESADO | COSTO_CALCULO4 |
| **Fecha Inicio Dep.** | FECHA_INIC_DEPREC | FECHA_INIC_DEPREC2 | FECHA_INIC_DEPREC3 | FECHA_INIC_DEPREC4 |
| **Fecha Fin Dep.** | Fecha_Fin_Deprec_1 | Fecha_Fin_Deprec_2 | Fecha_Fin_Deprec_3 | Fecha_Fin_Deprec_4 |
| **% Año 1** | DEPR_FINANCIERA_1 | DEPR_FISCAL_1 | DEPR_REVALUADA_1 | DEPR_CALCULO4_1 |
| **% Año 2+** | DEPR_FINANCIERA_2 | DEPR_FISCAL_2 | DEPR_REVALUADA_2 | DEPR_CALCULO4_2 |
| **Fecha Forzamiento** | FECHA_FORZA1 | FECHA_FORZA2 | FECHA_FORZA3 | FECHA_FORZA4 |
| **Monto Forzamiento** | PORCE_FORZA1 | PORCE_FORZA2 | MONTO_FORZA3 | MONTO_FORZA4 |
| **Tipo de Cambio** | TIPO_CAMBIO1 | TIPO_CAMBIO2 | TIPO_CAMBIO3 | TIPO_CAMBIO4 |
| **Flag No Capital.** | FLG_NOCAPITALIZABLE_1 | FLG_NOCAPITALIZABLE_2 | FLG_NOCAPITALIZABLE_3 | FLG_NOCAPITALIZABLE_4 |
| **Ajuste Automático** | AJUSTE_AUTOMATICO_1 | AJUSTE_AUTOMATICO_2 | AJUSTE_AUTOMATICO_3 | AJUSTE_AUTOMATICO_4 |

### Ejemplo en Stored Procedure

El stored procedure `usp_calculoenrique` usa el parámetro `@AplicaFiscal` para determinar qué campos usar:

```sql
-- Determinar qué costo base usar
CASE
    WHEN @AplicaFiscal = 0 THEN a.COSTO_ADQUISICION
    WHEN @AplicaFiscal = 1 THEN a.COSTO_REVALUADO
    WHEN @AplicaFiscal = 2 THEN a.COSTO_REEXPRESADO
    WHEN @AplicaFiscal = 3 THEN a.COSTO_CALCULO4
END

-- Determinar qué porcentaje usar
CASE
    WHEN @AplicaFiscal = 0 THEN a.DEPR_FINANCIERA_1
    WHEN @AplicaFiscal = 1 THEN a.DEPR_FISCAL_1
    WHEN @AplicaFiscal = 2 THEN a.DEPR_REVALUADA_1
    WHEN @AplicaFiscal = 3 THEN a.DEPR_CALCULO4_1
END

-- Determinar qué fecha de inicio usar
CASE
    WHEN @AplicaFiscal = 0 THEN a.FECHA_INIC_DEPREC
    WHEN @AplicaFiscal = 1 THEN a.FECHA_INIC_DEPREC2
    WHEN @AplicaFiscal = 2 THEN a.FECHA_INIC_DEPREC3
    WHEN @AplicaFiscal = 3 THEN a.FECHA_INIC_DEPREC4
END
```

### Ventajas del Sistema de Slots

1. **Flexibilidad**: Permite depreciar el mismo activo bajo diferentes normas contables simultáneamente
2. **Trazabilidad**: Cada cálculo se guarda en la tabla `calculo` con su `ID_TIPO_DEP` correspondiente
3. **Independencia**: Los cálculos no se afectan entre sí
4. **Adaptabilidad**: Se pueden agregar nuevos tipos de depreciación sin cambiar la estructura
5. **Compliance**: Permite cumplir con diferentes normativas (GAAP, IFRS, Fiscal) al mismo tiempo

### Ejemplo Práctico

**Activo: Computadora HP - ID_NUM_ACTIVO = 12345**

| Slot | Tipo Dep | Costo Base | Fecha Inicio | % Anual | Uso |
|------|----------|------------|--------------|---------|-----|
| 1 (AF=0) | Financiera | $10,000 (COSTO_ADQUISICION) | 01/01/2024 | 25% | Reportes internos |
| 2 (AF=1) | Fiscal | $10,000 (COSTO_REVALUADO) | 01/01/2024 | 30% | Declaraciones fiscales |
| 3 (AF=2) | USGAAP | $12,000 (COSTO_REEXPRESADO) | 01/01/2024 | 20% | Reportes corporativos USA |
| 4 (AF=3) | Pesos Rev. | $11,500 (COSTO_CALCULO4) | 01/01/2024 | 25% | Análisis inflacionario |

En la tabla `calculo` existirán **4 registros por mes** para este activo, uno por cada tipo de depreciación.

---

## Relaciones entre Tablas

### Diagrama de Relaciones Principales

```
compania (1) -----> (*) activo
                    |
tipo_activo (1) --> (*) activo
subtipo_activo (1) -> (*) activo
centro_costo (1) -> (*) activo
edificio (1) -----> (*) activo
area (1) ---------> (*) activo
pais (1) ---------> (*) activo
moneda (1) -------> (*) activo

tipo_depreciacion (1) -> (*) porcentaje_depreciacion
tipo_activo (1) -------> (*) porcentaje_depreciacion
subtipo_activo (1) ----> (*) porcentaje_depreciacion

activo (1) --------> (*) calculo
tipo_depreciacion (1) -> (*) calculo
```

### Flujo de Información

1. **Catálogos Base** (compania, tipo_activo, subtipo_activo, etc.)
   ↓
2. **Configuración de Porcentajes** (porcentaje_depreciacion)
   ↓
3. **Registro de Activos** (activo)
   ↓
4. **Cálculo de Depreciación** (stored procedure usp_calculoenrique)
   ↓
5. **Almacenamiento de Resultados** (calculo)

---

## Consideraciones Técnicas

### Control de Concurrencia

Todas las tablas incluyen el campo `rv` (timestamp) para control de concurrencia optimista en SQL Server.

### Valores NULL vs 0

- **NULL**: Indica que no se ha establecido un valor (usa valores por defecto)
- **0**: Indica explícitamente un valor de cero (no deprecia, no aplica, etc.)

Esta distinción es **crítica** en los campos de porcentaje de depreciación.

### Desnormalización

La tabla `calculo` incluye campos desnormalizados (ID_CENTRO_COSTO, ID_EDIFICIO, etc.) para:
- Mejorar performance en consultas
- Mantener histórico aunque el activo cambie de ubicación
- Facilitar reportes

---

## Índices Recomendados

### Tabla activo
- PK: ID_NUM_ACTIVO
- IX: ID_COMPANIA, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO
- IX: ID_CENTRO_COSTO
- IX: ID_EDIFICIO

### Tabla calculo
- PK: ID_COMPANIA, ID_ANO, ID_MES, ID_TIPO_DEP, ID_NUM_ACTIVO
- IX: ID_NUM_ACTIVO, ID_TIPO_DEP, ID_ANO, ID_MES (para consultas por activo)
- IX: ID_TIPO_DEP, ID_ANO, ID_MES (para reportes por tipo)

### Tabla porcentaje_depreciacion
- PK: ID_PORCEN
- IX: ID_TIPO_DEP, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO, FECHA_INICIO, FECHA_FIN

---

**Versión**: 1.0
**Fecha**: 2025-10-18
**Base de Datos**: actif_web_cima_dev
**Servidor**: dbdev.powerera.com
