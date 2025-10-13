using System;
using System.IO;
using Microsoft.Data.SqlClient;

// Programa para ejecutar el stored procedure v4.1 en la base de datos
class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        string sqlFile = "/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Calcular_RMF_Activos_Extranjeros_v4.1.sql";

        string sqlScript = File.ReadAllText(sqlFile);

        // Dividir por GO
        string[] batches = sqlScript.Split(new string[] { "\nGO\n", "\r\nGO\r\n", "\nGO\r\n", "\r\nGO\n" }, StringSplitOptions.None);

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com - Base de datos: Actif_RMF");
            Console.WriteLine();

            int batchNumber = 0;
            foreach (var batch in batches)
            {
                string trimmedBatch = batch.Trim();
                if (string.IsNullOrWhiteSpace(trimmedBatch)) continue;
                if (trimmedBatch.StartsWith("--") && trimmedBatch.Length < 100) continue;

                batchNumber++;
                try
                {
                    Console.WriteLine($"Ejecutando batch {batchNumber}...");
                    using (var command = new SqlCommand(trimmedBatch, connection))
                    {
                        command.CommandTimeout = 120;
                        var result = command.ExecuteNonQuery();
                        Console.WriteLine($"  ✓ Batch {batchNumber} ejecutado correctamente");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"  ✗ Error ejecutando batch {batchNumber}:");
                    Console.WriteLine($"    {ex.Message}");
                    Console.WriteLine();
                    Console.WriteLine($"    SQL: {trimmedBatch.Substring(0, Math.Min(200, trimmedBatch.Length))}...");
                    return;
                }
            }

            Console.WriteLine();
            Console.WriteLine("========================================");
            Console.WriteLine("✓ Stored procedure v4.1 creado exitosamente");
            Console.WriteLine("========================================");
        }
    }
}
