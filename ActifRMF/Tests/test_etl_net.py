#!/usr/bin/env python3
"""Test para ETL .NET - ActifRMF"""

import subprocess
import time
import sys
import os
import pyodbc

# Configuración
ETL_PATH = "/Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL"
ID_COMPANIA = 122
AÑO_CALCULO = 2024
LIMITE_TEST = 800

# Connection string
CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=dbdev.powerera.com;"
    "DATABASE=Actif_RMF;"
    "UID=earaiza;"
    "PWD=VgfN-n4ju?H1Z4#JFRE;"
    "TrustServerCertificate=yes;"
)

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def ejecutar_query(query, params=None):
    """Ejecuta una query y retorna los resultados"""
    try:
        conn = pyodbc.connect(CONN_STR)
        cursor = conn.cursor()
        if params:
            cursor.execute(query, params)
        else:
            cursor.execute(query)

        if query.strip().upper().startswith("SELECT"):
            results = cursor.fetchall()
            conn.close()
            return results
        else:
            conn.commit()
            rowcount = cursor.rowcount
            conn.close()
            return rowcount
    except Exception as e:
        log(f"❌ Error en query: {e}")
        return None

def test_limpiar_staging():
    """Limpia datos de prueba anteriores"""
    log("\n=== TEST 1: Limpiar Staging ===")
    query = "DELETE FROM Staging_Activo WHERE ID_Compania = ? AND Año_Calculo = ?"
    rows = ejecutar_query(query, (ID_COMPANIA, AÑO_CALCULO))
    if rows is not None:
        log(f"✅ Staging limpiado: {rows} registros eliminados")
        return True
    log("❌ Error al limpiar staging")
    return False

def test_verificar_tipo_cambio():
    """Verifica que exista tipo de cambio para 30 de junio"""
    log("\n=== TEST 2: Tipo de Cambio ===")
    query = """
        SELECT Tipo_Cambio
        FROM Tipo_Cambio
        WHERE Año = ? AND MONTH(Fecha) = 6 AND DAY(Fecha) = 30 AND ID_Moneda = 2
    """
    result = ejecutar_query(query, (AÑO_CALCULO,))
    if result and len(result) > 0:
        tc = result[0][0]
        log(f"✅ Tipo de cambio 30-Jun-{AÑO_CALCULO}: {tc}")
        return True
    log(f"❌ No existe tipo de cambio para 30-Jun-{AÑO_CALCULO}")
    return False

def test_ejecutar_etl():
    """Ejecuta el ETL .NET con límite de 800 registros"""
    log(f"\n=== TEST 3: Ejecutar ETL ({LIMITE_TEST} registros) ===")

    # Cambiar al directorio del ETL
    os.chdir(ETL_PATH)

    # Ejecutar ETL
    cmd = [
        "dotnet", "run",
        str(ID_COMPANIA),
        str(AÑO_CALCULO),
        "--limit", str(LIMITE_TEST)
    ]

    log(f"🚀 Ejecutando: {' '.join(cmd)}")
    start_time = time.time()

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 minutos timeout
        )

        elapsed = time.time() - start_time
        log(f"⏱️  Tiempo transcurrido: {elapsed:.2f} segundos")

        # Verificar salida
        output = result.stdout
        error = result.stderr

        if result.returncode != 0:
            log(f"❌ ETL falló con código: {result.returncode}")
            if error:
                log(f"Error: {error[:500]}")
            return False

        # Verificar que mencione el límite
        if f"Límite: {LIMITE_TEST}" not in output:
            log("⚠️  No se detectó modo TEST en salida")

        # Verificar que diga "completado"
        if "completado" not in output.lower():
            log("❌ ETL no completó correctamente")
            log(f"Salida: {output[:500]}")
            return False

        # Verificar que extrajo registros
        if "Activos extraídos:" in output:
            import re
            match = re.search(r'Activos extraídos:\s+(\d+)', output)
            if match:
                extraidos = int(match.group(1))
                log(f"📦 Activos extraídos: {extraidos}")

                if extraidos != LIMITE_TEST:
                    log(f"⚠️  Se esperaban {LIMITE_TEST}, se extrajeron {extraidos}")

        # Verificar que cargó registros
        if "Activos cargados:" in output:
            import re
            match = re.search(r'Activos cargados:\s+(\d+)', output)
            if match:
                cargados = int(match.group(1))
                log(f"💾 Activos cargados: {cargados}")

        # Mostrar resumen si está en la salida
        if "RESUMEN DE IMPORTACIÓN" in output:
            log("📊 Resumen encontrado en salida")

        log("✅ ETL ejecutado exitosamente")
        return True

    except subprocess.TimeoutExpired:
        log("❌ ETL excedió timeout de 5 minutos")
        return False
    except Exception as e:
        log(f"❌ Error ejecutando ETL: {e}")
        return False

