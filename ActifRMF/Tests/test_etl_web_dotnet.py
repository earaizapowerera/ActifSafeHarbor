#!/usr/bin/env python3
"""
Test Selenium - ETL .NET desde interfaz web
Verifica que el sistema web ejecute el ETL .NET correctamente
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

def test_etl_web_execution(driver):
    """Prueba ejecución del ETL .NET desde la web"""
    log("\n=== TEST: Ejecución ETL .NET desde Web ===")

    try:
        driver.get(f"{BASE_URL}/extraccion.html")
        time.sleep(2)

        # Seleccionar compañía
        select = Select(driver.find_element(By.ID, "companiaSelect"))
        select.select_by_value(str(COMPANY_ID))
        log(f"✅ Compañía {COMPANY_ID} seleccionada")

        # Ingresar año
        year_input = driver.find_element(By.ID, "anioCalculo")
        year_input.clear()
        year_input.send_keys(str(YEAR))
        log(f"✅ Año {YEAR} ingresado")

        # Ejecutar ETL
        btn = driver.find_element(By.ID, "btnEjecutar")
        driver.execute_script("arguments[0].click();", btn)
        log("⏳ ETL iniciado, esperando resultado...")

        # Esperar resultado (hasta 120 segundos para el ETL .NET)
        result_div = WebDriverWait(driver, 120).until(
            EC.presence_of_element_located((By.ID, "resultadoDiv"))
        )

        time.sleep(3)
        result_content = driver.find_element(By.ID, "resultadoContent")
        result_text = result_content.text

        log(f"\n📄 Resultado recibido ({len(result_text)} caracteres)")

        # Verificar mensaje de éxito
        if "exitosamente" in result_text.lower() or "completado" in result_text.lower():
            log("✅ ETL completado exitosamente")

            # Buscar información del ETL .NET en el resultado
            if "ETL .NET" in result_text or "dotnet" in result_text:
                log("✅ ETL .NET ejecutado correctamente")
            else:
                log("⚠️  No se detectó mensaje de ETL .NET")

            # Buscar registros importados
            import re
            match = re.search(r'(\d+)\s+registros?\s+importados?', result_text, re.IGNORECASE)
            if match:
                registros = int(match.group(1))
                log(f"✅ Registros importados: {registros}")

                if registros == 0:
                    log("❌ FALLO: 0 registros importados")
                    return False
            else:
                log("⚠️  No se pudo determinar número de registros")

            # Verificar que NO diga "query" o "SELECT" (indicaría que usó el sistema viejo)
            if "SELECT" in result_text or "FROM activo" in result_text:
                log("❌ FALLO: Parece que usó queries SQL en lugar de ETL .NET")
                return False

            log("✅ TEST EXITOSO")
            return True

        else:
            log(f"❌ FALLO: ETL no completó. Mensaje: {result_text[:200]}")
            return False

    except Exception as e:
        log(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    log("🚀 Iniciando test de ETL .NET desde interfaz web")
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

        if test_etl_web_execution(driver):
            log("\n" + "="*80)
            log("✅ TEST EXITOSO: ETL .NET funciona desde la web")
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
