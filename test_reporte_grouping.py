#!/usr/bin/env python3
"""
Test para verificar que el grouping por compañía funcione correctamente
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
    print("TEST: Verificar grouping por compañía en reporte")
    print("=" * 60)

    # 1. Cargar página reporte.html
    print("\n1. Cargando página reporte.html...")
    driver.get("http://localhost:5071/reporte.html")
    time.sleep(2)

    # 2. Seleccionar año 2024
    print("\n2. Seleccionando año 2024...")
    year_select = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "añoSelect"))
    )
    select = Select(year_select)
    select.select_by_value('2024')
    time.sleep(2)

    # 3. Seleccionar todas las compañías
    print("\n3. Seleccionando todas las compañías...")
    select_all = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "selectAll"))
    )
    select_all.click()
    time.sleep(1)

    # 4. Hacer clic en Cargar
    print("\n4. Cargando reporte...")
    btn_cargar = driver.find_element(By.ID, "btnCargarReporte")
    btn_cargar.click()
    time.sleep(5)  # Dar tiempo para cargar datos

    # 5. Verificar grid de Activos Extranjeros
    print("\n5. Verificando grid de Activos Extranjeros...")
    grid_ext = driver.find_element(By.ID, "gridExtranjeros")

    # Buscar filas de grupo (group rows) en el grid
    # AG-Grid usa la clase 'ag-row-group' para las filas de grupo
    time.sleep(2)
    group_rows = grid_ext.find_elements(By.CSS_SELECTOR, ".ag-row-group")

    if len(group_rows) > 0:
        print(f"   ✓ Encontradas {len(group_rows)} filas de grupo")

        # Verificar que tengan contenido
        for i, row in enumerate(group_rows[:3]):  # Solo primeras 3
            text = row.text
            print(f"   Grupo {i+1}: {text[:100]}")  # Primeros 100 caracteres
    else:
        # Intentar buscar celdas de grupo
        group_cells = grid_ext.find_elements(By.CSS_SELECTOR, ".ag-group-value")
        if len(group_cells) > 0:
            print(f"   ✓ Encontradas {len(group_cells)} celdas de grupo")
            for i, cell in enumerate(group_cells[:3]):
                print(f"   Grupo {i+1}: {cell.text}")
        else:
            print("   ⚠ No se encontraron filas de grupo")
            # Mostrar estructura del grid para debugging
            print("   Estructura del grid:")
            rows = grid_ext.find_elements(By.CSS_SELECTOR, ".ag-row")
            print(f"   Total de filas: {len(rows)}")
            if len(rows) > 0:
                first_row_html = rows[0].get_attribute('outerHTML')
                print(f"   Primera fila HTML: {first_row_html[:200]}")

    # 6. Verificar grid de Activos Nacionales
    print("\n6. Verificando grid de Activos Nacionales...")
    grid_nac = driver.find_element(By.ID, "gridNacionales")

    group_rows_nac = grid_nac.find_elements(By.CSS_SELECTOR, ".ag-row-group")
    if len(group_rows_nac) > 0:
        print(f"   ✓ Encontradas {len(group_rows_nac)} filas de grupo")
        for i, row in enumerate(group_rows_nac[:3]):
            text = row.text
            print(f"   Grupo {i+1}: {text[:100]}")
    else:
        group_cells_nac = grid_nac.find_elements(By.CSS_SELECTOR, ".ag-group-value")
        if len(group_cells_nac) > 0:
            print(f"   ✓ Encontradas {len(group_cells_nac)} celdas de grupo")
            for i, cell in enumerate(group_cells_nac[:3]):
                print(f"   Grupo {i+1}: {cell.text}")
        else:
            print("   ⚠ No se encontraron filas de grupo")

    # 7. Verificar contador de registros
    print("\n7. Verificando contador de registros...")
    contador = driver.find_element(By.ID, "contadorRegistros")
    print(f"   Contador: {contador.text}")

    print("\n" + "=" * 60)
    print("TEST COMPLETADO")
    print("=" * 60)

except Exception as e:
    print(f"\n✗ ERROR: {e}")
    import traceback
    traceback.print_exc()

    # Captura de pantalla para debugging
    driver.save_screenshot('/tmp/reporte_grouping_error.png')
    print("\n📸 Screenshot guardado en /tmp/reporte_grouping_error.png")
finally:
    driver.quit()
