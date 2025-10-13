#!/usr/bin/env python3
"""
Test para Compañías - ActifRMF
Verifica la gestión de compañías y actualización de queries ETL
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import sys

BASE_URL = "http://localhost:5071"

# Query Safe Harbor para todas las compañías
SAFE_HARBOR_QUERY = """-- Query ETL para Safe Harbor - TODOS los activos en uso
-- INPC se obtiene por separado, no en el ETL de activos
SELECT
    a.ID_NUM_ACTIVO,
    a.ID_ACTIVO,
    a.ID_TIPO_ACTIVO,
    a.ID_SUBTIPO_ACTIVO,
    ta.DESCRIPCION AS Nombre_TipoActivo,
    a.DESCRIPCION,
    a.COSTO_ADQUISICION,
    ISNULL(a.COSTO_REVALUADO, a.COSTO_ADQUISICION) AS Costo_Fiscal,
    a.ID_MONEDA,
    m.NOMBRE AS Nombre_Moneda,
    a.ID_PAIS,
    p.NOMBRE AS Nombre_Pais,
    a.FECHA_COMPRA,
    a.FECHA_BAJA,
    a.FECHA_INIC_DEPREC,
    a.STATUS,
    a.FLG_PROPIO,
    ISNULL(pd.PORC_BENEFICIO, 0) AS Tasa_Anual,
    CASE
        WHEN ISNULL(pd.PORC_BENEFICIO, 0) > 0
        THEN (pd.PORC_BENEFICIO / 12.0)
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
    except:
        log(f"❌ Timeout esperando elemento: {value}")
        return None

def test_companias_page_load(driver):
    """Prueba que la página de compañías cargue"""
    log("\n=== TEST: Carga de Página Compañías ===")
    driver.get(f"{BASE_URL}/companias.html")

    title = wait_for_element(driver, By.TAG_NAME, "h1")
    if title and "Compañías" in title.text:
        log("✅ Página de compañías cargada")
        return True
    else:
        log("❌ Error cargando página de compañías")
        return False

def test_companias_grid(driver):
    """Prueba que la tabla de compañías esté presente"""
    log("\n=== TEST: Grid de Compañías ===")

    time.sleep(2)  # Esperar a que cargue el grid

    # Verificar que hay botones de editar
    edit_buttons = driver.find_elements(By.CSS_SELECTOR, "button[onclick*='editarCompania']")
    if len(edit_buttons) > 0:
        log(f"✅ {len(edit_buttons)} compañías encontradas")
        return True
    else:
        log("❌ No se encontraron compañías")
        return False

def test_edit_company_query(driver):
    """Prueba la edición de query de una compañía"""
    log("\n=== TEST: Edición de Query de Compañía ===")

    time.sleep(2)

    # Buscar primer botón de editar
    edit_buttons = driver.find_elements(By.CSS_SELECTOR, "button[onclick*='editarCompania']")
    if len(edit_buttons) == 0:
        log("❌ No hay compañías para editar")
        return False

    # Click en el primer botón
    edit_buttons[0].click()
    time.sleep(1)

    # Esperar modal
    modal = wait_for_element(driver, By.ID, "modalCompania")
    if not modal:
        log("❌ Modal no apareció")
        return False

    log("✅ Modal abierto")

    # Obtener nombre de la compañía
    nombre_input = driver.find_element(By.ID, "nombreCompania")
    nombre = nombre_input.get_attribute("value")
    log(f"📋 Editando compañía: {nombre}")

    # Actualizar query
    query_textarea = driver.find_element(By.ID, "queryETL")
    driver.execute_script("arguments[0].value = arguments[1];", query_textarea, SAFE_HARBOR_QUERY)
    log("✅ Query actualizado")

    # Guardar
    save_button = driver.find_element(By.ID, "btnGuardar")
    save_button.click()

    # Manejar alert
    try:
        WebDriverWait(driver, 3).until(EC.alert_is_present())
        alert = driver.switch_to.alert
        alert.accept()
        log(f"✅ Compañía guardada: {nombre}")
        return True
    except:
        log("⚠️  No hubo confirmación")
        return False

def test_new_company_button(driver):
    """Prueba que el botón de nueva compañía esté presente"""
    log("\n=== TEST: Botón Nueva Compañía ===")

    new_button = wait_for_element(driver, By.ID, "btnNuevaCompania")
    if new_button:
        log("✅ Botón 'Nueva Compañía' presente")
        return True
    else:
        log("❌ Botón 'Nueva Compañía' no encontrado")
        return False

def main():
    """Función principal"""
    log("🚀 Iniciando pruebas de Compañías")
    log(f"🌐 URL Base: {BASE_URL}")

    # Configurar Chrome
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1920,1080')

    driver = None
    try:
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        # Ejecutar pruebas
        tests = [
            test_companias_page_load,
            test_companias_grid,
            test_new_company_button,
            test_edit_company_query
        ]

        passed = 0
        for test in tests:
            if test(driver):
                passed += 1

        # Resumen
        log("\n" + "="*80)
        log(f"📊 RESUMEN: {passed}/{len(tests)} pruebas exitosas")
        log("="*80)

        return 0 if passed == len(tests) else 1

    except Exception as e:
        log(f"❌ Error fatal: {str(e)}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if driver:
            driver.quit()

if __name__ == "__main__":
    sys.exit(main())
