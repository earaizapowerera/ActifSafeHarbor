using System;
using System.IO;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        string sqlFile = "/Users/enrique/ActifRMF/Database/Deploy_SP_Nacionales_v5.1.sql";

        Console.WriteLine("========================================");
        Console.WriteLine("DEPLOY: SP Calcular RMF Activos NACIONALES v5.1");
        Console.WriteLine("========================================");
        Console.WriteLine();

        string sqlScript = File.ReadAllText(sqlFile);

        // Dividir por GO
        string[] batches = sqlScript.Split(new string[] { "\nGO\n", "\r\nGO\r\n", "\nGO\r\n", "\r\nGO\n" }, StringSplitOptions.None);

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com");
            Console.WriteLine("✓ Base de datos: Actif_RMF");
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

                        // Capturar mensajes PRINT del servidor
                        connection.InfoMessage += (sender, e) =>
                        {
                            Console.WriteLine($"  {e.Message}");
                        };

                        var result = command.ExecuteNonQuery();
                        Console.WriteLine($"  ✓ Batch {batchNumber} ejecutado correctamente");
                        Console.WriteLine();
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

            Console.WriteLine("========================================");
            Console.WriteLine("✓ SP v5.1 desplegado exitosamente");
            Console.WriteLine("========================================");
            Console.WriteLine();
            Console.WriteLine("Características v5.1:");
            Console.WriteLine("  - Validación de INPC faltantes");
            Console.WriteLine("  - ERROR marcado en Observaciones");
            Console.WriteLine("  - Reporte detallado de INPCs faltantes");
            Console.WriteLine();
        }
    }
}
