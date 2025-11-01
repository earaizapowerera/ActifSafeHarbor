#!/bin/bash
# Test simple para verificar datos del ETL .NET

echo "=========================================="
echo "TEST ETL .NET - VERIFICACIÓN DE DATOS"
echo "=========================================="
echo ""

cd /Users/enrique/ActifRMF/ETL_NET/ActifRMF.ETL

# Compañías a verificar
COMPANIAS=(188 122 1500)

for COMPANIA in "${COMPANIAS[@]}"; do
    echo ""
    echo "===================="
    echo "COMPAÑÍA: $COMPANIA"
    echo "===================="

    # Verificar registros totales
    echo "1. Total registros en Staging:"
    PESqlConnect -S "dbdev.powerera.com" -d "Actif_RMF" -U "earaiza" -P "VgfN-n4ju?H1Z4#JFRE" \
        -Q "SELECT COUNT(*) as Total FROM Staging_Activo WHERE ID_Compania = $COMPANIA AND Año_Calculo = 2024" \
        -C "TrustServerCertificate=yes" -h -1

    # Verificar campos nuevos
    echo ""
    echo "2. Distribución de campos:"
    PESqlConnect -S "dbdev.powerera.com" -d "Actif_RMF" -U "earaiza" -P "VgfN-n4ju?H1Z4#JFRE" \
        -Q "SELECT
            COUNT(*) as Total,
            COUNT(CASE WHEN ManejaFiscal = 'S' THEN 1 END) as Con_Fiscal,
            COUNT(CASE WHEN ManejaUSGAAP = 'S' THEN 1 END) as Con_USGAAP,
            COUNT(CASE WHEN CostoUSD IS NOT NULL THEN 1 END) as Con_CostoUSD,
            COUNT(CASE WHEN CostoMXN IS NOT NULL AND CostoMXN > 0 THEN 1 END) as Con_CostoMXN
        FROM Staging_Activo
        WHERE ID_Compania = $COMPANIA AND Año_Calculo = 2024" \
        -C "TrustServerCertificate=yes" -h -1

    # Muestra de datos
    echo ""
    echo "3. Muestra de 3 registros:"
    PESqlConnect -S "dbdev.powerera.com" -d "Actif_RMF" -U "earaiza" -P "VgfN-n4ju?H1Z4#JFRE" \
        -Q "SELECT TOP 3
            ID_NUM_ACTIVO,
            ManejaFiscal,
            ManejaUSGAAP,
            CostoUSD,
            CostoMXN
        FROM Staging_Activo
        WHERE ID_Compania = $COMPANIA AND Año_Calculo = 2024
        ORDER BY ID_NUM_ACTIVO" \
        -C "TrustServerCertificate=yes" -h -1
done

echo ""
echo "=========================================="
echo "TEST COMPLETADO"
echo "=========================================="
