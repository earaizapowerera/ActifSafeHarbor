#!/bin/bash

echo "🧪 Prueba de Barra de Progreso ETL - Monitoreo en Tiempo Real"
echo "=============================================================="

# Lanzar ETL con 2000 registros
echo -e "\n📤 Lanzando ETL con 2000 registros..."

RESULT=$(curl -s -X POST http://localhost:5071/api/etl/ejecutar \
  -H "Content-Type: application/json" \
  -d '{"idCompania": 122, "añoCalculo": 2024, "usuario": "Test", "maxRegistros": 2000}')

LOTE=$(echo $RESULT | python3 -c "import sys, json; print(json.load(sys.stdin)['loteImportacion'])")

echo "✅ ETL lanzado"
echo "📦 Lote: $LOTE"
echo -e "\n⏱️  Esperando 5 segundos para que inicie...\n"

sleep 5

# Obtener el ID_Log
ID_LOG=$(PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF \
  "SELECT TOP 1 ID_Log FROM Log_Ejecucion_ETL WHERE Lote_Importacion = '$LOTE'" | tail -1)

echo "📝 ID_Log: $ID_LOG"
echo -e "\n🔍 Monitoreando progreso cada 5 segundos...\n"
echo "Consulta | Tiempo | Estado      | Procesados | Total | % Progreso | Actualización"
echo "---------|--------|-------------|------------|-------|------------|--------------"

LAST_PROCESADOS=0
CONSULTA=0

for i in {1..20}; do
  CONSULTA=$((CONSULTA + 1))
  NOW=$(date +%H:%M:%S)

  RESULT=$(PESqlConnect dbdev.powerera.com earaiza "VgfN-n4ju?H1Z4#JFRE" Actif_RMF \
    "SELECT TOP 1 Estado, Registros_Procesados, Registros_Exitosos, DATEDIFF(SECOND, Fecha_Inicio, GETDATE()) AS Segundos FROM Log_Ejecucion_ETL WHERE ID_Log = $ID_LOG" 2>/dev/null)

  if [ $? -eq 0 ]; then
    ESTADO=$(echo "$RESULT" | tail -1 | awk '{print $1}')
    PROCESADOS=$(echo "$RESULT" | tail -1 | awk '{print $2}')
    TOTAL=$(echo "$RESULT" | tail -1 | awk '{print $3}')
    SEGUNDOS=$(echo "$RESULT" | tail -1 | awk '{print $4}')

    if [ ! -z "$PROCESADOS" ] && [ "$PROCESADOS" != "Registros_Procesados" ]; then
      PORCENTAJE=$(awk "BEGIN {printf \"%.1f\", ($PROCESADOS/$TOTAL)*100}")

      if [ "$PROCESADOS" != "$LAST_PROCESADOS" ]; then
        STATUS="✅ CAMBIÓ"
      else
        STATUS="⏳ Sin cambios"
      fi

      printf "  #%-6d | %s | %-11s | %10d | %5d | %9.1f%% | %s\n" \
        $CONSULTA "$NOW" "$ESTADO" $PROCESADOS $TOTAL $PORCENTAJE "$STATUS"

      LAST_PROCESADOS=$PROCESADOS

      # Si completó, salir
      if [ "$ESTADO" = "Completado" ] || [ "$ESTADO" = "Error" ]; then
        echo -e "\n🏁 ETL Finalizado: $ESTADO"
        break
      fi
    fi
  fi

  sleep 5
done

echo -e "\n=============================================================="
echo "✅ Monitoreo completado"
