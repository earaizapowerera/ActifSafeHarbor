# Plan de Pruebas - ActifRMF

## Descripción General

Suite de pruebas automatizadas con Selenium para el sistema ActifRMF de cálculo de RMF (Safe Harbor).

**URL Base**: http://localhost:5071

## Prerrequisitos

```bash
# Instalar dependencias
pip3 install selenium

# Verificar Chrome/Chromium instalado
google-chrome --version

# Verificar aplicación corriendo
curl http://localhost:5071
```

## Archivos de Test

### 1. `test_dashboard.py` - Dashboard Principal

**Propósito**: Verificar carga y visualización del dashboard

**Tests incluidos**:
- ✅ Carga de página dashboard
- ✅ Presencia del navbar compartido
- ✅ Verificación de todos los items del menú
- ✅ Presencia de tarjetas informativas

**Ejecución**:
```bash
cd /Users/enrique/ActifRMF/ActifRMF/Tests
python3 test_dashboard.py
```

**Resultado esperado**: 4/4 tests exitosos

---

### 2. `test_companias.py` - Gestión de Compañías

**Propósito**: Verificar gestión de compañías y actualización de queries ETL

**Tests incluidos**:
- ✅ Carga de página de compañías
- ✅ Visualización del grid de compañías
- ✅ Botón "Nueva Compañía" presente
- ✅ Edición de query ETL (actualiza a Safe Harbor)

**Ejecución**:
```bash
python3 test_companias.py
```

**Resultado esperado**: 4/4 tests exitosos

**Nota**: El test actualiza automáticamente el query ETL de la primera compañía al formato Safe Harbor.

---

### 3. `test_extraccion.py` - Extracción ETL

**Propósito**: Verificar proceso completo de extracción ETL

**Tests incluidos**:
- ✅ Carga de página de extracción
- ✅ Select de compañías presente
- ✅ Ejecución de ETL completa (compañía 188, año 2024)
- ✅ Visualización del query ejecutado

**Validaciones especiales**:
- Query contiene `STATUS = 'A'` (Safe Harbor)
- Query contiene `FLG_PROPIO`
- Query contiene `COSTO_REVALUADO`
- Número de registros importados > 0

**Ejecución**:
```bash
python3 test_extraccion.py
```

**Resultado esperado**: 4/4 tests exitosos

**Prerrequisito**: La compañía 188 debe tener el query Safe Harbor configurado

---

### 4. `test_inpc.py` - Gestión de INPC

**Propósito**: Verificar carga y actualización de índices INPC

**Tests incluidos**:
- ✅ Carga de página INPC
- ✅ Select de año presente
- ✅ Select de grupo de simulación presente
- ✅ Botón de carga presente
- ✅ Ejecución de carga INPC (año 2024, grupo 8)

**Ejecución**:
```bash
python3 test_inpc.py
```

**Resultado esperado**: 5/5 tests exitosos

**Nota**: Utiliza grupo de simulación 8 (Safe Harbor)

---

### 5. `test_reporte.py` - Visualización de Reporte

**Propósito**: Verificar visualización y exportación de reportes

**Tests incluidos**:
- ✅ Carga de página de reporte
- ✅ Select de compañía presente
- ✅ Select de año presente
- ✅ AG-Grid presente
- ✅ Botón exportar a Excel presente

**Ejecución**:
```bash
python3 test_reporte.py
```

**Resultado esperado**: 5/5 tests exitosos

---

### 6. `SeleniumTest.py` - Test Integrado Completo

**Propósito**: Flujo completo del sistema end-to-end

**Tests incluidos**:
- ✅ Dashboard
- ✅ Actualización de queries de TODAS las compañías
- ✅ Ejecución de ETL
- ✅ Navegación entre todas las páginas

**Ejecución**:
```bash
python3 SeleniumTest.py
```

**Resultado esperado**: 4/4 tests exitosos

**Advertencia**: Este test modifica queries de TODAS las compañías. Usar con precaución.

---

## Ejecución de Todos los Tests