def test_verificar_staging():
    """Verifica que los datos se cargaron en Staging_Activo"""
    log("\n=== TEST 4: Verificar Staging ===")

    # Contar registros
    query = "SELECT COUNT(*) FROM Staging_Activo WHERE ID_Compania = ? AND Año_Calculo = ?"
    result = ejecutar_query(query, (ID_COMPANIA, AÑO_CALCULO))

    if not result:
        log("❌ Error al consultar staging")
        return False

    total = result[0][0]
    log(f"📊 Total en Staging: {total}")

    if total == 0:
        log("❌ No se cargaron registros")
        return False

    if total < LIMITE_TEST * 0.9:  # Permitir 10% de margen
        log(f"⚠️  Se cargaron menos registros de lo esperado ({total} vs {LIMITE_TEST})")

    # Verificar campos nuevos
    query = """
        SELECT
            COUNT(*) as Total,
            COUNT(CASE WHEN ManejaFiscal = 'S' THEN 1 END) as Con_Fiscal,
            COUNT(CASE WHEN ManejaUSGAAP = 'S' THEN 1 END) as Con_USGAAP,
            COUNT(CASE WHEN CostoUSD IS NOT NULL THEN 1 END) as Con_CostoUSD,
            COUNT(CASE WHEN CostoMXN IS NOT NULL THEN 1 END) as Con_CostoMXN
        FROM Staging_Activo
        WHERE ID_Compania = ? AND Año_Calculo = ?
    """
    result = ejecutar_query(query, (ID_COMPANIA, AÑO_CALCULO))

    if result and len(result) > 0:
        total, fiscal, usgaap, costousd, costomxn = result[0]
        log(f"  - Con ManejaFiscal='S': {fiscal}")
        log(f"  - Con ManejaUSGAAP='S': {usgaap}")
        log(f"  - Con CostoUSD: {costousd}")
        log(f"  - Con CostoMXN: {costomxn}")

        # Verificar que al menos algunos tengan costos
        if costomxn == 0:
            log("❌ Ningún registro tiene CostoMXN")
            return False

    log("✅ Datos verificados en Staging")
    return True

def test_verificar_log():
    """Verifica que se haya registrado en el log"""
    log("\n=== TEST 5: Verificar Log ===")

    query = """
        SELECT TOP 1
            ID_Log, Estado, Registros_Procesados, Duracion_Segundos
        FROM Log_Ejecucion_ETL
        WHERE ID_Compania = ? AND Año_Calculo = ? AND Tipo_Proceso = 'ETL_NET'
        ORDER BY Fecha_Inicio DESC
    """
    result = ejecutar_query(query, (ID_COMPANIA, AÑO_CALCULO))

    if not result or len(result) == 0:
        log("❌ No se encontró registro en log")
        return False

    id_log, estado, registros, duracion = result[0]
    log(f"📝 Log ID: {id_log}")
    log(f"  - Estado: {estado}")
    log(f"  - Registros: {registros}")
    log(f"  - Duración: {duracion} segundos")

    if estado != "Completado":
        log(f"❌ Estado no es 'Completado': {estado}")
        return False

    if registros == 0:
        log("❌ 0 registros procesados según log")
        return False

    log("✅ Log verificado")
    return True

def test_verificar_campos_fiscal_simulado():
    """Verifica que existan registros candidatos para fiscal simulado"""
    log("\n=== TEST 6: Candidatos Fiscal Simulado ===")

    query = """
        SELECT COUNT(*)
        FROM Staging_Activo
        WHERE ID_Compania = ? AND Año_Calculo = ?
          AND ManejaUSGAAP = 'S'
          AND ISNULL(ManejaFiscal, 'N') <> 'S'
          AND CostoUSD IS NOT NULL
          AND CostoUSD > 0
    """
    result = ejecutar_query(query, (ID_COMPANIA, AÑO_CALCULO))

    if not result:
        log("❌ Error al consultar candidatos")
        return False

    candidatos = result[0][0]
    log(f"📊 Candidatos para fiscal simulado: {candidatos}")

    if candidatos > 0:
        # Mostrar muestra
        query_sample = """
            SELECT TOP 3
                ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
                CostoUSD, CostoMXN, FECHA_INIC_DEPREC_3
            FROM Staging_Activo
            WHERE ID_Compania = ? AND Año_Calculo = ?
              AND ManejaUSGAAP = 'S'
              AND ISNULL(ManejaFiscal, 'N') <> 'S'
              AND CostoUSD > 0
        """
        samples = ejecutar_query(query_sample, (ID_COMPANIA, AÑO_CALCULO))

        if samples:
            log("  Muestra:")
            for s in samples:
                log(f"    - {s[0]} ({s[1]}): ${s[3]:,.2f} USD → ${s[4]:,.2f} MXN")

    log(f"✅ {candidatos} candidatos encontrados")
    return True

def main():
    log("🚀 Iniciando pruebas de ETL .NET")
    log(f"Compañía: {ID_COMPANIA}, Año: {AÑO_CALCULO}, Límite: {LIMITE_TEST}")

    tests = [
        ("Limpiar Staging", test_limpiar_staging),
        ("Verificar Tipo Cambio", test_verificar_tipo_cambio),
        ("Ejecutar ETL", test_ejecutar_etl),
        ("Verificar Staging", test_verificar_staging),
        ("Verificar Log", test_verificar_log),
        ("Candidatos Fiscal Simulado", test_verificar_campos_fiscal_simulado)
    ]

    resultados = []
    for nombre, test_func in tests:
        try:
            resultado = test_func()
            resultados.append((nombre, resultado))
        except Exception as e:
            log(f"❌ Excepción en {nombre}: {e}")
            import traceback
            traceback.print_exc()
            resultados.append((nombre, False))

    # Resumen
    log("\n" + "="*80)
    log("📊 RESUMEN DE PRUEBAS")
    log("="*80)

    passed = 0
    for nombre, resultado in resultados:
        status = "✅ PASS" if resultado else "❌ FAIL"
        log(f"{status} - {nombre}")
        if resultado:
            passed += 1

    log("="*80)
    log(f"Total: {passed}/{len(tests)} pruebas exitosas")
    log("="*80)

    return 0 if passed == len(tests) else 1

if __name__ == "__main__":
    sys.exit(main())
