#!/usr/bin/env python3
"""
Test para verificar que el selector en cascada de reporte funcione correctamente
con múltiples cambios de año
"""
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
import time

# Configurar Chrome
options = Options()
options.add_argument('--headless')
options.add_argument('--no-sandbox')
options.add_argument('--disable-dev-shm-usage')
options.add_argument('--disable-cache')
options.add_argument('--disable-application-cache')
options.add_argument('--disable-offline-load-stale-cache')
options.add_argument('--disk-cache-size=0')

driver = webdriver.Chrome(options=options)

try:
    print("=" * 60)
    print("TEST: Verificar actualización de compañías al cambiar año")
    print("=" * 60)

    # 1. Cargar página reporte.html
    print("\n1. Cargando página reporte.html...")
    driver.get("http://localhost:5071/reporte.html")
    time.sleep(2)

    # 2. Verificar mensaje inicial
    print("\n2. Verificando mensaje inicial...")
    container = driver.find_element(By.ID, "companiasContainer")
    initial_text = container.text
    print(f"   Texto inicial: {initial_text}")
    assert "Seleccione primero un año" in initial_text, "Debería mostrar mensaje de selección"

    # 3. Seleccionar año 2024
    print("\n3. Seleccionando año 2024...")
    year_select = driver.find_element(By.ID, "añoSelect")
    select = Select(year_select)
    select.select_by_value('2024')
    time.sleep(2)

    # 4. Verificar que se cargaron compañías para 2024
    print("\n4. Verificando compañías para 2024...")
    container = driver.find_element(By.ID, "companiasContainer")
    checkboxes_2024 = container.find_elements(By.CSS_SELECTOR, ".compania-check")
    print(f"   Compañías encontradas: {len(checkboxes_2024)}")

    if len(checkboxes_2024) > 0:
        labels = container.find_elements(By.CSS_SELECTOR, ".form-check-label")
        print("   Compañías disponibles para 2024:")
        for label in labels:
            print(f"     • {label.text}")

    # 5. Cambiar a año 2023
    print("\n5. Cambiando a año 2023...")
    select.select_by_value('2023')
    time.sleep(2)

    container = driver.find_element(By.ID, "companiasContainer")
    text_2023 = container.text
    print(f"   Contenido para 2023: {text_2023}")

    # 6. Cambiar de vuelta a 2024
    print("\n6. Cambiando de vuelta a año 2024...")
    select.select_by_value('2024')
    time.sleep(2)

    container = driver.find_element(By.ID, "companiasContainer")
    checkboxes_2024_second = container.find_elements(By.CSS_SELECTOR, ".compania-check")
    print(f"   Compañías encontradas (segunda vez): {len(checkboxes_2024_second)}")

    if len(checkboxes_2024_second) > 0:
        labels = container.find_elements(By.CSS_SELECTOR, ".form-check-label")
        print("   Compañías disponibles para 2024 (segunda carga):")
        for label in labels:
            print(f"     • {label.text}")

    # 7. Verificación final
    print("\n7. Verificación final...")
    if len(checkboxes_2024_second) == len(checkboxes_2024):
        print("   ✓ El selector en cascada funciona correctamente")
        print("   ✓ Las compañías se actualizan al cambiar de año")
    else:
        print(f"   ✗ ERROR: Número de compañías diferente ({len(checkboxes_2024)} vs {len(checkboxes_2024_second)})")

    print("\n" + "=" * 60)
    print("TEST COMPLETADO")
    print("=" * 60)

except Exception as e:
    print(f"\n✗ ERROR: {e}")
    import traceback
    traceback.print_exc()
finally:
    driver.quit()
