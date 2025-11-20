#!/usr/bin/env python3
"""
Script de prueba con Selenium para la página de Reporte de Safe Harbor
Verifica la columna "Fecha Fin Depreciación" en el reporte de 2025
"""

import os
import time
import glob
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options

# Configuración
BASE_URL = "http://localhost:5071"
DOWNLOAD_DIR = os.path.expanduser("~/Downloads")
TEST_COMPANIA = 12  # Piedras Negras
TEST_AÑO = 2025

def setup_driver():
    """Configura el driver de Chrome con opciones para descarga automática"""
    chrome_options = Options()

    # Configurar directorio de descargas
    prefs = {
        "download.default_directory": DOWNLOAD_DIR,
        "download.prompt_for_download": False,
        "download.directory_upgrade": True,
        "safebrowsing.enabled": True
    }
    chrome_options.add_experimental_option("prefs", prefs)

    # Opcional: descomentar para ver el navegador en acción
    # chrome_options.add_argument("--headless")  # Ejecutar sin interfaz gráfica

    driver = webdriver.Chrome(options=chrome_options)
    driver.maximize_window()
    return driver

def test_columnas_fecha_depreciacion():
    """Prueba que verifica la columna Fecha Fin Depreciación en el reporte de 2025"""
    driver = setup_driver()

    try:
        print("=" * 80)
        print("PRUEBA: Verificación de Columna 'Fecha Fin Depreciación'")
        print(f"Compañía: {TEST_COMPANIA} (Piedras Negras)")
        print(f"Año: {TEST_AÑO}")
        print("=" * 80)

        # 1. Navegar a la página del reporte
        url = f"{BASE_URL}/reporte.html"
        print(f"\n[1/6] Navegando a: {url}")
        driver.get(url)

        # 2. Esperar a que cargue la página y las compañías
        print("[2/6] Esperando carga de página y compañías...")
        wait = WebDriverWait(driver, 20)

        # Esperar al título
        titulo = wait.until(EC.presence_of_element_located((By.TAG_NAME, "h1")))
        print(f"   ✓ Título: {titulo.text}")

        # Esperar a que aparezcan los checkboxes de compañías
        wait.until(EC.presence_of_element_located((By.CLASS_NAME, "compania-check")))
        time.sleep(1)

        # 3. Seleccionar la compañía Piedras Negras (ID 12)
        print(f"\n[3/6] Seleccionando compañía {TEST_COMPANIA}...")
        checkbox = driver.find_element(By.ID, f"compania_{TEST_COMPANIA}")
        if not checkbox.is_selected():
            checkbox.click()
            print(f"   ✓ Compañía {TEST_COMPANIA} seleccionada")

        # 4. Seleccionar el año 2025
        print(f"\n[4/6] Seleccionando año {TEST_AÑO}...")
        año_select = Select(driver.find_element(By.ID, "añoSelect"))
        año_select.select_by_value(str(TEST_AÑO))
        print(f"   ✓ Año {TEST_AÑO} seleccionado")

        # 5. Hacer clic en el botón "Cargar Reporte"
        print("\n[5/6] Cargando reporte...")
        btn_cargar = driver.find_element(By.ID, "btnCargarReporte")
        btn_cargar.click()

        # Esperar a que se carguen los datos
        time.sleep(3)
        wait.until(EC.text_to_be_present_in_element((By.ID, "btnCargarReporte"), "Cargar"))
        time.sleep(2)

        print("   ✓ Datos cargados")

        # Contador de errores
        errores = []

        # 6. Verificar grid de Nacionales
        print("\n[6/6] Verificando Grids...")
        print("\n📊 Grid de Nacionales:")
        try:
            headers_nac = driver.find_elements(By.CSS_SELECTOR, "#gridNacionales .ag-header-cell-text")
            header_texts_nac = [h.text for h in headers_nac if h.text]

            print(f"   📋 Columnas encontradas: {len(header_texts_nac)}")
            print("   📝 Lista completa de columnas:")
            for i, col in enumerate(header_texts_nac, 1):
                print(f"      {i}. {col}")

            # Buscar columnas específicas
            columnas_fecha = [
                "Fecha Adquisición",
                "Fecha Inicio Depreciación",
                "Fecha Fin Depreciación",
                "Fecha Baja"
            ]

            for col in columnas_fecha:
                if col in header_texts_nac:
                    print(f"   ✅ '{col}'")
                else:
                    msg = f"Columna '{col}' NO encontrada en grid Nacionales"
                    print(f"   ❌ {msg}")
                    errores.append(msg)

            # Contar filas
            rows_nac = driver.find_elements(By.CSS_SELECTOR, "#gridNacionales .ag-row")
            print(f"   📊 Filas visibles: {len(rows_nac)}")

        except Exception as e:
            msg = f"Error al verificar grid Nacionales: {str(e)}"
            print(f"   ❌ {msg}")
            errores.append(msg)

        # Verificar grid de Extranjeros
        print("\n📊 Grid de Extranjeros:")
        try:
            headers_ext = driver.find_elements(By.CSS_SELECTOR, "#gridExtranjeros .ag-header-cell-text")
            header_texts_ext = [h.text for h in headers_ext if h.text]

            print(f"   📋 Columnas encontradas: {len(header_texts_ext)}")

            for col in columnas_fecha:
                if col in header_texts_ext:
                    print(f"   ✅ '{col}'")
                else:
                    msg = f"Columna '{col}' NO encontrada en grid Extranjeros"
                    print(f"   ❌ {msg}")
                    errores.append(msg)

            # Contar filas
            rows_ext = driver.find_elements(By.CSS_SELECTOR, "#gridExtranjeros .ag-row")
            print(f"   📊 Filas visibles: {len(rows_ext)}")

        except Exception as e:
            msg = f"Error al verificar grid Extranjeros: {str(e)}"
            print(f"   ❌ {msg}")
            errores.append(msg)

        # 5. Tomar screenshot
        screenshot_path = f"{DOWNLOAD_DIR}/reporte_2025_screenshot.png"
        driver.save_screenshot(screenshot_path)
        print(f"\n📸 Screenshot guardado: {screenshot_path}")

        # Resultado
        print("\n" + "=" * 80)
        if len(errores) == 0:
            print("✅ PRUEBA EXITOSA")
            print("Todas las columnas de fecha se encuentran en ambos grids")
            return True
        else:
            print("❌ PRUEBA FALLIDA")
            print(f"Se encontraron {len(errores)} errores:")
            for err in errores:
                print(f"   - {err}")
            return False

    except Exception as e:
        print(f"\n❌ ERROR CRÍTICO: {e}")
        import traceback
        traceback.print_exc()

        # Screenshot de error
        try:
            screenshot_path = f"{DOWNLOAD_DIR}/reporte_2025_error.png"
            driver.save_screenshot(screenshot_path)
            print(f"📸 Screenshot de error: {screenshot_path}")
        except:
            pass

        return False

    finally:
        print("\n🔒 Cerrando navegador...")
        time.sleep(2)
        driver.quit()
        print("✓ Navegador cerrado")

if __name__ == "__main__":
    success = test_columnas_fecha_depreciacion()
    exit(0 if success else 1)
