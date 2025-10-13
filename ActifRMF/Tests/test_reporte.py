#!/usr/bin/env python3
"""Test para Reporte - ActifRMF"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
import time, sys

BASE_URL = "http://localhost:5071"

def log(msg): print(f"[{time.strftime('%H:%M:%S')}] {msg}")
def wait_elem(driver, by, val, timeout=10):
    try: return WebDriverWait(driver, timeout).until(EC.presence_of_element_located((by, val)))
    except: log(f"❌ Timeout: {val}"); return None

def test_page_load(driver):
    log("\n=== TEST: Carga Reporte ===")
    driver.get(f"{BASE_URL}/reporte.html")
    if wait_elem(driver, By.TAG_NAME, "h1"): log("✅ Página cargada"); return True
    return False

def test_company_select(driver):
    log("\n=== TEST: Select Compañía ===")
    time.sleep(1)
    if wait_elem(driver, By.ID, "companiaSelect"): log("✅ Select presente"); return True
    return False

def test_year_select(driver):
    log("\n=== TEST: Select Año ===")
    if wait_elem(driver, By.ID, "añoSelect"): log("✅ Select presente"); return True
    return False

def test_ag_grid(driver):
    log("\n=== TEST: AG-Grid ===")
    if wait_elem(driver, By.ID, "reporteGrid"): log("✅ Grid presente"); return True
    return False

def test_export_button(driver):
    log("\n=== TEST: Botón Exportar ===")
    if wait_elem(driver, By.ID, "btnExportarExcel"): log("✅ Botón presente"); return True
    return False

def main():
    log("🚀 Iniciando pruebas de Reporte")
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = None
    try:
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        tests = [test_page_load, test_company_select, test_year_select,
                test_ag_grid, test_export_button]
        passed = sum([1 for t in tests if t(driver)])

        log("\n" + "="*80)
        log(f"📊 RESUMEN: {passed}/{len(tests)} pruebas exitosas")
        log("="*80)
        return 0 if passed == len(tests) else 1
    except Exception as e:
        log(f"❌ Error: {e}"); return 1
    finally:
        if driver: driver.quit()

if __name__ == "__main__": sys.exit(main())
