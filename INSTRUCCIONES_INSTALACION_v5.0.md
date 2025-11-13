# Instrucciones de Instalación - ActifRMF v5.0 Safe Harbor

**Versión:** v5.0-SafeHarbor
**Fecha:** 2025-11-13
**Tipo:** Actualización Mayor

---

## ⚠️ IMPORTANTE - Leer Antes de Instalar

Esta actualización incluye:
- ✅ **9 columnas nuevas** en tabla `Calculo_RMF`
- ✅ **Stored Procedure actualizado** a v5.0
- ✅ **Aplicación web actualizada** para mostrar Safe Harbor
- ⚠️ **NO es compatible** con versiones anteriores sin actualizar BD

---

## 📦 Contenido del Paquete

```
ActifRMF_v5.0_SafeHarbor.zip
├── ActifRMF/                              # Aplicación web compilada
│   ├── wwwroot/
│   ├── appsettings.json
│   └── ActifRMF.dll
├── Database/
│   ├── DEPLOY_v5.0_ACTUALIZACION_BD.sql   # Script de actualización BD
│   └── sp_Calcular_RMF_Activos_Nacionales.sql  # SP v5.0
├── INSTRUCCIONES_INSTALACION_v5.0.md      # Este archivo
└── CAMBIOS_SAFE_HARBOR.md                 # Documentación de cambios
```

---

## 🗄️ PASO 1: Actualizar Base de Datos

### 1.1 Backup de Seguridad

**CRÍTICO:** Hacer backup antes de continuar

```sql
-- Backup de tabla Calculo_RMF
SELECT * INTO Calculo_RMF_BACKUP_20251113
FROM Calculo_RMF;

-- Backup de SP anterior
EXEC sp_helptext 'sp_Calcular_RMF_Activos_Nacionales';
-- Copiar el resultado a un archivo .sql de respaldo
```

### 1.2 Ejecutar Script de Actualización

```bash
sqlcmd -S <servidor> -d Actif_RMF -U <usuario> -P <password> -C \
  -i DEPLOY_v5.0_ACTUALIZACION_BD.sql
```

**Resultado esperado:**
```
✓ Columna INPC_SH_Junio agregada
✓ Columna Factor_SH agregada
✓ Columna Saldo_SH_Actualizado agregada
✓ Columna Dep_SH_Actualizada agregada
✓ Columna Valor_SH_Promedio agregada
✓ Columna Proporcion_SH agregada
✓ Columna Saldo_SH_Fiscal_Hist agregada
✓ Columna Saldo_SH_Fiscal_Act agregada
✓ Columna Valor_SH_Reportable agregada
```

### 1.3 Actualizar Stored Procedure

```bash
sqlcmd -S <servidor> -d Actif_RMF -U <usuario> -P <password> -C \
  -i Database/sp_Calcular_RMF_Activos_Nacionales.sql
```

**Resultado esperado:**
```
SP sp_Calcular_RMF_Activos_Nacionales v5.0-SAFE-HARBOR actualizado
```

### 1.4 Verificar Actualización

```sql
-- Verificar columnas
SELECT TOP 1
    INPC_SH_Junio,
    Factor_SH,
    Valor_SH_Reportable
FROM Calculo_RMF;

-- Verificar SP
EXEC sp_helptext 'sp_Calcular_RMF_Activos_Nacionales';
-- Debe contener 'v5.0 - SAFE HARBOR'
```

---

## 🌐 PASO 2: Desplegar Aplicación Web

### 2.1 Detener Aplicación Actual

**En IIS:**
1. Abrir IIS Manager
2. Seleccionar sitio ActifRMF
3. Click derecho → **Detener**

**O por PowerShell:**
```powershell
Stop-WebAppPool -Name "ActifRMF"
Stop-Website -Name "ActifRMF"
```

### 2.2 Backup de Versión Anterior

```bash
# Renombrar carpeta actual
mv C:\inetpub\wwwroot\ActifRMF C:\inetpub\wwwroot\ActifRMF_v4.5_backup
```

### 2.3 Desplegar Nueva Versión

```bash
# Extraer ZIP en carpeta de IIS
Expand-Archive -Path ActifRMF_v5.0_SafeHarbor.zip -DestinationPath C:\inetpub\wwwroot\
```

### 2.4 Configurar appsettings.json

Editar `C:\inetpub\wwwroot\ActifRMF\appsettings.json`:

```json
{
  "ConnectionStrings": {
    "ActifRMF": "Server=TU_SERVIDOR;Database=Actif_RMF;User Id=TU_USUARIO;Password=TU_PASSWORD;TrustServerCertificate=True;"
  }
}
```

### 2.5 Reiniciar Aplicación

```powershell
Start-WebAppPool -Name "ActifRMF"
Start-Website -Name "ActifRMF"
```

### 2.6 Verificar Funcionamiento

1. Abrir navegador: `http://localhost:5071` (o el puerto configurado)
2. Verificar que la aplicación carga correctamente
3. Ir a página de reportes
4. Debe mostrar columnas de Safe Harbor

---

## 🧪 PASO 3: Prueba de Funcionamiento

### 3.1 Ejecutar Cálculo de Prueba

```sql
-- Ejecutar para una compañía de prueba
EXEC sp_Calcular_RMF_Activos_Nacionales
    @ID_Compania = 188,  -- Cambiar por tu compañía
    @Año_Calculo = 2024;
```

