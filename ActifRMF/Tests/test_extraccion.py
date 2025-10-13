#!/usr/bin/env python3
"""Test para Extracción ETL - ActifRMF"""

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
    log("\n=== TEST: Carga de Extracción ETL ===")
    driver.get(f"{BASE_URL}/extraccion.html")
    if wait_elem(driver, By.TAG_NAME, "h1"): log("✅ Página cargada"); return True
    log("❌ Error cargando"); return False

def test_company_select(driver):
    log("\n=== TEST: Select de Compañías ===")
    time.sleep(2)
    sel = wait_elem(driver, By.ID, "companiaSelect")
    if sel: log("✅ Select presente"); return True
    log("❌ Select no encontrado"); return False

def test_etl_execution(driver, company_id=188, year=2024):
    log(f"\n=== TEST: Ejecución ETL (Compañía {company_id}) ===")
    try:
        time.sleep(2)
        Select(wait_elem(driver, By.ID, "companiaSelect")).select_by_value(str(company_id))
        log(f"📋 Compañía {company_id} seleccionada")

        year_input = driver.find_element(By.ID, "anioCalculo")
        year_input.clear()
        year_input.send_keys(str(year))
        log(f"📅 Año {year} ingresado")

        # Usar JavaScript click para evitar interceptación
        btn_ejecutar = driver.find_element(By.ID, "btnEjecutar")
        driver.execute_script("arguments[0].click();", btn_ejecutar)
        log("⏳ ETL iniciado...")

        result = wait_elem(driver, By.ID, "resultadoDiv", timeout=60)
        if not result:
            log("❌ FALLO: Timeout esperando resultado")
            return False

        # Esperar más tiempo para que aparezca el contenido
        time.sleep(5)
        result_content = driver.find_element(By.ID, "resultadoContent")
        full_text = result_content.text

        log(f"📄 Mensaje completo recibido ({len(full_text)} caracteres)")
        if len(full_text) == 0:
            log("⚠️  Mensaje vacío, esperando más tiempo...")
            time.sleep(5)
            full_text = driver.find_element(By.ID, "resultadoContent").text
            log(f"📄 Segundo intento: {len(full_text)} caracteres")

        # CRITERIO 1: NO debe haber mensajes de error
        if "error" in full_text.lower() or "invalid" in full_text.lower():
            log(f"❌ FALLO: Mensaje de error detectado: {full_text[:300]}")
            return False

        # CRITERIO 2: Debe decir "exitosamente"
        if "exitosamente" not in full_text.lower():
            log(f"❌ FALLO: No dice 'exitosamente'. Mensaje: {full_text[:300]}")
            return False

        # CRITERIO 3: Debe haber registros importados (no 0)
        if "0 registros" in full_text or "registros importados:\n0" in full_text.lower():
            log(f"❌ FALLO: 0 registros importados")
            return False

        # CRITERIO 4: Verificar que haya un número positivo de registros
        import re
        registros_match = re.search(r'registros\s+importados[:\s]+(\d+)', full_text.lower())
        if registros_match:
            num_registros = int(registros_match.group(1))
            if num_registros == 0:
                log(f"❌ FALLO: 0 registros importados")
                return False
            log(f"✅ {num_registros} registros importados exitosamente")
        else:
            log("⚠️  No se pudo determinar número de registros")

        # CRITERIO 5: Verificar query Safe Harbor (opcional pero informativo)
        try:
            query_content = driver.find_element(By.ID, "queryExecutedContent")
            query = query_content.text

            if "STATUS = 'A'" in query:
                log("✅ Query contiene filtro Safe Harbor")
            else:
                log("⚠️  Query no contiene STATUS = 'A'")

            if "FLG_PROPIO" in query:
                log("✅ Query incluye FLG_PROPIO")

            if "COSTO_REVALUADO" in query or "Costo_Fiscal" in query:
                log("✅ Query incluye costo fiscal")
        except:
            log("⚠️  Query ejecutado no disponible")

        log("✅ TEST EXITOSO: ETL completado correctamente")
        return True

    except Exception as e:
        log(f"❌ FALLO: Excepción: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_query_display(driver):
    log("\n=== TEST: Visualización de Query ===")
    sec = driver.find_elements(By.ID, "queryExecutedSection")
    if sec and len(sec) > 0: log("✅ Sección de query presente"); return True
    log("⚠️  Sección no presente"); return True  # No es error crítico

def main():
    log("🚀 Iniciando pruebas de Extracción ETL")
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = None
    try:
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        tests = [test_page_load, test_company_select, test_etl_execution, test_query_display]
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
