using System;
using Microsoft.Data.SqlClient;

class AddColumn
{
    static void Main()
    {
        string connStr = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

        try
        {
            using (var conn = new SqlConnection(connStr))
            {
                conn.Open();
                Console.WriteLine("✅ Conexión exitosa a Actif_RMF");

                // Verificar si la columna ya existe
                string checkSql = @"
                    SELECT COUNT(*)
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = 'dbo'
                      AND TABLE_NAME = 'Staging_Activo'
                      AND COLUMN_NAME = 'COSTO_REVALUADO'";

                using (var cmdCheck = new SqlCommand(checkSql, conn))
                {
                    int exists = (int)cmdCheck.ExecuteScalar();

                    if (exists > 0)
                    {
                        Console.WriteLine("⚠️ La columna COSTO_REVALUADO ya existe en Staging_Activo");
                        return;
                    }
                }

                // Agregar la columna
                string alterSql = "ALTER TABLE dbo.Staging_Activo ADD COSTO_REVALUADO DECIMAL(18, 2) NULL;";

                using (var cmdAlter = new SqlCommand(alterSql, conn))
                {
                    cmdAlter.ExecuteNonQuery();
                    Console.WriteLine("✅ Columna COSTO_REVALUADO agregada exitosamente");
                }

                // Verificar que se agregó correctamente
                using (var cmdCheck = new SqlCommand(checkSql, conn))
                {
                    int exists = (int)cmdCheck.ExecuteScalar();
                    Console.WriteLine($"✅ Verificación: Columna existe = {exists > 0}");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error: {ex.Message}");
            Environment.Exit(1);
        }
    }
}
