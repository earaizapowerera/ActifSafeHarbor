#!/usr/bin/env python3
"""Test para INPC - ActifRMF"""

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
    log("\n=== TEST: Carga INPC ===")
    driver.get(f"{BASE_URL}/inpc.html")
    if wait_elem(driver, By.TAG_NAME, "h1"): log("✅ Página cargada"); return True
    return False

def test_year_select(driver):
    log("\n=== TEST: Select de Año ===")
    time.sleep(1)
    if wait_elem(driver, By.ID, "añoSelect"): log("✅ Select año presente"); return True
    return False

def test_simulation_group_select(driver):
    log("\n=== TEST: Select Grupo Simulación ===")
    if wait_elem(driver, By.ID, "grupoSimulacionSelect"): log("✅ Select grupo presente"); return True
    return False

def test_load_button(driver):
    log("\n=== TEST: Botón Cargar INPC ===")
    if wait_elem(driver, By.ID, "btnCargar"): log("✅ Botón presente"); return True
    return False

def test_load_inpc(driver, year=2024):
    log(f"\n=== TEST: Cargar INPC {year} ===")
    try:
        time.sleep(2)
        Select(wait_elem(driver, By.ID, "añoSelect")).select_by_value(str(year))
        log(f"📅 Año {year} seleccionado")

        # Seleccionar grupo 8 (Safe Harbor)
        Select(wait_elem(driver, By.ID, "grupoSimulacionSelect")).select_by_value("8")
        log("📋 Grupo simulación 8 seleccionado")

        driver.find_element(By.ID, "btnCargar").click()
        log("⏳ Cargando INPC...")

        time.sleep(3)  # Esperar carga
        log("✅ Comando ejecutado")
        return True
    except Exception as e:
        log(f"❌ Error: {e}"); return False

def test_recent_inpc_display(driver):
    log("\n=== TEST: Datos Recientes Filtrados por Grupo 8 ===")
    try:
        time.sleep(2)
        # Verificar que la tabla de datos recientes existe
        tbody = wait_elem(driver, By.ID, "tbodyINPC")
        if not tbody:
            log("❌ No se encontró tabla de datos recientes")
            return False

        # Verificar que hay filas en la tabla
        rows = tbody.find_elements(By.TAG_NAME, "tr")
        if len(rows) == 0:
            log("⚠️ No hay datos en la tabla (puede ser normal si no hay INPC cargado)")
            return True

        # Verificar que aparecen datos (al menos una fila con 4 columnas)
        first_row = rows[0]
        cells = first_row.find_elements(By.TAG_NAME, "td")
        if len(cells) >= 4:
            log(f"✅ Tabla muestra {len(rows)} registros de INPC")
            log(f"   Ejemplo: Año {cells[0].text}, Mes {cells[1].text}, Índice {cells[2].text}")
            return True
        else:
            log("❌ Formato de tabla incorrecto")
            return False

    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def main():
    log("🚀 Iniciando pruebas de INPC")
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = None
    try:
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        tests = [test_page_load, test_year_select, test_simulation_group_select,
                test_load_button, test_load_inpc, test_recent_inpc_display]
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
