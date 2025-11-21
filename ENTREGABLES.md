# ActifRMF - Entregables Listos (v2.0 - ETL Integrado)

## 📦 Archivos Generados

### 1. Paquete de Instalación Web (SIMPLIFICADO)
**Archivo:** `ActifRMF_Integrated_v2.zip` (10 MB)
**Ubicación:** `/Users/enrique/ActifRMF/ActifRMF_Integrated_v2.zip`

**🎉 ARQUITECTURA SIMPLIFICADA:**
- ✅ **Una sola aplicación web** (sin ejecutables separados)
- ✅ **ETL integrado** directamente en el servidor web
- ✅ **Fácil de desplegar** en Windows/Linux/Mac
- ✅ **Menor tamaño** (10 MB vs 25 MB)

**Contenido:**
```
ActifRMF_Release_Integrated/
├── ActifRMF.exe            # Ejecutable web (Windows)
├── ActifRMF                # Ejecutable web (Linux/Mac)
├── wwwroot/                # HTML, CSS, JS
├── appsettings.json        # Configuración
├── *.dll                   # Librerías .NET
└── INSTALACION_WINDOWS.md  # Guía instalación Windows
```

### 2. Backup de Base de Datos
**Archivo:** `Actif_RMF_20251121_120617.bak` (comprimido)
**Ubicación:** En servidor `dbdev.powerera.com:/tmp/`
**Tamaño:** ~3 MB comprimido (656 MB descomprimido)

**Contenido:**
- Base de datos completa Actif_RMF
- 7 compañías configuradas
- Tablas: ConfiguracionCompania, Staging_Activo, Calculo_RMF, etc.
- Stored Procedures y Functions
- Tipos de Cambio hasta 2025

**Para descargar:**
```bash
scp earaiza@dbdev.powerera.com:/tmp/Actif_RMF_20251121_120617.bak .
```

## 🚀 Instalación Rápida

### Opción 1: Windows (Más Fácil)

```cmd
:: 1. Descomprimir
unzip ActifRMF_Integrated_v2.zip

:: 2. Editar connection string en appsettings.json

:: 3. Ejecutar
cd ActifRMF_Release_Integrated
ActifRMF.exe --urls "http://localhost:5071"

:: 4. Abrir navegador
start http://localhost:5071/extraccion.html
```

**Ver instrucciones completas:** `INSTALACION_WINDOWS.md` incluido en el ZIP

### Opción 2: Linux Server (Producción)

```bash
# 1. Descomprimir
unzip ActifRMF_Integrated_v2.zip

# 2. Copiar a /opt
sudo cp -r ActifRMF_Release_Integrated /opt/actifrmf

# 3. Editar connection string
sudo nano /opt/actifrmf/appsettings.json

# 4. Ejecutar directamente o como servicio
cd /opt/actifrmf
./ActifRMF --urls "http://localhost:5071"

# 5. Verificar
curl http://localhost:5071/health
```

### Opción 3: Desarrollo Local (Mac/Linux)

```bash
# 1. Extraer
unzip ActifRMF_Integrated_v2.zip

# 2. Editar appsettings.json con connection string

# 3. Ejecutar
cd ActifRMF_Release_Integrated
./ActifRMF --urls "http://localhost:5071"

# 4. Abrir navegador
open http://localhost:5071/extraccion.html
```

## 📋 Funcionalidades Implementadas

### ✅ ETL (Extracción) - INTEGRADO EN WEB
- **ETL integrado** en aplicación web (sin ejecutables separados)
- Ejecución asíncrona con `Task.Run` (no bloquea servidor)
- Extracción de activos NO propios desde bases de origen
- Soporte para 7 compañías configuradas
- Query configurable por compañía en tabla ConfiguracionCompania
- Auto-limpieza de procesos colgados (>3 minutos)
- Timeout frontend: 10 minutos
- Connection timeout: 30 segundos
- Versionado de cache JS/CSS

### ✅ Cálculo Safe Harbor
- Activos mexicanos (Art. 182 LISR)
- Activos extranjeros (USGAAP)
- Regla del 10% de depreciación pendiente
- Cálculo de proporción para bajas parciales
- Función fn_CalcularDepFiscal_Tipo2 para cálculo retroactivo
- Tipos de cambio 30-Jun y 31-Dic

### ✅ Reporte
- Generación de reporte Safe Harbor por año/compañía
- Export a Excel con formato
- Visualización en HTML responsive
- Observaciones automáticas por ruta de cálculo

## 🔧 Cambios y Correcciones (21-Nov-2025)

