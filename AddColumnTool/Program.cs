using System;
using Microsoft.Data.SqlClient;

string connStr = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

try
{
    using (var conn = new SqlConnection(connStr))
    {
        conn.Open();
        Console.WriteLine("✅ Conexión exitosa a Actif_RMF");

        // Verificar si COSTO_ADQUISICION existe
        string checkAdquisicionSql = @"
            SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'dbo'
              AND TABLE_NAME = 'Staging_Activo'
              AND COLUMN_NAME = 'COSTO_ADQUISICION'";

        using (var cmdCheck = new SqlCommand(checkAdquisicionSql, conn))
        {
            int exists = (int)cmdCheck.ExecuteScalar();

            if (exists == 0)
            {
                Console.WriteLine("⚠️  La columna COSTO_ADQUISICION ya fue eliminada");
            }
            else
            {
                // Eliminar la columna COSTO_ADQUISICION
                Console.WriteLine("🗑️  Eliminando columna COSTO_ADQUISICION...");
                string dropSql = "ALTER TABLE dbo.Staging_Activo DROP COLUMN COSTO_ADQUISICION;";

                using (var cmdDrop = new SqlCommand(dropSql, conn))
                {
                    cmdDrop.ExecuteNonQuery();
                    Console.WriteLine("✅ Columna COSTO_ADQUISICION eliminada exitosamente");
                }
            }
        }

        // Verificar columnas finales
        string verifyAllSql = @"
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'dbo'
              AND TABLE_NAME = 'Staging_Activo'
              AND COLUMN_NAME IN ('COSTO_ADQUISICION', 'COSTO_REVALUADO')
            ORDER BY COLUMN_NAME";

        Console.WriteLine("\n📋 Columnas finales:");
        using (var cmdVerify = new SqlCommand(verifyAllSql, conn))
        using (var reader = cmdVerify.ExecuteReader())
        {
            while (reader.Read())
            {
                Console.WriteLine($"   ✓ {reader.GetString(0)}");
            }
        }
    }
}
catch (Exception ex)
{
    Console.WriteLine($"❌ Error: {ex.Message}");
    Environment.Exit(1);
}
