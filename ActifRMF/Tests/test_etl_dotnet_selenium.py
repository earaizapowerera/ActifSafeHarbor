#!/usr/bin/env python3
"""
Test de Selenium para ETL .NET - ActifRMF
Valida que los datos se cargaron correctamente con los nuevos campos
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import sys
import pyodbc

# Configuración
BASE_URL = "http://localhost:5071"
CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=dbdev.powerera.com;"
    "DATABASE=Actif_RMF;"
    "UID=earaiza;"
    "PWD=VgfN-n4ju?H1Z4#JFRE;"
    "TrustServerCertificate=yes;"
)

COMPANIAS_TEST = [188, 122, 1500]

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def verificar_datos_bd(id_compania, año_calculo=2024):
    """Verifica que los datos estén correctos en la BD"""
    log(f"\n=== VERIFICANDO COMPAÑÍA {id_compania} EN BD ===")

    try:
        conn = pyodbc.connect(CONN_STR)
        cursor = conn.cursor()

        # 1. Verificar que existen registros
        cursor.execute("""
            SELECT COUNT(*)
            FROM Staging_Activo
            WHERE ID_Compania = ? AND Año_Calculo = ?
        """, (id_compania, año_calculo))

        total = cursor.fetchone()[0]
        if total == 0:
            log(f"❌ No hay registros para compañía {id_compania}")
            return False

        log(f"✅ Total registros: {total}")

        # 2. Verificar nuevos campos renombrados
        cursor.execute("""
            SELECT
                COUNT(*) as Total,
                COUNT(CASE WHEN ManejaFiscal = 'S' THEN 1 END) as Con_Fiscal,
                COUNT(CASE WHEN ManejaUSGAAP = 'S' THEN 1 END) as Con_USGAAP,
                COUNT(CASE WHEN CostoUSD IS NOT NULL THEN 1 END) as Con_CostoUSD,
                COUNT(CASE WHEN CostoMXN IS NOT NULL THEN 1 END) as Con_CostoMXN
            FROM Staging_Activo
            WHERE ID_Compania = ? AND Año_Calculo = ?
        """, (id_compania, año_calculo))

        row = cursor.fetchone()
        total, fiscal, usgaap, costousd, costomxn = row

        log(f"  - Con ManejaFiscal='S': {fiscal}")
        log(f"  - Con ManejaUSGAAP='S': {usgaap}")
        log(f"  - Con CostoUSD: {costousd}")
        log(f"  - Con CostoMXN: {costomxn}")

        # Validaciones
        if costomxn == 0:
            log("❌ FALLO: Ningún registro tiene CostoMXN")
            return False

        log("✅ Campos nuevos poblados correctamente")

        # 3. Verificar lógica de costos
        cursor.execute("""
            SELECT TOP 5
                ID_NUM_ACTIVO,
                ManejaFiscal,
                ManejaUSGAAP,
                CostoUSD,
                CostoMXN,
                ID_MONEDA
            FROM Staging_Activo
            WHERE ID_Compania = ? AND Año_Calculo = ?
            ORDER BY ID_NUM_ACTIVO
        """, (id_compania, año_calculo))

        log("\n  Muestra de registros:")
        for row in cursor.fetchall():
            id_num, fiscal, usgaap, usd, mxn, moneda = row
            log(f"    ID {id_num}: Fiscal={fiscal}, USGAAP={usgaap}, USD={usd}, MXN={mxn:.2f if mxn else 0}")

        # 4. Verificar tipo de cambio usado
        cursor.execute("""
            SELECT TOP 1
                CostoUSD,
                CostoMXN
            FROM Staging_Activo
            WHERE ID_Compania = ?
              AND Año_Calculo = ?
              AND CostoUSD IS NOT NULL
              AND CostoUSD > 0
              AND CostoMXN IS NOT NULL
              AND CostoMXN > 0
        """, (id_compania, año_calculo))

        row = cursor.fetchone()
        if row:
            usd, mxn = row
            tc_calculado = mxn / usd
            log(f"\n  Tipo de cambio calculado: {tc_calculado:.6f}")

            # Verificar que esté cerca de 18.2478
            if abs(tc_calculado - 18.2478) < 0.01:
                log("✅ Tipo de cambio correcto (30-Jun-2024)")
            else:
                log(f"⚠️  Tipo de cambio inesperado: {tc_calculado:.6f}")

        conn.close()
        log(f"✅ Verificación BD completada para compañía {id_compania}")
        return True

    except Exception as e:
        log(f"❌ Error verificando BD: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_dashboard_carga(driver):
    """Prueba que el dashboard cargue"""
    log("\n=== TEST: Dashboard Carga ===")

    try:
        driver.get(f"{BASE_URL}/index.html")
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((By.TAG_NAME, "h1"))
        )
        log("✅ Dashboard cargado")
        return True
    except:
        log("❌ Error cargando dashboard")
        return False

def test_pagina_companias(driver):
    """Prueba que la página de compañías muestre datos"""
    log("\n=== TEST: Página Compañías ===")

    try:
        driver.get(f"{BASE_URL}/companias.html")
        time.sleep(2)

        # Verificar que haya tabla
        tabla = driver.find_element(By.ID, "companiaTable")
        if tabla:
            log("✅ Tabla de compañías presente")
            return True
        else:
            log("❌ Tabla no encontrada")
            return False
    except Exception as e:
        log(f"❌ Error: {e}")
        return False

def main():
    """Función principal"""
    log("🚀 Iniciando pruebas de Selenium para ETL .NET")
    log(f"🌐 URL Base: {BASE_URL}")

    # Primero verificar datos en BD
    log("\n" + "="*80)
    log("VERIFICACIÓN DE DATOS EN BASE DE DATOS")
    log("="*80)

    bd_tests_passed = 0
    for compania in COMPANIAS_TEST:
        if verificar_datos_bd(compania):
            bd_tests_passed += 1

    log("\n" + "="*80)
    log(f"BD: {bd_tests_passed}/{len(COMPANIAS_TEST)} compañías verificadas")
    log("="*80)

    # Luego pruebas de Selenium en el sitio web
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1920,1080')

    driver = None
    web_tests_passed = 0

    try:
        log("\n🔧 Iniciando Chrome WebDriver...")
        driver = webdriver.Chrome(options=options)
        driver.implicitly_wait(10)

        # Ejecutar pruebas web
        tests = [
            ("Dashboard", test_dashboard_carga),
            ("Compañías", test_pagina_companias),
        ]

        log("\n" + "="*80)
        log("VERIFICACIÓN DE INTERFAZ WEB")
        log("="*80)

        for nombre, test_func in tests:
            if test_func(driver):
                web_tests_passed += 1

        log("\n" + "="*80)
        log(f"WEB: {web_tests_passed}/{len(tests)} pruebas exitosas")
        log("="*80)

    except Exception as e:
        log(f"❌ Error en pruebas web: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if driver:
            log("🔚 Cerrando navegador...")
            driver.quit()

    # Resumen final
    total_tests = len(COMPANIAS_TEST) + 2  # BD tests + web tests
    total_passed = bd_tests_passed + web_tests_passed

    log("\n" + "="*80)
    log(f"📊 RESUMEN FINAL: {total_passed}/{total_tests} pruebas exitosas")
    log("="*80)

    if bd_tests_passed == len(COMPANIAS_TEST):
        log("✅ TODAS LAS COMPAÑÍAS VERIFICADAS EN BD")
        return 0
    else:
        log("⚠️  ALGUNAS VERIFICACIONES FALLARON")
        return 1

if __name__ == "__main__":
    sys.exit(main())
