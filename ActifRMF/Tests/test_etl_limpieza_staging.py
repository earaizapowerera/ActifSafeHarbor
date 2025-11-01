#!/usr/bin/env python3
"""
Test Selenium - Verificar limpieza de staging en ETL
Ejecuta el ETL dos veces y verifica que limpia correctamente los datos previos
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
import time
import sys

BASE_URL = "http://localhost:5071"
COMPANY_ID = 188
YEAR = 2024

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def ejecutar_etl(driver):
    """Ejecuta el ETL desde la interfaz web y retorna el texto del resultado"""
    driver.get(f"{BASE_URL}/extraccion.html")
    time.sleep(2)

    # Seleccionar compañía
    select = Select(driver.find_element(By.ID, "companiaSelect"))
    select.select_by_value(str(COMPANY_ID))

    # Ingresar año
    year_input = driver.find_element(By.ID, "anioCalculo")
    year_input.clear()
    year_input.send_keys(str(YEAR))

    # Ejecutar ETL
    btn = driver.find_element(By.ID, "btnEjecutar")
    driver.execute_script("arguments[0].click();", btn)
    log("ETL iniciado...")

    # Esperar resultado (hasta 120 segundos)
    result_div = WebDriverWait(driver, 120).until(
        EC.presence_of_element_located((By.ID, "resultadoDiv"))
    )

    time.sleep(3)
    result_content = driver.find_element(By.ID, "resultadoContent")
    return result_content.text

def test_limpieza_staging(driver):
    """Test: Verificar que el ETL limpia staging antes de importar"""
    log("\n=== TEST: Limpieza de Staging ===" )

    try:
        # Primera ejecución
        log("\n1️⃣ Primera ejecución del ETL...")
        result1 = ejecutar_etl(driver)

        if "exitosamente" not in result1.lower() and "completado" not in result1.lower():
            log(f"❌ FALLO: Primera ejecución no completó. Resultado: {result1[:200]}")
            return False

        log("✅ Primera ejecución completada")

        # Esperar un momento antes de la segunda ejecución
        time.sleep(5)

        # Segunda ejecución (debe limpiar los datos de la primera)
        log("\n2️⃣ Segunda ejecución del ETL (debe limpiar datos previos)...")
        result2 = ejecutar_etl(driver)

        if "exitosamente" not in result2.lower() and "completado" not in result2.lower():
            log(f"❌ FALLO: Segunda ejecución no completó. Resultado: {result2[:200]}")
            return False

        log("✅ Segunda ejecución completada")

        # Verificar que no hubo error de clave duplicada
        if "duplicate" in result2.lower() or "duplicado" in result2.lower():
            log("❌ FALLO: Se detectó error de clave duplicada (no limpió staging)")
            return False

        if "constraint" in result2.lower() and "violation" in result2.lower():
            log("❌ FALLO: Se detectó violación de constraint (no limpió staging)")
            return False

        log("✅ No se detectaron errores de duplicados")

        # Verificar que ambas ejecuciones importaron registros
        import re
        match1 = re.search(r'(\d+)\s+registros?\s+importados?', result1, re.IGNORECASE)
        match2 = re.search(r'(\d+)\s+registros?\s+importados?', result2, re.IGNORECASE)

        if match1 and match2:
            registros1 = int(match1.group(1))
            registros2 = int(match2.group(1))
            log(f"✅ Primera ejecución: {registros1} registros")
            log(f"✅ Segunda ejecución: {registros2} registros")

            if registros1 > 0 and registros2 > 0:
                log("✅ Ambas ejecuciones importaron registros correctamente")
            else:
                log("⚠️ Una o ambas ejecuciones importaron 0 registros")
        else:
            log("⚠️ No se pudo determinar número de registros en una o ambas ejecuciones")

        log("\n✅ TEST EXITOSO: El ETL limpia staging correctamente")
        return True

    except Exception as e:
        log(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    log("🚀 Iniciando test de limpieza de staging")
    log(f"🌐 URL: {BASE_URL}")
    log(f"🏢 Compañía: {COMPANY_ID}")
    log(f"📅 Año: {YEAR}")

    options = webdriver.ChromeOptions()
    # options.add_argument('--headless')  # Comentado para ver el navegador
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1920,1080')

    driver = None
    try:
        log("\n🔧 Iniciando Chrome WebDriver...")
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        if test_limpieza_staging(driver):
            log("\n" + "="*80)
            log("✅ TEST EXITOSO: ETL limpia staging correctamente")
            log("="*80)
            return 0
        else:
            log("\n" + "="*80)
            log("❌ TEST FALLIDO")
            log("="*80)
            return 1

    except Exception as e:
        log(f"❌ Error fatal: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if driver:
            log("\n🔚 Cerrando navegador...")
            driver.quit()

if __name__ == "__main__":
    sys.exit(main())
