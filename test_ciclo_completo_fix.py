#!/usr/bin/env python3
"""
Test Ciclo Completo: Cálculo + Reporte
Verifica que no haya valores negativos después del fix USD/MXN
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
    print("=" * 80)
    print("TEST CICLO COMPLETO: CÁLCULO + REPORTE")
    print("=" * 80)

    # =========================================================================
    # PARTE 1: EJECUTAR CÁLCULO PARA TODAS LAS COMPAÑÍAS
    # =========================================================================

    print("\n### PARTE 1: EJECUTAR CÁLCULO ###")
    print("-" * 80)

    driver.get("http://localhost:5071/calculo.html")
    time.sleep(2)

    # Seleccionar año 2024
    print("\n1. Seleccionando año 2024...")
    year_select = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "añoSelect"))
    )
    select = Select(year_select)
    select.select_by_value('2024')
    time.sleep(2)

    # Seleccionar todas las compañías
    print("2. Seleccionando todas las compañías...")
    select_all = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "selectAll"))
    )
    select_all.click()
    time.sleep(1)

    # Ejecutar cálculo
    print("3. Ejecutando cálculo...")
    btn_calcular = driver.find_element(By.ID, "btnCalcular")
    btn_calcular.click()

    # Esperar a que termine el cálculo (máximo 60 segundos)
    print("4. Esperando que termine el cálculo...")
    time.sleep(5)

    wait_attempts = 0
    max_wait = 60
    while wait_attempts < max_wait:
        try:
            resultado = driver.find_element(By.ID, "resultadoCalculo")
            if "exitoso" in resultado.text.lower() or "completado" in resultado.text.lower():
                print(f"   ✓ Cálculo completado en ~{wait_attempts} segundos")
                break
        except:
            pass
        time.sleep(1)
        wait_attempts += 1

    if wait_attempts >= max_wait:
        print(f"   ⚠ Timeout esperando resultado del cálculo")

    # =========================================================================
    # PARTE 2: VERIFICAR REPORTE - NO DEBE HABER NEGATIVOS
    # =========================================================================

    print("\n### PARTE 2: VERIFICAR REPORTE ###")
    print("-" * 80)

    driver.get("http://localhost:5071/reporte.html")
    time.sleep(2)

    # Seleccionar año 2024
    print("\n1. Cargando reporte para año 2024...")
    year_select = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "añoSelect"))
    )
    select = Select(year_select)
    select.select_by_value('2024')
    time.sleep(2)

    # Seleccionar todas las compañías
    print("2. Seleccionando todas las compañías...")
    select_all = WebDriverWait(driver, 10).until(
        EC.presence_of_element_located((By.ID, "selectAll"))
    )
    select_all.click()
    time.sleep(1)

    # Cargar reporte
    print("3. Cargando reporte...")
    btn_cargar = driver.find_element(By.ID, "btnCargarReporte")
    btn_cargar.click()
    time.sleep(5)

    # Verificar contador de registros
    print("\n4. Verificando contador de registros...")
    contador = driver.find_element(By.ID, "contadorRegistros")
    print(f"   Contador: {contador.text}")

    # =========================================================================
    # PARTE 3: BUSCAR VALORES NEGATIVOS EN EL GRID
    # =========================================================================

    print("\n### PARTE 3: BUSCAR VALORES NEGATIVOS ###")
    print("-" * 80)

    # Verificar grid de Activos Extranjeros
    print("\n1. Verificando Activos Extranjeros...")
    grid_ext = driver.find_element(By.ID, "gridExtranjeros")

    # Buscar celdas con valores negativos (contienen paréntesis o signo negativo)
    time.sleep(2)
    all_cells = grid_ext.find_elements(By.CSS_SELECTOR, ".ag-cell")

    negativos_encontrados = []
    for cell in all_cells:
        text = cell.text.strip()
        # Buscar valores con paréntesis (formato contable negativo) o con signo -
        if text and (('(' in text and ')' in text) or text.startswith('-$')):
            # Verificar que no sea el header
            if '$' in text:
                negativos_encontrados.append(text)

    if len(negativos_encontrados) > 0:
        print(f"   ✗ ERROR: Encontrados {len(negativos_encontrados)} valores negativos:")
        for val in negativos_encontrados[:5]:  # Mostrar primeros 5
            print(f"      • {val}")
    else:
        print(f"   ✓ No se encontraron valores negativos en Activos Extranjeros")

    # =========================================================================
    # PARTE 4: VERIFICAR FOLIO 45308 ESPECÍFICAMENTE
    # =========================================================================

    print("\n### PARTE 4: VERIFICAR FOLIO 45308 (Caso problemático) ###")
    print("-" * 80)

    # Buscar el folio 45308 en el grid
    print("\n1. Buscando Folio 45308...")
    folio_cells = grid_ext.find_elements(By.CSS_SELECTOR, ".ag-cell")

    found_45308 = False
    for i, cell in enumerate(folio_cells):
        if '45308' in cell.text:
            found_45308 = True
            print(f"   ✓ Folio 45308 encontrado")

            # Obtener las celdas de la misma fila
            try:
                # Las siguientes 5-10 celdas deberían contener los valores
                row_cells = folio_cells[i:i+15]
                row_values = [c.text for c in row_cells if c.text.strip()]
                print(f"   Valores de la fila:")
                for j, val in enumerate(row_values[:10]):
                    print(f"      [{j}] {val}")

                # Verificar que no haya valores negativos en esta fila
                negativos_fila = [v for v in row_values if ('(' in v and ')' in v and '$' in v) or v.startswith('-$')]
                if len(negativos_fila) > 0:
                    print(f"   ✗ ERROR: Folio 45308 tiene valores negativos: {negativos_fila}")
                else:
                    print(f"   ✓ Folio 45308 no tiene valores negativos")

            except Exception as e:
                print(f"   ⚠ Error leyendo valores de fila: {e}")
            break

    if not found_45308:
        print(f"   ⚠ Folio 45308 no encontrado en el grid")

    # =========================================================================
    # RESULTADO FINAL
    # =========================================================================

    print("\n" + "=" * 80)
    print("RESULTADO FINAL")
    print("=" * 80)

    if len(negativos_encontrados) == 0:
        print("✓ TEST EXITOSO: No se encontraron valores negativos")
        print("✓ El fix USD/MXN funciona correctamente")
    else:
        print(f"✗ TEST FALLIDO: Se encontraron {len(negativos_encontrados)} valores negativos")
        print("✗ El bug USD/MXN persiste")

    print("=" * 80)

except Exception as e:
    print(f"\n✗ ERROR EN TEST: {e}")
    import traceback
    traceback.print_exc()

    # Captura de pantalla
    driver.save_screenshot('/tmp/test_ciclo_completo_error.png')
    print("\n📸 Screenshot guardado en /tmp/test_ciclo_completo_error.png")
finally:
    driver.quit()
