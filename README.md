# ActifRMF - Sistema de Reportes de Impuesto al Activo Extranjero

## Descripción General

Sistema Data Warehouse para importar datos del sistema Actif y generar reportes para el impuesto al activo extranjero (RMF - Resolución Miscelánea Fiscal).

El sistema permite identificar activos de ownership extranjero o ajeno que requieren declaración de impuestos, diferenciándolos de los activos nacionales.

## Arquitectura del Sistema

### Componentes Principales

1. **Extracción de Datos (ETL)**
   - Conexión a múltiples bases de datos Actif (configurables por compañía)
   - Importación selectiva por año
   - Normalización de datos

2. **Motor de Cálculo**
   - Implementación de reglas de negocio para cálculo de impuestos
   - Manejo de casos especiales según ownership
   - Cálculo basado en depreciaciones y valores

3. **Generación de Reportes**
   - Resumen para activos nacionales
   - Resumen para activos extranjeros
   - Detalle para activos extranjeros
   - Detalle para activos nacionales
   - Reportes agrupados por compañía

### Stack Tecnológico

- **.NET 9** - Framework principal (Minimal API)
- **SQL Server** - Base de datos
- **EPPlus / ClosedXML** - Procesamiento de archivos Excel
- **Bootstrap 5.3** - Framework CSS para UI
- **Font Awesome 6.4** - Iconos
- **Servidor**: dbdev.powerera.com
- **Puerto**: 5071 (http://localhost:5071)

## Estructura de Bases de Datos

### Base de Datos Fuente: Actif (Múltiples instancias)

Ejemplo: `actif_web_CIMA_Dev` en dbdev.powerera.com

#### Tablas Principales

##### 1. activo
Tabla principal de activos fijos

**Campos clave:**
- `ID_NUM_ACTIVO` (PK, Identity) - ID único numérico del activo
- `ID_COMPANIA` - Relación con compañía
- `ID_ACTIVO` - Código alfanumérico del activo
- `ID_TIPO_ACTIVO` - Tipo de activo
- `ID_SUBTIPO_ACTIVO` - Subtipo de activo
- `ID_CENTRO_COSTO` - Centro de costo asignado
- `ID_RESPONSABLE` - Responsable del activo
- `ID_MONEDA` - Moneda del activo
- `ID_PAIS` - País del activo
- `ID_EDIFICIO` - Edificio donde se encuentra
- `ID_SERIE` - Número de serie
- `DESCRIPCION` - Descripción corta
- `DESCR_LARGA` - Descripción larga
- `FECHA_COMPRA` - Fecha de adquisición
- `FECHA_INIC_DEPREC` - Fecha inicio depreciación tipo 1
- `FECHA_INIC_DEPREC2` - Fecha inicio depreciación tipo 2
- `FECHA_INIC_DEPREC3` - Fecha inicio depreciación tipo 3
- `COSTO_ADQUISICION` - Costo original
- `COSTO_REVALUADO` - Costo revaluado
- `COSTO_REEXPRESADO` - Costo reexpresado
- `VIDA_UTIL` - Vida útil en meses
- `VIDA_REMANENTE` - Vida remanente en meses
- **`ID_PAIS`** - **CRÍTICO**: Indicador de nacionalidad del activo (1=Nacional/México, >1=Extranjero)
- **`FLG_PROPIO`** - Indicador de ownership (propio vs. arrendado/terceros)
- `STATUS` - Estado del activo (A=Activo, B=Baja, etc.)

##### 2. compania
Catálogo de compañías

**Campos clave:**
- `ID_COMPANIA` (PK, Identity)
- `NOMBRE` - Nombre de la compañía
- `RFC` - Registro Federal de Contribuyentes
- `FECHA_INICIO_EJERC` - Fecha inicio de ejercicio fiscal
- `Default_Id_Moneda` - Moneda por defecto
- `Default_Id_Pais` - País por defecto
- `Default_TipoCambio` - Tipo de cambio por defecto
- `ID_TIPO_DEP_PRINCIPAL` - Tipo de depreciación principal

**Configuración en ActifRMF:**
Cada compañía tendrá un connection string configurado para extraer datos de su base de datos Actif correspondiente.

##### 3. calculo
Tabla de cálculos de depreciación por mes/año

**Campos clave (PK compuesta):**
- `ID_COMPANIA` - Compañía
- `ID_ANO` - Año del cálculo
- `ID_MES` - Mes del cálculo (1-12)
- `ID_TIPO_DEP` - Tipo de depreciación (1=Contable, 2=Fiscal, 3=IFRS, etc.)
- `ID_NUM_ACTIVO` - Activo relacionado

**Campos de cálculo:**
- `VALOR_ADQUISICION` - Valor de adquisición
- `MENSUAL_HISTORICA` - Depreciación mensual histórica
- `ACUMULADO_HISTORICA` - Depreciación acumulada histórica
- `EJERCICIO_HISTORICA` - Depreciación del ejercicio
- `MENSUAL_CALCU` - Depreciación mensual calculada
- `ACUMULADO_CALCU` - Depreciación acumulada calculada
- `EJERCICIO_CALCU` - Depreciación del ejercicio calculada
- `ID_CENTRO_COSTO` - Centro de costo (snapshot)
- `ID_EDIFICIO` - Edificio (snapshot)
- `ID_TIPO_ACTIVO` - Tipo activo (snapshot)
- `STATUS` - Estado

**Importante:** Esta tabla guarda el cálculo histórico por tipo de depreciación, activo, mes y año.

##### 4. centro_costo
Catálogo de centros de costo

**Campos clave:**
- `ID_CENTRO_COSTO` (PK, Identity)
- `ID_COMPANIA` - Compañía
- `CODIGO` - Código del centro de costo
- `DESCRIPCION` - Descripción
- `RESPONSABLE` - Responsable
- `STATUS` - Estado
- `CTA1` - `CTA16` - Cuentas contables asociadas

##### 5. edificio
Catálogo de edificios/ubicaciones

**Campos clave:**
- `ID_COMPANIA` - Compañía
- `ID_EDIFICIO` (PK, Identity)
- (Más campos según estructura completa)

##### 6. porcentaje_depreciacion
Porcentajes de depreciación por tipo de activo

**Nota:** Esta tabla aún no ha sido consultada en detalle.

##### 7. moneda
Catálogo de monedas

**Campos clave:**
- `ID_MONEDA` (PK, Identity)
- `ID_PAIS` - País asociado
- `NOMBRE` - Nombre de la moneda
- `SIMBOLO` - Símbolo ($, €, etc.)

##### 8. pais
Catálogo de países

**Campos clave:**
- `ID_PAIS` (PK, Identity)
- `NOMBRE` - Nombre del país

### Base de Datos Destino: Actif_RMF

Nueva base de datos en dbdev.powerera.com para almacenar:
- Configuración de conexiones por compañía
- Datos importados (data warehouse)
- Cálculos de impuestos
- Historial de procesos

**Esquema por diseñar** (ver sección siguiente)

## Modelo de Datos ActifRMF (Por diseñar)

### Tablas Propuestas

1. **ConfiguracionCompania**
   - ID_Configuracion (PK)
   - Nombre_Compania
   - ConnectionString (encriptado)
   - Activo (bit)
   - FechaCreacion
   - FechaModificacion

2. **ActivoImportado**
   - Copia desnormalizada de activos importados
   - Campos adicionales de control (fecha importación, compañía origen, etc.)

3. **CalculoImpuesto**
   - Cálculos específicos para impuesto RMF
   - Año fiscal
   - Tipo de activo (nacional/extranjero)
   - Montos calculados

4. **ProcesoEjecucion**
   - Log de ejecuciones de importación/cálculo
   - Fecha, usuario, resultado, errores

## Casos de Uso - Cálculo de Impuesto

### Referencia: Propuesta reporte Calculo AF.xlsx

El archivo Excel en `/Users/enrique/ActifRMF/Propuesta reporte Calculo AF.xlsx` contiene:
- Ejemplos de cálculos
- Casos especiales (ownership extranjero vs nacional)
- Formato de reportes esperados
- Reglas de negocio

**Por analizar en detalle mediante el proyecto .NET**

## Interfaz Web

El sistema cuenta con una interfaz web completa para administración y operación:

### Páginas Disponibles

1. **Inicio (index.html)**
   - Panel principal con accesos rápidos
   - Descripción del flujo del sistema
   - Navegación a todas las funcionalidades

2. **Compañías (companias.html)**
   - CRUD completo de compañías
   - Configuración de connection strings por compañía
   - Gestión de queries ETL personalizados
   - URL: http://localhost:5071/companias.html

3. **Extracción ETL (extraccion.html)**
   - Selección de compañía y año
   - Ejecución de ETL bajo demanda
   - Visualización de resultados en tiempo real
   - Historial de extracciones
   - URL: http://localhost:5071/extraccion.html

4. **Cálculo RMF (calculo.html)**
   - Ejecución de cálculos fiscales
   - Visualización de resultados
   - URL: http://localhost:5071/calculo.html

### API Endpoints

- `GET /health` - Health check
- `GET /api/companias` - Listar compañías
- `GET /api/companias/{id}` - Obtener compañía por ID
- `POST /api/companias` - Crear compañía
- `PUT /api/companias/{id}` - Actualizar compañía
- `DELETE /api/companias/{id}` - Eliminar compañía
- `POST /api/etl/ejecutar` - Ejecutar ETL
- `POST /api/calculo/ejecutar` - Ejecutar cálculo
- `GET /api/calculo/resultado/{idCompania}/{añoCalculo}` - Obtener resultados

## Flujo del Sistema

### 1. Configuración Inicial
- Registrar compañías en ActifRMF
- Configurar connection string para cada compañía
- Definir año(s) a procesar

### 2. Extracción de Datos
```
Por cada compañía:
  - Conectar a su base de datos Actif
  - Extraer activos del año seleccionado
  - Extraer cálculos de depreciación
  - Extraer catálogos relacionados (compañía, centro costo, edificio, etc.)
  - Guardar en Actif_RMF (staging/data warehouse)
```

### 3. Procesamiento
```
- Aplicar reglas de negocio
- Clasificar activos (nacional/extranjero) según ID_PAIS
- Clasificar ownership (propio/terceros) según FLG_PROPIO
- Calcular impuestos según casos de uso (ver RMF.md)
- Aplicar actualización con INPC
- Generar registros de cálculo
```

### 4. Generación de Reportes
```
Por cada compañía:
  1. Resumen activos nacionales
  2. Resumen activos extranjeros
  3. Detalle activos extranjeros
  4. Detalle activos nacionales
```

## Reglas de Negocio (Preliminares)

### Clasificación de Activos

**Por Nacionalidad (Campo: ID_PAIS):**
- **Nacional**: `ID_PAIS = 1` (México)
- **Extranjero**: `ID_PAIS > 1` (Ejemplo: 2=Estados Unidos)

**Por Ownership (Campo: FLG_PROPIO):**
- **Propio**: `FLG_PROPIO = 1` (Propiedad de la empresa)
- **Terceros/Arrendado**: `FLG_PROPIO = 0` (No es propiedad, mejoras en arrendamiento)

**IMPORTANTE**: Los activos extranjeros (ID_PAIS > 1) utilizados en México también requieren declaración de impuestos, sin importar si son propios o de terceros. Ver RMF.md para detalles sobre tratamiento fiscal según LISR Artículo 31.

### Cálculos

(Por documentar basado en análisis del Excel)

## Conexiones a Base de Datos

### Actif (Fuente)

**Servidor:** dbdev.powerera.com
**Ejemplo BD:** actif_web_CIMA_Dev
**Usuario:** earaiza
**Password:** VgfN-n4ju?H1Z4#JFRE

**Connection String:**
```
Server=dbdev.powerera.com;Database=actif_web_CIMA_Dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;
```

### Actif_RMF (Destino)

**Servidor:** dbdev.powerera.com
**Base de Datos:** Actif_RMF
**Usuario:** usuarioPrueba
**Password:** Password123!

**Connection String:**
```
Server=dbdev.powerera.com;Database=Actif_RMF;User Id=usuarioPrueba;Password=Password123!;TrustServerCertificate=True;
```

**Nota:** La base de datos Actif_RMF ya está creada en el servidor con las tablas necesarias para el sistema.

## Próximos Pasos

- [x] Analizar estructura de base de datos Actif
- [x] Documentar tablas principales (ver DICCIONARIO_DATOS.md)
- [x] Investigar marco legal RMF/LISR (ver RMF.md)
- [x] Crear proyecto .NET 9 con Web API
- [ ] Analizar archivo Excel de referencia con .NET
- [ ] Definir casos de uso detallados de cálculo
- [ ] Diseñar esquema completo de Actif_RMF
- [ ] Crear base de datos Actif_RMF
- [ ] Desarrollar ETL de extracción
- [ ] Implementar motor de cálculo (basado en RMF.md)
- [ ] Implementar actualización con INPC
- [ ] Desarrollar generador de reportes
- [ ] Pruebas con datos reales

## Documentación Adicional

- **DICCIONARIO_DATOS.md** - Diccionario completo de datos de tablas Actif
- **RMF.md** - Marco legal y reglas de cálculo de impuestos (LISR Art. 31-35, RMF 2024/2025)

## Documentación Técnica

### Vista vMetaData

Actif incluye una vista útil `vMetaData` que proporciona metadatos de todas las tablas:
- Nombres de columnas
- Tipos de datos
- Relaciones (foreign keys)
- Campos de búsqueda
- Primary keys
- Descripciones (extended properties)

**Query ejemplo:**
```sql
SELECT * FROM vMetaData
WHERE TableName IN ('activo', 'compania', 'centro_costo')
ORDER BY TableName, Columna
```

---

**Fecha de creación:** 2025-10-12
**Última actualización:** 2025-10-12
**Versión:** 0.1.0 - Documentación inicial
