# ActifRMF - Sistema de Cálculo Safe Harbor

Sistema web para calcular el valor reportable de activos extranjeros bajo la regla Safe Harbor (Art. 182 LISR).

## Tecnologías

- **Backend**: .NET 9 Minimal API
- **Frontend**: HTML, JavaScript, Bootstrap 5, ag-Grid
- **Base de Datos**: SQL Server (Azure)
- **Pruebas**: Selenium WebDriver (Python)

## Estructura del Proyecto

```
ActifRMF/
├── SQL/                          # Scripts de base de datos
│   ├── 02_CREATE_TABLES.sql
│   ├── 03_INSERT_CATALOGOS.sql
│   ├── 04_SP_ETL_Importar_Activos.sql
│   ├── 05_SP_Calcular_RMF_Activos_Extranjeros.sql
│   ├── 06_AJUSTES_TABLAS.sql
│   ├── 07_FIX_LOG_DUPLICADOS.sql
│   └── 08_FIX_Calculo_RMF_Table.sql
├── Services/                     # Servicios backend
│   ├── ETLService.cs
│   └── DatabaseSetupService.cs
├── wwwroot/                      # Frontend
│   ├── index.html               # Dashboard
│   ├── companias.html           # Gestión de compañías
│   ├── extraccion.html          # ETL de activos
│   ├── calculo.html             # Cálculo Safe Harbor
│   ├── reporte.html             # Reporte con ag-Grid
│   ├── js/                      # JavaScript
│   └── css/                     # Estilos
└── Tests/                        # Pruebas Selenium
    ├── test_companias.py
    ├── test_extraccion.py
    ├── test_calculo.py
    └── test_reporte.py
```

## Configuración

### 1. Base de Datos

Configurar connection string en `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "ActifRMF": "Server=...;Database=Actif_RMF;User Id=...;Password=...;"
  }
}
```

### 2. Ejecutar Setup Inicial

```bash
# Opción 1: Mediante API
curl -X POST http://localhost:5071/api/setup/database

# Opción 2: Ejecutar scripts SQL manualmente
# Usar SQL Server Management Studio o Azure Data Studio
# Ejecutar scripts en orden numérico (02, 03, 04, 05, 06, 07, 08)
```

### 3. Ejecutar la Aplicación

```bash
cd ActifRMF
dotnet run --urls="http://localhost:5071"
```

Acceder a: http://localhost:5071

## Flujo de Trabajo

1. **Gestión de Compañías** (`/companias.html`)
   - Crear/editar compañías
   - Configurar query ETL personalizado por compañía

2. **Extracción ETL** (`/extraccion.html`)
   - Seleccionar compañía y año
   - Extraer activos de base de datos origen
   - Ver progreso en tiempo real

3. **Cálculo Safe Harbor** (`/calculo.html`)
   - Seleccionar lote ETL
   - Ejecutar cálculo RMF
   - Ver progreso del cálculo

4. **Reporte** (`/reporte.html`)
   - Ver resultados en grid con filtros
   - Exportar a Excel
   - Análisis de activos calculados

## PROTOCOLO DE PRUEBAS (OBLIGATORIO)

### ⚠️ REGLA CRÍTICA

**ANTES DE ENTREGAR CUALQUIER PANTALLA O FUNCIONALIDAD:**

1. ✅ **Debe existir un archivo de prueba Selenium** en `/Tests/test_{pantalla}.py`
2. ✅ **La prueba debe ejecutarse y pasar completamente**
3. ✅ **Debe tener criterios de éxito claros y verificables**
4. ✅ **CRITERIO MÍNIMO: NO deben aparecer errores en la UI**

### Criterios de Éxito por Pantalla

#### Compañías (`test_companias.py`)
- ✅ Página carga sin errores
- ✅ Grid muestra compañías
- ✅ Modal de edición abre correctamente
- ✅ Se puede guardar cambios sin errores

#### Extracción ETL (`test_extraccion.py`)
- ✅ Página carga sin errores
- ✅ Dropdown de compañías se llena
- ✅ ETL se ejecuta sin errores
- ✅ Barra de progreso muestra porcentaje real
- ✅ Historial se actualiza correctamente
- ✅ NO hay registros huérfanos "En Proceso"

