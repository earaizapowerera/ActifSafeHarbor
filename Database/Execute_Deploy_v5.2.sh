#!/bin/bash

# Crear versión desplegable del SP
cat StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql | \
sed 's/^\/\*/CREATE PROCEDURE/' | \
sed 's/^\*\///' | \
sed 's/^-- NO EJECUTAR.*//' | \
sed 's/-- IF OBJECT/IF OBJECT/' | \
sed 's/--     DROP PROCEDURE/    DROP PROCEDURE/' | \
sed 's/-- GO/GO/' | \
sed '/^\/\*/,/^\*\//d' > Deploy_SP_v5.2_AUTO.sql

# Agregar header
cat > Deploy_SP_v5.2_AUTO.sql.tmp << 'HEADER'
USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Nacionales', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Nacionales;
GO

HEADER

# Agregar cuerpo del SP (líneas 18-540)
sed -n '18,540p' StoredProcedures/sp_Calcular_RMF_Activos_Nacionales.sql | \
sed 's/^\/\*//' | \
sed 's/^\*\///' >> Deploy_SP_v5.2_AUTO.sql.tmp

# Cerrar CREATE PROCEDURE
echo "END" >> Deploy_SP_v5.2_AUTO.sql.tmp
echo "GO" >> Deploy_SP_v5.2_AUTO.sql.tmp

mv Deploy_SP_v5.2_AUTO.sql.tmp Deploy_SP_v5.2_AUTO.sql

echo "Script generado: Deploy_SP_v5.2_AUTO.sql"
