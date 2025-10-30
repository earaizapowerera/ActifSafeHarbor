#!/usr/bin/env python3
import requests
import time
import subprocess

print("🧪 Prueba Simple de Barra de Progreso")
print("="*60)

# Lanzar ETL
print("\n📤 Lanzando ETL con 2000 registros...")
response = requests.post("http://localhost:5071/api/etl/ejecutar", json={
    "idCompania": 122,
    "añoCalculo": 2024,
    "usuario": "Test",
    "maxRegistros": 2000
})

lote = response.json()["loteImportacion"]
print(f"✅ ETL lanzado: {lote}")
print("\n⏱️  Esperando 5 segundos...\n")
time.sleep(5)

# Obtener ID_Log
cmd = f'PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF "SELECT TOP 1 ID_Log FROM Log_Ejecucion_ETL WHERE Lote_Importacion = \'{lote}\'"'
result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
id_log = result.stdout.strip().split('\n')[-1]

print(f"📝 ID_Log: {id_log}\n")
print("Consulta | Procesados | Total | %    | Estado     | Actualización")
print("---------|-----------|-

|------|------------|----------------")

last_procesados = 0
for i in range(1, 25):
    cmd = f'PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF "SELECT TOP 1 Estado, Registros_Procesados, Registros_Exitosos FROM Log_Ejecucion_ETL WHERE ID_Log = {id_log}"'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    lines = result.stdout.strip().split('\n')
    if len(lines) > 1:
        parts = lines[-1].split('\t')
        if len(parts) >= 3:
            estado, procesados, total = parts[0], parts[1], parts[2]
            try:
                procesados = int(procesados)
                total = int(total)
                pct = (procesados / total * 100) if total > 0 else 0

                status = "✅ CAMBIÓ" if procesados != last_procesados else "⏳ Sin cambios"

                print(f"  #{i:2d}     | {procesados:10d} | {total:5d} | {pct:4.1f}% | {estado:10s} | {status}")

                last_procesados = procesados

                if estado in ["Completado", "Error"]:
                    print(f"\n🏁 ETL Finalizado: {estado}")
                    break
            except:
                pass

    time.sleep(5)

print("\n" + "="*60)
print("✅ Monitoreo completado")
