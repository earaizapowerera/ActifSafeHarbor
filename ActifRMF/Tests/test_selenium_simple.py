#!/usr/bin/env python3
"""Test Selenium simple - Verificar interfaz web ActifRMF"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import sys

BASE_URL = "http://localhost:5071"

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def test_dashboard_loads(driver):
    """Test 1: Dashboard carga"""
    log("\n=== TEST 1: Dashboard ===")
    try:
        driver.get(f"{BASE_URL}/index.html")
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.TAG_NAME, "h1"))
        )
        title = driver.find_element(By.TAG_NAME, "h1").text
        log(f"✅ Dashboard cargado: {title}")
        return True
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def test_companias_page(driver):
    """Test 2: Página de compañías"""
    log("\n=== TEST 2: Compañías ===")
    try:
        driver.get(f"{BASE_URL}/companias.html")

        # Esperar a que la tabla se cargue dinámicamente
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.TAG_NAME, "tbody"))
        )
        time.sleep(2)

        # Verificar que hay filas en tbody
        tbody = driver.find_element(By.TAG_NAME, "tbody")
        rows = tbody.find_elements(By.TAG_NAME, "tr")
        log(f"✅ Tabla cargada con {len(rows)} compañías")
        return len(rows) > 0
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def test_extraccion_page(driver):
    """Test 3: Página de extracción"""
    log("\n=== TEST 3: Extracción ETL ===")
    try:
        driver.get(f"{BASE_URL}/extraccion.html")
        time.sleep(2)

        # Verificar select de compañías
        select = driver.find_element(By.ID, "companiaSelect")
        options = select.find_elements(By.TAG_NAME, "option")
        log(f"✅ Select con {len(options)} compañías")

        # Verificar input de año
        year_input = driver.find_element(By.ID, "anioCalculo")
        log(f"✅ Input de año presente")

        # Verificar botón ejecutar
        btn = driver.find_element(By.ID, "btnEjecutar")
        log(f"✅ Botón ejecutar presente")

        return True
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def test_calculo_page(driver):
    """Test 4: Página de cálculo"""
    log("\n=== TEST 4: Cálculo RMF ===")
    try:
        driver.get(f"{BASE_URL}/calculo.html")
        time.sleep(2)

        # Verificar elementos básicos
        h1 = driver.find_element(By.TAG_NAME, "h1").text
        log(f"✅ Página cargada: {h1}")
        return True
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def test_reporte_page(driver):
    """Test 5: Página de reporte"""
    log("\n=== TEST 5: Reporte ===")
    try:
        driver.get(f"{BASE_URL}/reporte.html")
        time.sleep(2)

        h1 = driver.find_element(By.TAG_NAME, "h1").text
        log(f"✅ Página cargada: {h1}")
        return True
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def test_inpc_page(driver):
    """Test 6: Página de INPC"""
    log("\n=== TEST 6: INPC ===")
    try:
        driver.get(f"{BASE_URL}/inpc.html")
        time.sleep(2)

        h1 = driver.find_element(By.TAG_NAME, "h1").text
        log(f"✅ Página cargada: {h1}")
        return True
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def main():
    log("🚀 Iniciando pruebas simples de Selenium")
    log(f"🌐 URL: {BASE_URL}")

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

        tests = [
            ("Dashboard", test_dashboard_loads),
            ("Compañías", test_companias_page),
            ("Extracción", test_extraccion_page),
            ("Cálculo", test_calculo_page),
            ("Reporte", test_reporte_page),
            ("INPC", test_inpc_page),
        ]

        passed = 0
        for name, test_func in tests:
            if test_func(driver):
                passed += 1

        log("\n" + "="*80)
        log(f"📊 RESUMEN: {passed}/{len(tests)} pruebas exitosas")
        log("="*80)

        if passed == len(tests):
            log("✅ TODAS LAS PRUEBAS PASARON")
            return 0
        else:
            log("⚠️  ALGUNAS PRUEBAS FALLARON")
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
