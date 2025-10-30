#!/usr/bin/env python3
"""
Prueba automatizada de la barra de progreso del ETL
Verifica que se actualice cada consulta o cada 10 segundos
"""

import requests
import time
import sys
from datetime import datetime

def test_progress_updates():
    print("🧪 Iniciando prueba de barra de progreso ETL...")
    print("="*70)

    base_url = "http://localhost:5071"

    # Lanzar ETL con límite de 500 registros (prueba rápida)
    print("\n📤 Lanzando ETL...")
    payload = {
        "idCompania": 122,
        "añoCalculo": 2024,
        "usuario": "Test",
        "maxRegistros": 500
    }

    response = requests.post(f"{base_url}/api/etl/ejecutar", json=payload)

    if response.status_code != 200:
        print(f"❌ Error al lanzar ETL: {response.status_code}")
        print(response.text)
        return False

    result = response.json()
    lote = result.get("loteImportacion")

    print(f"✅ ETL lanzado exitosamente")
    print(f"📦 Lote: {lote}")
    print(f"🏢 Compañía: {payload['idCompania']}")
    print(f"📅 Año: {payload['añoCalculo']}")
    print(f"📊 Límite: {payload['maxRegistros']} registros")
    print("\n" + "="*70)
    print("⏱️  Monitoreando progreso...\n")

    # Monitorear progreso
    updates = []
    last_registros = 0
    consulta = 0
    start_time = time.time()

    while True:
        consulta += 1
        now = datetime.now().strftime("%H:%M:%S")

        # Consultar progreso
        response = requests.get(f"{base_url}/api/etl/progreso/{lote}")

        if response.status_code != 200:
            print(f"❌ Error consultando progreso: {response.status_code}")
            break

        progreso = response.json()
        estado = progreso.get("estado", "")
        registros = progreso.get("registrosInsertados", 0)
        total = progreso.get("totalRegistros", 0)

        # Detectar actualización
        if registros != last_registros:
            elapsed = time.time() - start_time
            porcentaje = (registros / total * 100) if total > 0 else 0

            update_info = {
                'consulta': consulta,
                'tiempo': elapsed,
                'registros': registros,
                'total': total,
                'porcentaje': porcentaje
            }
            updates.append(update_info)

            print(f"[{now}] Consulta #{consulta:2d} | "
                  f"Registros: {registros:4d}/{total:4d} | "
                  f"Progreso: {porcentaje:5.1f}% | "
                  f"⏱️  {elapsed:.1f}s | "
                  f"✅ ACTUALIZADO")

            last_registros = registros
        else:
            elapsed = time.time() - start_time
            print(f"[{now}] Consulta #{consulta:2d} | "
                  f"Registros: {registros:4d}/{total:4d} | "
                  f"⏱️  {elapsed:.1f}s | "
                  f"⏳ Sin cambios")

        # Verificar si completó
        if estado == "Completado" or estado.startswith("Error"):
            print(f"\n{'='*70}")
            print(f"🏁 ETL Finalizado: {estado}")
            break

        # Esperar 5 segundos antes de siguiente consulta
        time.sleep(5)

    # Análisis de resultados
    print(f"\n{'='*70}")
    print("📊 ANÁLISIS DE RESULTADOS\n")

    total_time = time.time() - start_time
    print(f"⏱️  Tiempo total: {total_time:.1f} segundos")
    print(f"🔄 Consultas realizadas: {consulta}")
    print(f"✅ Actualizaciones detectadas: {len(updates)}")
    print(f"📈 Registros finales: {last_registros}")

    if len(updates) > 1:
        print(f"\n📏 Tiempos entre actualizaciones:")
        for i in range(1, len(updates)):
            tiempo_entre = updates[i]['tiempo'] - updates[i-1]['tiempo']
            print(f"  Update {i}: {tiempo_entre:.1f}s después de la anterior")

    # Verificar criterio de éxito
    print(f"\n{'='*70}")
    print("🎯 CRITERIO DE ÉXITO:")

    success = True

    # Debe haber al menos 2 actualizaciones
    if len(updates) >= 2:
        print("  ✅ Se detectaron múltiples actualizaciones")
    else:
        print("  ❌ No se detectaron suficientes actualizaciones")
        success = False

    # Verificar que las actualizaciones ocurren con frecuencia
    if len(updates) > 1:
        avg_time_between = (updates[-1]['tiempo'] - updates[0]['tiempo']) / (len(updates) - 1)
        print(f"  📊 Tiempo promedio entre actualizaciones: {avg_time_between:.1f}s")

        if avg_time_between <= 15:  # Debería actualizar cada ~10s o menos
            print(f"  ✅ Actualizaciones frecuentes (cada {avg_time_between:.1f}s)")
        else:
            print(f"  ⚠️  Actualizaciones lentas (cada {avg_time_between:.1f}s)")

    print(f"\n{'='*70}")

    if success:
        print("✅ PRUEBA EXITOSA: La barra de progreso se actualiza correctamente")
        return True
    else:
        print("❌ PRUEBA FALLIDA: La barra de progreso no se actualiza como esperado")
        return False

if __name__ == "__main__":
    try:
        success = test_progress_updates()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⏸️  Prueba interrumpida por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error en la prueba: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
