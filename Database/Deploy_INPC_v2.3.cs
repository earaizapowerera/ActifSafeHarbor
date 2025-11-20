using System;
using System.IO;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        string sqlFile = "/Users/enrique/ActifRMF/Database/StoredProcedures/sp_Actualizar_INPC_Nacionales.sql";

        Console.WriteLine("========================================");
        Console.WriteLine("DEPLOY: SP Actualizar INPC Nacionales v2.3");
        Console.WriteLine("========================================");
        Console.WriteLine();

        string sqlScript = File.ReadAllText(sqlFile);
        string[] batches = sqlScript.Split(new string[] { "\nGO\n", "\r\nGO\r\n", "\nGO\r\n", "\r\nGO\n" }, StringSplitOptions.None);

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com - Actif_RMF");
            Console.WriteLine();

            connection.InfoMessage += (sender, e) => Console.WriteLine($"  {e.Message}");

            int batchNumber = 0;
            foreach (var batch in batches)
            {
                string trimmedBatch = batch.Trim();
                if (string.IsNullOrWhiteSpace(trimmedBatch)) continue;

                batchNumber++;
                try
                {
                    Console.WriteLine($"Ejecutando batch {batchNumber}...");
                    using (var command = new SqlCommand(trimmedBatch, connection))
                    {
                        command.CommandTimeout = 120;
                        command.ExecuteNonQuery();
                        Console.WriteLine($"  ✓ Batch {batchNumber} ejecutado");
                        Console.WriteLine();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"  ✗ Error batch {batchNumber}: {ex.Message}");
                    return;
                }
            }

            Console.WriteLine("========================================");
            Console.WriteLine("✓ SP v2.3 desplegado exitosamente");
            Console.WriteLine("========================================");
        }
    }
}
