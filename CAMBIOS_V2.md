# ActifRMF v2.0 - ETL Integrado

## 🎉 Cambios Principales

### Arquitectura Simplificada
- **ANTES (v1.0):** Dos ejecutables separados (Web + ETL)
- **AHORA (v2.0):** Una sola aplicación web con ETL integrado

### Ventajas
✅ **Más fácil de desplegar** - Solo un ejecutable
✅ **Menor tamaño** - 10 MB vs 25 MB
✅ **Instalación simplificada** - No requiere configurar procesos separados
✅ **Windows-friendly** - Instrucciones completas para Windows
✅ **Mismo rendimiento** - ETL ejecuta en `Task.Run` asíncrono

## 📁 Archivos Modificados

### Nuevos Archivos
- `Services/ETLProcessor.cs` - Clase `ETLActivos` integrada
- `INSTALACION_WINDOWS.md` - Guía completa de instalación Windows

### Archivos Modificados
- `Services/ETLService.cs` - Llama a ETL directamente (no Process.Start)
- `ENTREGABLES.md` - Actualizado con arquitectura v2.0

### Archivos Eliminados (Ya No Necesarios)
- ❌ `/ETL_NET/` - Proyecto ETL separado ya no requerido

## 🚀 Cómo Usar

### Windows
```cmd
cd ActifRMF_Release_Integrated
ActifRMF.exe --urls "http://localhost:5071"
```

### Linux/Mac
```bash
cd ActifRMF_Release_Integrated
./ActifRMF --urls "http://localhost:5071"
```

## 🔬 Pruebas Realizadas

✅ **ETL integrado funciona correctamente:**
- Compañía 12, Año 2025
- 5 registros extraídos
- 5 registros cargados en Staging_Activo
- Duración: 2 segundos
- Sin bloqueos en servidor web

✅ **Compilación limpia:**
- Sin errores
- Solo warnings menores de nullable types (normales)

## 📦 Entregables

### Paquete de Instalación
- **Archivo:** `ActifRMF_Integrated_v2.zip` (10 MB)
- **Ubicación:** `/Users/enrique/ActifRMF/`
- **Contenido:** Aplicación web completa con ETL integrado

### Base de Datos
- **Archivo:** `Actif_RMF_20251121_120617.bak` (3 MB comprimido)
- **Ubicación:** `dbdev.powerera.com:/tmp/`

## 🔄 Migración desde v1.0

Si tienes instalada la versión anterior:

1. **Detener ambos servicios:**
   ```bash
   sudo systemctl stop actifrmf
   sudo systemctl stop actifrmf-etl
   ```

2. **Instalar v2.0:**
   ```bash
   sudo rm -rf /opt/actifrmf/etl  # Ya no necesario
   sudo cp -r ActifRMF_Release_Integrated /opt/actifrmf/web
   ```

3. **Iniciar solo web (con ETL integrado):**
   ```bash
   sudo systemctl start actifrmf
   ```

## 💡 Notas Técnicas

### Implementación
- `ETLService.EjecutarETLAsync()` ahora usa `Task.Run()` para llamar a `ETLActivos.EjecutarETL()`
- No se bloquea el thread del servidor web
- Los resultados se consultan desde la base de datos después de completar
- El progreso se rastrea en `ConcurrentDictionary` estático

### Compatibilidad
- ✅ .NET 9.0 (Runtime único)
- ✅ SQL Server 2019+
- ✅ Windows 10/11, Windows Server 2016+
- ✅ Linux (Ubuntu 20.04+, CentOS 7+)
- ✅ macOS 11+

## 📝 Próximos Pasos

1. Agregar más casos de prueba (ciclo de vida de activos)
2. Documentar validaciones contra ejemplos del cliente
3. Optimizar performance para miles de activos

---

**Versión:** 2.0.0
**Fecha:** 21 de Noviembre de 2025
**Autor:** Enrique Araiza (earaiza@powerera.com)