#### Cálculo Safe Harbor (`test_calculo.py`)
- ✅ Página carga sin errores
- ✅ Setup de BD ejecuta correctamente
- ✅ Stored procedure existe y funciona
- ✅ Dropdown de lotes muestra lotes únicos (sin duplicados)
- ✅ Cálculo se ejecuta sin errores
- ✅ **NO aparece error "Invalid object name 'dbo.Calculo_RMF'"**
- ✅ **NO aparece error "Could not find stored procedure"**
- ✅ Historial muestra cálculos completados

#### Reporte (`test_reporte.py`)
- ✅ Página carga sin errores
- ✅ Grid ag-Grid se inicializa
- ✅ Datos se cargan correctamente
- ✅ Si no hay datos, muestra "No hay registros para mostrar" (NO loading infinito)
- ✅ Filtros funcionan
- ✅ Exportación a Excel funciona
- ✅ Todos los textos dicen "Safe Harbor" (no "RMF")

### Ejecutar Pruebas

```bash
# Instalar dependencias
pip3 install selenium requests

# Asegurar que el servidor esté corriendo
dotnet run --urls="http://localhost:5071"

# Ejecutar prueba específica
python3 Tests/test_companias.py
python3 Tests/test_extraccion.py
python3 Tests/test_calculo.py
python3 Tests/test_reporte.py

# Todas las pruebas deben retornar exit code 0 (sin errores)
```

### Estructura de una Prueba

```python
def test_pantalla_function(driver):
    """Descripción de lo que prueba"""
    log("\n=== TEST: Nombre del Test ===")

    # Realizar acciones
    driver.get(f"{BASE_URL}/pantalla.html")

    # Verificar que NO haya errores
    errors = driver.find_elements(By.CLASS_NAME, "alert-danger")
    if len(errors) > 0:
        log(f"❌ Se encontraron {len(errors)} errores en la página")
        return False

    # Verificaciones adicionales
    # ...

    log("✅ Test pasó correctamente")
    return True
```

### Qué Hacer Si Una Prueba Falla

1. **NO entregar** la funcionalidad
2. **Investigar** el error en detalle
3. **Corregir** el problema en el código
4. **Volver a ejecutar** la prueba
5. **Iterar** hasta que la prueba pase
6. **Solo entonces** entregar al usuario

## Arquitectura de Base de Datos

### Tablas Principales

- `Compania` - Catálogo de compañías
- `Staging_Activo` - Datos extraídos por ETL
- `Calculo_RMF` - Resultados de cálculos Safe Harbor
- `Log_Ejecucion_ETL` - Historial de procesos (ETL y Cálculo)
- `INPC_Importado` - Índices INPC para actualización
- `Tipo_Cambio` - Tipos de cambio USD-MXN

### Stored Procedures

- `sp_Calcular_RMF_Activos_Extranjeros` - Cálculo principal Safe Harbor

## Troubleshooting

### Error: "Invalid object name 'dbo.Calculo_RMF'"

**Causa**: La tabla no existe en la base de datos.

**Solución**:
```bash
# Ejecutar setup completo
curl -X POST http://localhost:5071/api/setup/database

# O ejecutar manualmente el script
# SQL/08_FIX_Calculo_RMF_Table.sql
```

### Error: "Could not find stored procedure"

**Causa**: El stored procedure no se creó.

**Solución**:
```sql
-- Ejecutar SQL/05_SP_Calcular_RMF_Activos_Extranjeros.sql
-- Verificar con:
SELECT * FROM sys.procedures WHERE name = 'sp_Calcular_RMF_Activos_Extranjeros'
```

### Dropdown de Lotes Muestra Duplicados

**Causa**: Duplicados en tabla `Log_Ejecucion_ETL`.

**Solución**:
```bash
# Ejecutar script de fix
# SQL/07_FIX_LOG_DUPLICADOS.sql
# Esto crea constraint UNIQUE y limpia duplicados
```

### Loading Infinito en Reporte

**Causa**: No hay datos pero el grid no muestra mensaje.

**Solución**: Ya corregido en `reporte.js` - muestra "No hay registros para mostrar".

## Contribuir

1. Crear feature branch
2. Hacer cambios
3. **Crear o actualizar prueba Selenium**
4. **Ejecutar prueba y asegurar que pasa**
5. Hacer commit con prueba incluida
6. Crear pull request

## Soporte

Para reportar issues o solicitar features, contactar al equipo de desarrollo.

---

**Última actualización**: 2025-01-13
**Versión**: 1.0.0
