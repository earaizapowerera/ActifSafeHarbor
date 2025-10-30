#!/usr/bin/env python3
import requests, time, subprocess, sys

print("Prueba de Barra de Progreso ETL")
print("="*60)

# Lanzar ETL
print("\nLanzando ETL con 2000 registros...")
r = requests.post("http://localhost:5071/api/etl/ejecutar", json={
    "idCompania": 122, "añoCalculo": 2024, "usuario": "Test", "maxRegistros": 2000
})
lote = r.json()["loteImportacion"]
print(f"ETL lanzado: {lote[:8]}...")
print("\nEsperando 5 segundos...\n")
time.sleep(5)

# Get ID
cmd = f'PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF "SELECT TOP 1 ID_Log FROM Log_Ejecucion_ETL WHERE Lote_Importacion = \'{lote}\'"'
result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
id_log = result.stdout.strip().split('\n')[-1]

print(f"ID_Log: {id_log}\n")
print(f"{'Consulta':<10} {'Procesados':>10} {'Total':>6} {'%':>6} {'Estado':<12} {'Actualizacion'}")
print("-" * 70)

last = 0
for i in range(1, 25):
    cmd = f'PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF "SELECT TOP 1 Estado, Registros_Procesados, Registros_Exitosos FROM Log_Ejecucion_ETL WHERE ID_Log = {id_log}"'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    lines = result.stdout.strip().split('\n')
    if len(lines) > 1:
        parts = lines[-1].split('\t')
        if len(parts) >= 3:
            try:
                estado, proc, total = parts[0], int(parts[1]), int(parts[2])
                pct = (proc/total*100) if total > 0 else 0
                status = "CAMBIO" if proc != last else "Sin cambios"
                print(f"#{i:<9} {proc:>10} {total:>6} {pct:>5.1f}% {estado:<12} {status}")
                last = proc
                if estado in ["Completado", "Error"]:
                    print(f"\nFinalizado: {estado}")
                    break
            except:
                pass
    time.sleep(5)

print("\n" + "="*60)
print("Monitoreo completado")