### 🎉 NUEVA ARQUITECTURA v2.0 - ETL INTEGRADO
- ✅ **ETL integrado** directamente en aplicación web
- ✅ **Eliminado ejecutable separado** (ActifRMF.ETL.exe)
- ✅ **Una sola aplicación** más fácil de desplegar
- ✅ **ETLProcessor.cs** con clase `ETLActivos` integrada
- ✅ **ETLService.cs** llama a ETL directamente (no Process.Start)
- ✅ **Task.Run** para ejecución asíncrona sin bloquear servidor
- ✅ **Menor tamaño** de paquete (10 MB vs 25 MB)
- ✅ **Instrucciones para Windows** (INSTALACION_WINDOWS.md)

### Correcciones Previas (21-Nov-2025)

### 1. Fix ETL Timeout
- ❌ **Problema:** ETL se colgaba mostrando "En Proceso"
- ✅ **Causa:** Alias faltante `FECHA_INIC_DEPREC2 AS FECHA_INIC_DEPREC`
- ✅ **Fix:** Actualizado Query_ETL en 6 compañías (12, 122, 123, 1000, 1001, 1500)

### 2. Fix Process Deadlock
- ❌ **Problema:** Procesos ETL bloqueados en StandardOutput buffer
- ✅ **Fix:** Reemplazado BeginOutputReadLine con async Task.Run pattern

### 3. Connection Timeout
- ❌ **Problema:** Connection timeout default (15 seg) muy corto
- ✅ **Fix:** Agregado `Connection Timeout=30` en todas las compañías

### 4. Frontend Timeout
- ❌ **Problema:** Timeout de 3 minutos muy corto
- ✅ **Fix:** Aumentado a 10 minutos en extraccion.js

### 5. Cache Navegador
- ❌ **Problema:** Navegador cachea JS/CSS viejos
- ✅ **Fix:** Versionado dinámico `?v=timestamp` en extraccion.html

## 📊 Estado Actual del Sistema

### Compañías Activas
| ID  | Nombre                 | Registros | Estado ETL |
|-----|------------------------|-----------|------------|
| 12  | PIEDRAS NEGRAS        | 18        | ✅ OK      |
| 122 | Lear Mexican Trim     | —         | ✅ OK      |
| 123 | CIMA                  | —         | ✅ OK      |
| 188 | Compañia Prueba 188   | 37        | ✅ OK      |
| 1000| Compañia 1000 LC      | —         | ✅ OK      |
| 1001| Lear Corp USD         | —         | ✅ OK      |
| 1500| CIMA                  | —         | ✅ OK      |

### Casos de Prueba Disponibles

Actualmente hay ejemplos de:
- ✅ Activo adquirido antes de 2025 (uso todo el año)
- ✅ Activo adquirido en 2025 (alta parcial)
- ✅ Activo dado de baja en 2025 (baja parcial)
- ⚠️ **Faltantes:** Más casos de ciclo de vida (según imágenes del usuario)

## 🔜 Próximos Pasos

1. **Agregar más activos de ejemplo** con escenarios completos
2. **Documentar casos de prueba** en tabla AutoTest
3. **Validar cálculos** contra ejemplos del cliente
4. **Optimizar performance** para compañías con miles de activos

## 📞 Soporte

- **GitHub:** https://github.com/earaizapowerera/ActifSafeHarbor
- **Commit actual:** `618d32e` (21-Nov-2025)
- **Build:** Release .NET 9.0 / .NET 8.0

## 📝 Notas de Instalación

### Base de Datos
El backup incluye:
- ✅ ConfiguracionCompania con Query_ETL corregido
- ✅ Tipos de Cambio hasta 2025
- ✅ 37 activos de ejemplo (compañía 188)
- ✅ Stored Procedures actualizados (v5.1)
- ✅ Functions: fn_CalcularDepFiscal_Tipo2

### Aplicación Web (Todo Integrado)
- Puerto por defecto: 5071
- Runtime: .NET 9.0
- Compatible: Linux, macOS, Windows
- Base de datos: SQL Server 2019+
- **ETL integrado**: No requiere ejecutables separados
- **Ejecución**: `./ActifRMF --urls "http://localhost:5071"`

---

**Fecha de generación:** 21 de Noviembre de 2025
**Versión:** 2.0.0 (ETL Integrado)
**Mejoras v2.0:**
- ✅ Arquitectura simplificada (una sola app)
- ✅ Más fácil de desplegar en clientes
- ✅ Menor tamaño de paquete (10 MB)
- ✅ Instrucciones completas para Windows
