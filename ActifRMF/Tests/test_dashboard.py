#!/usr/bin/env python3
"""
Test para Dashboard - ActifRMF
Verifica la carga y visualización del dashboard
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import sys

BASE_URL = "http://localhost:5071"

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

def test_dashboard_load(driver):
    """Prueba que el dashboard cargue correctamente"""
    log("\n=== TEST: Carga del Dashboard ===")
    driver.get(f"{BASE_URL}/index.html")

    # Verificar título
    title = wait_for_element(driver, By.TAG_NAME, "h1")
    if title and "Dashboard RMF" in title.text:
        log("✅ Título del dashboard presente")
        return True
    else:
        log("❌ Título del dashboard no encontrado")
        return False

def test_navbar_present(driver):
    """Prueba que el navbar esté presente"""
    log("\n=== TEST: Navbar Presente ===")
    navbar = wait_for_element(driver, By.CLASS_NAME, "navbar")
    if navbar:
        log("✅ Navbar presente")
        return True
    else:
        log("❌ Navbar no encontrado")
        return False

def test_menu_items(driver):
    """Prueba que todos los items del menú estén presentes"""
    log("\n=== TEST: Items del Menú ===")

    menu_items = [
        "Dashboard",
        "Compañías",
        "Extracción ETL",
        "INPC",
        "Cálculo RMF",
        "Reporte"
    ]

    nav_links = driver.find_elements(By.CLASS_NAME, "nav-link")
    link_texts = [link.text.strip() for link in nav_links]

    all_present = True
    for item in menu_items:
        if item in link_texts:
            log(f"✅ Item '{item}' presente")
        else:
            log(f"❌ Item '{item}' NO encontrado")
            all_present = False

    return all_present

def test_dashboard_cards(driver):
    """Prueba que las tarjetas del dashboard estén presentes"""
    log("\n=== TEST: Tarjetas del Dashboard ===")

    cards = driver.find_elements(By.CLASS_NAME, "card")
    if len(cards) > 0:
        log(f"✅ {len(cards)} tarjetas encontradas")
        return True
    else:
        log("❌ No se encontraron tarjetas")
        return False

def main():
    """Función principal"""
    log("🚀 Iniciando pruebas del Dashboard")
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
            test_dashboard_load,
            test_navbar_present,
            test_menu_items,
            test_dashboard_cards
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