### Ejecutar todos los tests individuales:

```bash
#!/bin/bash
cd /Users/enrique/ActifRMF/ActifRMF/Tests

echo "=== Ejecutando Suite de Pruebas ActifRMF ==="
echo ""

python3 test_dashboard.py
echo ""

python3 test_companias.py
echo ""

python3 test_extraccion.py
echo ""

python3 test_inpc.py
echo ""

python3 test_reporte.py
echo ""

echo "=== Suite de Pruebas Completada ==="
```

### Script Master de Tests:

```bash
# Guardar como run_all_tests.sh
chmod +x run_all_tests.sh
./run_all_tests.sh
```

---

## Configuración de Base de Datos Requerida

### Antes de ejecutar los tests, asegúrate de:

1. **Ejecutar script de migración de tabla**:
   ```sql
   -- /Users/enrique/ActifRMF/SQL/05_ALTER_Staging_Activo_Safe_Harbor.sql
   -- Agrega COSTO_REVALUADO, elimina campos INPC
   ```

2. **Desplegar stored procedure Safe Harbor**:
   ```sql
   -- /Users/enrique/ActifRMF/SQL/06_SP_Calcular_RMF_Safe_Harbor.sql
   -- Lógica de cálculo Safe Harbor
   ```

3. **Actualizar queries de compañías** (automático vía test_companias.py):
   ```sql
   -- Ver: /tmp/query_etl_safe_harbor.sql
   ```

---

## Troubleshooting

### Error: "Invalid column name 'Costo_Fiscal'"
**Solución**: Ejecutar script de migración `05_ALTER_Staging_Activo_Safe_Harbor.sql`

### Error: "Connection refused to localhost:5071"
**Solución**:
```bash
cd /Users/enrique/ActifRMF/ActifRMF
dotnet run --urls="http://localhost:5071"
```

### Error: "0 registros importados"
**Solución**: Verificar que:
- La compañía tenga datos con `STATUS = 'A'`
- El query ETL esté actualizado al formato Safe Harbor
- La conexión a la base de datos Actif sea correcta

### Tests fallan con "element not found"
**Solución**:
- Aumentar tiempos de espera en los tests
- Verificar que la aplicación web esté completamente cargada
- Revisar que los IDs de elementos HTML no hayan cambiado

---

## Estrategia de Testing

### Tests Unitarios por Pantalla
- Cada pantalla tiene su propio archivo de test
- Tests rápidos y focalizados
- Fácil identificación de problemas

### Test Integrado
- `SeleniumTest.py` verifica flujo completo
- Usa para validación de releases
- Más lento pero más completo

### Frecuencia Recomendada
- **Antes de commit**: Tests individuales de pantallas modificadas
- **Antes de push**: Suite completa de tests
- **Antes de deploy**: Test integrado completo

---

## Próximas Mejoras

- [ ] Test de cálculo RMF (cuando esté implementado)
- [ ] Validación de contenido de reportes
- [ ] Tests de performance (tiempo de ETL)
- [ ] Tests de concurrencia (múltiples usuarios)
- [ ] Integración con CI/CD

---

## Notas Importantes

1. **Safe Harbor Query**: Los tests verifican que el query ETL incluya:
   - `STATUS = 'A'` (solo activos en uso)
   - `FLG_PROPIO` (flag de propiedad para documentación)
   - `COSTO_REVALUADO` (valor fiscal del activo)
   - Sin filtros por `FLG_PROPIO = 'S'`

2. **INPC Separado**: Los tests validan que INPC se maneje por separado (no en ETL)

3. **Grupo Simulación 8**: Tests de INPC usan grupo 8 por defecto (Safe Harbor)

4. **Headless Mode**: Tests corren en modo headless (sin interfaz gráfica)

---

## Contacto y Soporte

Para problemas con los tests:
1. Revisar logs de la aplicación en consola
2. Verificar que la base de datos esté accesible
3. Comprobar que las migraciones SQL estén aplicadas
4. Ejecutar tests individuales para aislar el problema
