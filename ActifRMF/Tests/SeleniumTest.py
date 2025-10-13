#!/usr/bin/env python3
"""
Test de Selenium para ActifRMF
Prueba el flujo completo del sistema incluyendo:
- Actualización de queries ETL
- Ejecución de ETL
- Verificación de query ejecutado
- Navegación entre páginas
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select
from selenium.common.exceptions import TimeoutException
import time
import sys

BASE_URL = "http://localhost:5071"

# Query Safe Harbor para todas las compañías
SAFE_HARBOR_QUERY = """-- Query ETL para Safe Harbor - TODOS los activos en uso
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    a.COSTO_REVALUADO,
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC AS FECHA_INICIO_DEP,
    a.STATUS,
    CAST(CASE WHEN a.FLG_PROPIO = 'P' THEN 1 ELSE 0 END AS INT) AS FLG_PROPIO,
    CASE WHEN pd.NUM_ANOS_DEPRECIAR > 0
         THEN (100.0 / pd.NUM_ANOS_DEPRECIAR)
         ELSE 0
    END AS Tasa_Anual,
    CASE
        WHEN ISNULL(pd.NUM_ANOS_DEPRECIAR, 0) > 0
        THEN (100.0 / pd.NUM_ANOS_DEPRECIAR / 12.0)
        ELSE 0
    END AS Tasa_Mensual,
    ISNULL(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año
FROM activo a
INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS
LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA
LEFT JOIN porcentaje_depreciacion pd
    ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
    AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
    AND pd.ID_TIPO_DEP = 2
LEFT JOIN calculo c
    ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO
    AND c.ID_COMPANIA = @ID_COMPANIA
    AND c.ID_ANO = @AÑO_ANTERIOR
    AND c.ID_MES = 12
    AND c.ID_TIPO_DEP = 2
WHERE a.ID_COMPANIA = @ID_COMPANIA
  AND a.STATUS = 'A'
  AND a.FECHA_COMPRA IS NOT NULL
  AND a.FECHA_COMPRA <= CAST(@AÑO_CALCULO AS VARCHAR) + '-12-31'"""

def log(message):
    """Imprime mensaje con timestamp"""
    print(f"[{time.strftime('%H:%M:%S')}] {message}")

def wait_for_element(driver, by, value, timeout=10):
    """Espera a que un elemento esté presente"""
    try:
        element = WebDriverWait(driver, timeout).until(
            EC.presence_of_element_located((by, value))
        )
        return element
    except TimeoutException:
        log(f"❌ Timeout esperando elemento: {value}")
        return None

def test_dashboard(driver):
    """Prueba el dashboard"""
    log("\n=== PROBANDO DASHBOARD ===")
    driver.get(f"{BASE_URL}/index.html")

    # Verificar que cargue el título
    title = wait_for_element(driver, By.TAG_NAME, "h1")
    if title and "Dashboard RMF" in title.text:
        log("✅ Dashboard cargado correctamente")
        return True
    else:
        log("❌ Error cargando dashboard")
        return False

def test_update_company_queries(driver):
    """Actualiza las queries de todas las compañías"""
    log("\n=== ACTUALIZANDO QUERIES DE COMPAÑÍAS ===")
    driver.get(f"{BASE_URL}/companias.html")

    # Esperar a que cargue la tabla
    time.sleep(2)

    # Buscar todas las filas de compañías
    try:
        edit_buttons = driver.find_elements(By.CSS_SELECTOR, "button[onclick*='editarCompania']")
        log(f"📋 Encontradas {len(edit_buttons)} compañías")

        companies_updated = 0
        for i in range(len(edit_buttons)):
            # Re-buscar los botones cada vez (para evitar stale element)
            edit_buttons = driver.find_elements(By.CSS_SELECTOR, "button[onclick*='editarCompania']")
            if i >= len(edit_buttons):
                break

            edit_buttons[i].click()
            time.sleep(1)

            # Esperar a que se abra el modal
            modal = wait_for_element(driver, By.ID, "modalCompania")
            if not modal:
                continue

            # Obtener el nombre de la compañía
            nombre_input = driver.find_element(By.ID, "nombreCompania")
            nombre = nombre_input.get_attribute("value")

            # Actualizar el query ETL
            query_textarea = driver.find_element(By.ID, "queryETL")
            driver.execute_script("arguments[0].value = arguments[1];", query_textarea, SAFE_HARBOR_QUERY)

            # Guardar
            save_button = driver.find_element(By.ID, "btnGuardar")
            save_button.click()

            # Manejar el alert de confirmación
            try:
                WebDriverWait(driver, 3).until(EC.alert_is_present())
                alert = driver.switch_to.alert
                alert.accept()
                log(f"✅ Query actualizado para: {nombre}")
                companies_updated += 1
            except:
                log(f"⚠️  No hubo alert para: {nombre}")

            # Esperar a que se cierre el modal
            time.sleep(2)

        log(f"✅ Total de compañías actualizadas: {companies_updated}")
        return True

    except Exception as e:
        log(f"❌ Error actualizando queries: {str(e)}")
        return False

def test_etl_execution(driver, company_id=188, year=2024):
    """Prueba la ejecución del ETL"""
    log(f"\n=== EJECUTANDO ETL PARA COMPAÑÍA {company_id} ===")
    driver.get(f"{BASE_URL}/extraccion.html")

    try:
        # Esperar a que cargue el select de compañías
        time.sleep(2)

        # Seleccionar compañía
        company_select = Select(wait_for_element(driver, By.ID, "companiaSelect"))
        company_select.select_by_value(str(company_id))
        log(f"📋 Compañía {company_id} seleccionada")

        # Ingresar año
        year_input = driver.find_element(By.ID, "anioCalculo")
        year_input.clear()
        year_input.send_keys(str(year))
        log(f"📅 Año {year} ingresado")

        # Ejecutar ETL
        execute_button = driver.find_element(By.ID, "btnEjecutar")
        execute_button.click()
        log("⏳ ETL iniciado, esperando resultado...")

        # Esperar resultado (hasta 60 segundos)
        result_div = wait_for_element(driver, By.ID, "resultadoDiv", timeout=60)
        if not result_div:
            log("❌ Timeout esperando resultado del ETL")
            return False

        # Verificar si fue exitoso
        time.sleep(2)
        result_content = driver.find_element(By.ID, "resultadoContent")

        if "exitosamente" in result_content.text.lower():
            log("✅ ETL ejecutado exitosamente")

            # Buscar el query ejecutado
            try:
                query_section = driver.find_element(By.ID, "queryExecutedSection")
                if query_section.is_displayed():
                    query_content = driver.find_element(By.ID, "queryExecutedContent")
                    executed_query = query_content.text

                    log("\n📄 QUERY EJECUTADO:")
                    log("="*80)
                    log(executed_query[:500] + "..." if len(executed_query) > 500 else executed_query)
                    log("="*80)

                    # Verificar que contiene STATUS = 'A'
                    if "STATUS = 'A'" in executed_query:
                        log("✅ Query contiene filtro Safe Harbor (STATUS = 'A')")
                    else:
                        log("⚠️  Query NO contiene filtro Safe Harbor")

                    # Verificar si trae FLG_PROPIO
                    if "FLG_PROPIO" in executed_query:
                        log("✅ Query incluye campo FLG_PROPIO")
                    else:
                        log("⚠️  Query NO incluye FLG_PROPIO")

                    # Verificar COSTO_REVALUADO
                    if "COSTO_REVALUADO" in executed_query:
                        log("✅ Query incluye COSTO_REVALUADO")
                    else:
                        log("⚠️  Query NO incluye COSTO_REVALUADO")

                else:
                    log("⚠️  Sección de query ejecutado no visible")

            except Exception as e:
                log(f"⚠️  No se pudo obtener el query ejecutado: {str(e)}")

            # Verificar número de registros
            if "0 registros" in result_content.text or "Registros Importados:\n0" in result_content.text:
                log("⚠️  ETL retornó 0 registros - revisar query ejecutado arriba")
            else:
                log("✅ ETL importó registros exitosamente")

            return True
        else:
            log(f"❌ ETL falló: {result_content.text[:200]}")
            return False

    except Exception as e:
        log(f"❌ Error ejecutando ETL: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def test_navigation(driver):
    """Prueba la navegación entre páginas"""
    log("\n=== PROBANDO NAVEGACIÓN ===")

    pages = [
        ("Dashboard", "/index.html"),
        ("Compañías", "/companias.html"),
        ("Extracción ETL", "/extraccion.html"),
        ("INPC", "/inpc.html"),
        ("Reporte", "/reporte.html")
    ]

    for name, url in pages:
        try:
            driver.get(f"{BASE_URL}{url}")
            time.sleep(1)

            # Verificar que el navbar esté presente
            navbar = wait_for_element(driver, By.CLASS_NAME, "navbar", timeout=5)
            if navbar:
                log(f"✅ {name} - Navbar presente")
            else:
                log(f"⚠️  {name} - Navbar no encontrado")

        except Exception as e:
            log(f"❌ Error navegando a {name}: {str(e)}")

def main():
    """Función principal"""
    log("🚀 Iniciando pruebas de Selenium para ActifRMF")
    log(f"🌐 URL Base: {BASE_URL}")

    # Configurar Chrome
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')  # Ejecutar sin interfaz gráfica
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1920,1080')

    driver = None
    try:
        log("🔧 Iniciando Chrome WebDriver...")
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        # Ejecutar pruebas
        tests_passed = 0
        tests_total = 4

        if test_dashboard(driver):
            tests_passed += 1

        if test_update_company_queries(driver):
            tests_passed += 1

        if test_etl_execution(driver, company_id=188, year=2024):
            tests_passed += 1

        if test_navigation(driver):
            tests_passed += 1

        # Resumen
        log("\n" + "="*80)
        log(f"📊 RESUMEN: {tests_passed}/{tests_total} pruebas exitosas")
        log("="*80)

        if tests_passed == tests_total:
            log("✅ TODAS LAS PRUEBAS PASARON")
            return 0
        else:
            log("⚠️  ALGUNAS PRUEBAS FALLARON")
            return 1

    except Exception as e:
        log(f"❌ Error fatal: {str(e)}")
        import traceback
        traceback.print_exc()
        return 1

    finally:
        if driver:
            log("🔚 Cerrando navegador...")
            driver.quit()

if __name__ == "__main__":
    sys.exit(main())
