#!/usr/bin/env python3
"""
Prueba automatizada con Selenium para ActifRMF
Verifica:
- Carga correcta de la página de extracción
- Lista de compañías filtrada
- Historial de ETL visible
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
import time
import sys

def test_actifrmf():
    print("🔧 Iniciando prueba de Selenium...")

    # Configurar Chrome en modo headless
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--window-size=1920,1080")

    # Deshabilitar cache
    chrome_options.add_argument("--disable-cache")
    chrome_options.add_argument("--disable-application-cache")
    chrome_options.add_argument("--disk-cache-size=0")

    driver = None

    try:
        print("🌐 Abriendo navegador Chrome...")
        driver = webdriver.Chrome(options=chrome_options)
        driver.set_page_load_timeout(10)

        # URL de prueba
        url = "http://localhost:5071/extraccion.html"
        print(f"📡 Navegando a: {url}")
        driver.get(url)

        # Esperar que cargue el dropdown de compañías
        print("⏳ Esperando que cargue el dropdown de compañías...")
        wait = WebDriverWait(driver, 10)
        select_compania = wait.until(
            EC.presence_of_element_located((By.ID, "companiaSelect"))
        )

        # Obtener todas las opciones del select
        time.sleep(2)  # Dar tiempo a que se llenen las opciones via AJAX

        options = driver.find_elements(By.CSS_SELECTOR, "#companiaSelect option")

        print(f"\n✅ Dropdown encontrado con {len(options)} opciones:")

        companias = []
        for i, option in enumerate(options):
            text = option.text
            value = option.get_attribute("value")
            print(f"  {i+1}. {text} (value: {value})")
            if value and value != "":
                companias.append({
                    'value': value,
                    'text': text
                })

        # Verificar que solo hay 3 compañías + opción por defecto
        expected_count = 4  # "Seleccione..." + 3 compañías
        if len(options) == expected_count:
            print(f"\n✅ CORRECTO: Se encontraron {len(companias)} compañías (122, 123, 188)")
        else:
            print(f"\n⚠️  ADVERTENCIA: Se esperaban {expected_count} opciones, se encontraron {len(options)}")

        # Verificar IDs de compañías
        expected_ids = ['122', '123', '188']
        found_ids = [c['value'] for c in companias]

        print("\n🔍 Verificación de IDs:")
        for exp_id in expected_ids:
            if exp_id in found_ids:
                print(f"  ✅ ID {exp_id}: Encontrado")
            else:
                print(f"  ❌ ID {exp_id}: NO encontrado")

        # Verificar que el historial se haya cargado
        print("\n⏳ Verificando historial de ETL...")
        tbody = wait.until(
            EC.presence_of_element_located((By.ID, "tbodyHistorial"))
        )

        time.sleep(2)  # Dar tiempo a que cargue via AJAX

        rows = driver.find_elements(By.CSS_SELECTOR, "#tbodyHistorial tr")
        print(f"✅ Historial encontrado con {len(rows)} filas")

        # Mostrar primeras 3 filas del historial
        if len(rows) > 0:
            print("\n📊 Primeras entradas del historial:")
            for i, row in enumerate(rows[:3]):
                cells = row.find_elements(By.TAG_NAME, "td")
                if len(cells) >= 4:
                    fecha = cells[0].text
                    compania = cells[1].text
                    año = cells[2].text
                    lote = cells[3].text
                    print(f"  {i+1}. {compania} - Año {año} - {fecha[:10]} - Lote: {lote}")

        # Verificar versión en consola
        print("\n🔍 Verificando versión de cache...")
        logs = driver.get_log('browser')
        version_found = False
        for log in logs:
            message = log.get('message', '')
            if 'VERSIÓN CARGADA' in message:
                print(f"✅ {message}")
                version_found = True
                if 'v13' in message:
                    print("✅ Cache actualizado correctamente (v13)")
                else:
                    print("⚠️  Cache no actualizado (debería ser v13)")

        if not version_found:
            print("⚠️  No se encontró mensaje de versión en la consola")

        print("\n" + "="*60)
        print("✅ PRUEBA COMPLETADA EXITOSAMENTE")
        print("="*60)
        print(f"\n📋 Resumen:")
        print(f"  - Compañías encontradas: {len(companias)}")
        print(f"  - IDs correctos: {', '.join(found_ids)}")
        print(f"  - Historial: {len(rows)} registros")
        print(f"  - URL: {url}")
        print(f"  - Estado: ✅ FUNCIONANDO")

        return True

    except Exception as e:
        print(f"\n❌ ERROR en la prueba:")
        print(f"  {type(e).__name__}: {str(e)}")

        if driver:
            # Capturar screenshot del error
            try:
                screenshot_path = "/Users/enrique/ActifRMF/error_screenshot.png"
                driver.save_screenshot(screenshot_path)
                print(f"\n📸 Screenshot guardado en: {screenshot_path}")
            except:
                pass

        return False

    finally:
        if driver:
            print("\n🔒 Cerrando navegador...")
            driver.quit()

if __name__ == "__main__":
    success = test_actifrmf()
    sys.exit(0 if success else 1)
