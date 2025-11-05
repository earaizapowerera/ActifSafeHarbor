#!/usr/bin/env python3
"""
Test automatizado para verificar la funcionalidad multi-compañía en ActifRMF
"""

import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

BASE_URL = "http://localhost:5071"

def test_calculo_page():
    """Prueba la página de Cálculo RMF"""
    print("\n=== TEST: Página de Cálculo RMF ===")

    driver = webdriver.Chrome()

    try:
        # Navegar a la página
        print(f"1. Navegando a {BASE_URL}/calculo.html")
        driver.get(f"{BASE_URL}/calculo.html")
        time.sleep(2)

        # Verificar que el badge CHECKLIST v2 esté presente
        print("2. Verificando badge 'CHECKLIST v2'...")
        badge = driver.find_element(By.XPATH, "//span[contains(@class, 'badge') and contains(text(), 'CHECKLIST v2')]")
        assert badge.is_displayed(), "Badge CHECKLIST v2 no visible"
        print("   ✓ Badge encontrado")

        # Esperar a que carguen las compañías
        print("3. Esperando carga de compañías...")
        try:
            WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.XPATH, "//input[@type='checkbox'][@class='form-check-input']"))
            )
            print("   ✓ Compañías cargadas")
        except TimeoutException:
            error_msg = driver.find_element(By.ID, "companiasChecklist").text
            if "No se pudo conectar a la base de datos" in error_msg:
                print(f"   ⚠ Error de conexión detectado: {error_msg}")
                return False
            else:
                print(f"   ✗ Error inesperado: {error_msg}")
                return False

        # Contar checkboxes disponibles
        checkboxes = driver.find_elements(By.XPATH, "//input[@type='checkbox'][@class='form-check-input']")
        print(f"4. Checkboxes encontrados: {len(checkboxes)}")
        assert len(checkboxes) > 0, "No se encontraron checkboxes"

        # Verificar que los checkboxes estén habilitados (no disabled)
        disabled_count = 0
        for cb in checkboxes:
            if not cb.is_enabled():
                disabled_count += 1

        if disabled_count > 0:
            print(f"   ✗ {disabled_count} checkboxes deshabilitados")
            return False
        else:
            print(f"   ✓ Todos los checkboxes están habilitados")

        # Seleccionar primeras 2 compañías
        print("5. Seleccionando primeras 2 compañías...")
        for i in range(min(2, len(checkboxes))):
            driver.execute_script("arguments[0].click();", checkboxes[i])
            time.sleep(0.5)

        selected = driver.find_elements(By.XPATH, "//input[@type='checkbox'][@class='form-check-input']:checked")
        print(f"   ✓ {len(selected)} compañías seleccionadas")

        # Verificar que el botón "Ejecutar Cálculo" esté presente y habilitado
        print("6. Verificando botón 'Ejecutar Cálculo'...")
        btn_ejecutar = driver.find_element(By.ID, "btnEjecutar")
        assert btn_ejecutar.is_enabled(), "Botón ejecutar deshabilitado"
        print("   ✓ Botón habilitado")

        # Obtener nombres de compañías seleccionadas
        selected_names = []
        for cb in selected:
            label = driver.find_element(By.XPATH, f"//label[@for='{cb.get_attribute('id')}']")
            selected_names.append(label.text)

        print(f"7. Compañías a procesar: {selected_names}")

        # Click en ejecutar (esto mostrará el confirm dialog)
        print("8. Haciendo click en 'Ejecutar Cálculo'...")
        btn_ejecutar.click()
        time.sleep(1)

        # Verificar que apareció el confirm (usualmente aparece como alert)
        try:
            alert = driver.switch_to.alert
            alert_text = alert.text
            print(f"   ✓ Confirmación mostrada: {alert_text[:100]}...")

            # Verificar que el texto incluye las compañías
            for name in selected_names:
                company_name_short = name.split('(')[0].strip()
                if company_name_short not in alert_text:
                    print(f"   ⚠ Compañía '{company_name_short}' no aparece en confirmación")

            # Cancelar para no ejecutar realmente
            print("9. Cancelando ejecución (no ejecutar realmente)...")
            alert.dismiss()
            time.sleep(1)
            print("   ✓ Test completado sin ejecutar cálculo")

        except:
            print("   ⚠ No se detectó diálogo de confirmación")

        print("\n✅ TEST EXITOSO: Página de Cálculo funcionando correctamente")
        return True

    except Exception as e:
        print(f"\n❌ TEST FALLIDO: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        driver.quit()


def test_extraccion_page():
    """Prueba la página de Extracción ETL"""
    print("\n=== TEST: Página de Extracción ETL ===")

    driver = webdriver.Chrome()

    try:
        # Navegar a la página
        print(f"1. Navegando a {BASE_URL}/extraccion.html")
        driver.get(f"{BASE_URL}/extraccion.html")
        time.sleep(2)

        # Verificar que el badge CHECKLIST v2 esté presente
        print("2. Verificando badge 'CHECKLIST v2'...")
        badge = driver.find_element(By.XPATH, "//span[contains(@class, 'badge') and contains(text(), 'CHECKLIST v2')]")
        assert badge.is_displayed(), "Badge CHECKLIST v2 no visible"
        print("   ✓ Badge encontrado")

        # Esperar a que carguen las compañías
        print("3. Esperando carga de compañías...")
        try:
            WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.XPATH, "//input[@type='checkbox'][@class='form-check-input']"))
            )
            print("   ✓ Compañías cargadas")
        except TimeoutException:
            error_msg = driver.find_element(By.ID, "companiasChecklist").text
            if "No se pudo conectar a la base de datos" in error_msg:
                print(f"   ⚠ Error de conexión detectado: {error_msg}")
                return False
            else:
                print(f"   ✗ Error inesperado: {error_msg}")
                return False

        # Contar checkboxes disponibles
        checkboxes = driver.find_elements(By.XPATH, "//input[@type='checkbox'][@class='form-check-input']")
        print(f"4. Checkboxes encontrados: {len(checkboxes)}")
        assert len(checkboxes) > 0, "No se encontraron checkboxes"

        # Verificar que los checkboxes estén habilitados
        disabled_count = 0
        for cb in checkboxes:
            if not cb.is_enabled():
                disabled_count += 1

        if disabled_count > 0:
            print(f"   ✗ {disabled_count} checkboxes deshabilitados")
            return False
        else:
            print(f"   ✓ Todos los checkboxes están habilitados")

        print("\n✅ TEST EXITOSO: Página de Extracción funcionando correctamente")
        return True

    except Exception as e:
        print(f"\n❌ TEST FALLIDO: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        driver.quit()


def main():
    print("=" * 60)
    print("PRUEBAS AUTOMATIZADAS - ActifRMF Multi-Compañía")
    print("=" * 60)

    # Verificar que el servidor esté corriendo
    print(f"\nVerificando que el servidor esté corriendo en {BASE_URL}...")
    import requests
    try:
        response = requests.get(BASE_URL, timeout=5)
        print("✓ Servidor respondiendo")
    except Exception as e:
        print(f"✗ No se pudo conectar al servidor: {e}")
        print("Por favor, asegúrate de que el servidor esté corriendo con 'dotnet run'")
        return

    # Ejecutar pruebas
    resultados = []

    resultados.append(("Extracción ETL", test_extraccion_page()))
    resultados.append(("Cálculo RMF", test_calculo_page()))

    # Resumen
    print("\n" + "=" * 60)
    print("RESUMEN DE PRUEBAS")
    print("=" * 60)

    exitosas = 0
    fallidas = 0

    for nombre, resultado in resultados:
        estado = "✅ EXITOSO" if resultado else "❌ FALLIDO"
        print(f"{nombre}: {estado}")
        if resultado:
            exitosas += 1
        else:
            fallidas += 1

    print(f"\nTotal: {exitosas} exitosas, {fallidas} fallidas")

    if fallidas == 0:
        print("\n🎉 ¡TODAS LAS PRUEBAS PASARON!")
    else:
        print(f"\n⚠️ {fallidas} prueba(s) fallaron")


if __name__ == "__main__":
    main()
