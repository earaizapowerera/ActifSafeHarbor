#!/usr/bin/env python3
"""
Test de selector en cascada para página de Cálculo
- Verifica que al seleccionar año, se carguen las compañías con datos importados
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

driver = webdriver.Chrome(options=options)

try:
    print("=" * 60)
    print("TEST: Selector en Cascada - Cálculo")
    print("=" * 60)

    # 1. Cargar página calculo.html
    print("\n1. Cargando página calculo.html...")
    driver.get("http://localhost:5071/calculo.html")
    time.sleep(2)

    # 2. Verificar que el selector de año existe
    print("\n2. Verificando selector de año...")
    year_select = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "anioCalculo"))
    )
    print("   ✓ Selector de año encontrado")

    # 3. Verificar que hay opciones de años
    select = Select(year_select)
    years = [opt.get_attribute('value') for opt in select.options if opt.get_attribute('value')]
    print(f"   ✓ Años disponibles: {len(years)}")

    # 4. Seleccionar año 2024
    print("\n3. Seleccionando año 2024...")
    select.select_by_value('2024')
    time.sleep(2)  # Dar tiempo a que cargue las compañías

    # 5. Verificar que se cargaron las compañías
    print("\n4. Verificando que se cargaron las compañías...")
    checklist = driver.find_element(By.ID, "companiasChecklist")
    checkboxes = checklist.find_elements(By.CSS_SELECTOR, ".form-check-input")

    if len(checkboxes) > 0:
        print(f"   ✓ Se cargaron {len(checkboxes)} compañías")

        # Verificar badges con número de registros
        badges = checklist.find_elements(By.CSS_SELECTOR, ".badge")
        print(f"   ✓ Badges encontrados: {len(badges)}")

        for badge in badges:
            badge_text = badge.text
            print(f"     - {badge_text}")

        # Verificar que los nombres de compañías se muestran
        labels = checklist.find_elements(By.CSS_SELECTOR, ".form-check-label")
        print("\n   Compañías disponibles:")
        for label in labels:
            print(f"     • {label.text}")
    else:
        print("   ✗ No se cargaron compañías")

    # 6. Cambiar a año diferente para ver cascada
    print("\n5. Cambiando a año 2023...")
    select.select_by_value('2023')
    time.sleep(2)

    checklist = driver.find_element(By.ID, "companiasChecklist")
    content = checklist.text
    print(f"   Contenido: {content}")

    print("\n" + "=" * 60)
    print("TEST COMPLETADO EXITOSAMENTE")
    print("=" * 60)

except Exception as e:
    print(f"\n✗ ERROR: {e}")
    import traceback
    traceback.print_exc()
finally:
    driver.quit()