**Resultado esperado:**
```
========================================
Cálculo RMF Activos Nacionales v5.0 - SAFE HARBOR
========================================
...
INPC de junio 2024: 134.594000
...
Total valor FISCAL (MXN): $XXX,XXX.XX
Total valor SAFE HARBOR (MXN): $XXX,XXX.XX
========================================
```

### 3.2 Verificar Resultados

```sql
SELECT TOP 10
    ID_NUM_ACTIVO,
    -- Columnas FISCALES
    Valor_Reportable_MXN AS Fiscal,
    INPCUtilizado AS INPC_Fiscal,
    -- Columnas SAFE HARBOR (nuevas)
    Valor_SH_Reportable AS SafeHarbor,
    INPC_SH_Junio AS INPC_SH,
    Factor_SH
FROM Calculo_RMF
WHERE ID_Compania = 188
  AND Año_Calculo = 2024
  AND Tipo_Activo = 'Nacional'
ORDER BY ID_NUM_ACTIVO;
```

**Resultado esperado:**
- Columnas de Safe Harbor deben tener valores
- `Valor_SH_Reportable` generalmente mayor que `Valor_Reportable_MXN`
- `INPC_SH_Junio` debe ser 134.594 (para 2024)

---

## 📊 PASO 4: Actualizar Reportes (Opcional)

Si usan reportes externos (Power BI, Crystal Reports, etc.), actualizar queries para incluir columnas Safe Harbor:

**Columnas disponibles:**
- `INPC_SH_Junio` - INPC de junio (fijo)
- `Factor_SH` - Factor de actualización Safe Harbor
- `Saldo_SH_Actualizado` - Saldo actualizado SH
- `Dep_SH_Actualizada` - Depreciación actualizada SH
- `Valor_SH_Promedio` - Valor promedio SH
- `Proporcion_SH` - Proporción SH
- `Saldo_SH_Fiscal_Hist` - Saldo fiscal histórico
- `Saldo_SH_Fiscal_Act` - Saldo fiscal actualizado
- **`Valor_SH_Reportable`** - **Resultado final Safe Harbor**

---

## 🔧 Solución de Problemas

### Error: "Invalid column name 'INPC_SH_Junio'"

**Causa:** No se ejecutó el script de actualización de BD

**Solución:**
```sql
USE Actif_RMF;
GO
-- Ejecutar DEPLOY_v5.0_ACTUALIZACION_BD.sql
```

### Error: "Procedure has no parameters"

**Causa:** SP no se actualizó correctamente

**Solución:**
```sql
-- Verificar versión del SP
EXEC sp_helptext 'sp_Calcular_RMF_Activos_Nacionales';
-- Si no dice 'v5.0', ejecutar sp_Calcular_RMF_Activos_Nacionales.sql
```

### Aplicación web no carga

**Verificar:**
1. Connection string correcto en appsettings.json
2. Usuario SQL tiene permisos en Actif_RMF
3. Puerto no está en uso por otra aplicación

```powershell
# Ver puertos en uso
netstat -ano | findstr :5071
```

### Valores Safe Harbor son NULL

**Causa:** No se ha ejecutado el cálculo con la nueva versión

**Solución:**
```sql
-- Borrar cálculos antiguos y recalcular
DELETE FROM Calculo_RMF
WHERE ID_Compania = 188
  AND Año_Calculo = 2024;

-- Ejecutar de nuevo
EXEC sp_Calcular_RMF_Activos_Nacionales 188, 2024;
```

---

## 🔄 Rollback (Si es necesario)

Si necesitas regresar a la versión anterior:

### 1. Restaurar BD

```sql
-- Solo si hiciste backup
DROP TABLE Calculo_RMF;
EXEC sp_rename 'Calculo_RMF_BACKUP_20251113', 'Calculo_RMF';

-- Restaurar SP anterior (usar backup guardado)
```

### 2. Restaurar Aplicación

```bash
# Detener v5.0
Stop-Website -Name "ActifRMF"

# Eliminar v5.0
Remove-Item C:\inetpub\wwwroot\ActifRMF -Recurse -Force

# Restaurar v4.5
Move-Item C:\inetpub\wwwroot\ActifRMF_v4.5_backup C:\inetpub\wwwroot\ActifRMF

# Iniciar
Start-Website -Name "ActifRMF"
```

---

## 📞 Soporte

**Problemas técnicos:**
- Revisar archivo `CAMBIOS_SAFE_HARBOR.md` para detalles técnicos
- Contactar equipo de desarrollo

**Preguntas sobre cálculos:**
- Revisar documentación en `FORMULAS_EXACTAS.md`
- Comparar con Excel de ejemplo

---

## ✅ Checklist de Instalación

- [ ] Backup de BD realizado
- [ ] Script DEPLOY_v5.0_ACTUALIZACION_BD.sql ejecutado
- [ ] SP sp_Calcular_RMF_Activos_Nacionales.sql ejecutado
- [ ] Verificación de columnas OK
- [ ] Aplicación web detenida
- [ ] Backup de versión anterior realizado
- [ ] Nueva versión desplegada
- [ ] appsettings.json configurado
- [ ] Aplicación web iniciada
- [ ] Prueba de cálculo realizada
- [ ] Resultados verificados en BD
- [ ] Reportes actualizados (si aplica)
- [ ] Usuarios notificados del cambio

---

**Fin de las instrucciones de instalación**

**Versión:** v5.0-SafeHarbor
**Última actualización:** 2025-11-13
