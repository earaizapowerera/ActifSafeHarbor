using System;
using System.IO;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        string sqlFile = "/Users/enrique/ActifRMF/Database/ALTER_Add_INPC_Columns.sql";

        Console.WriteLine("Agregando columnas INPC a tabla Calculo_RMF...");
        Console.WriteLine();

        string sqlScript = File.ReadAllText(sqlFile);
        string[] batches = sqlScript.Split(new string[] { "\nGO\n", "\r\nGO\r\n", "\nGO\r\n", "\r\nGO\n" }, StringSplitOptions.None);

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com - Actif_RMF");
            Console.WriteLine();

            connection.InfoMessage += (sender, e) => Console.WriteLine($"  {e.Message}");

            foreach (var batch in batches)
            {
                string trimmedBatch = batch.Trim();
                if (string.IsNullOrWhiteSpace(trimmedBatch)) continue;

                try
                {
                    using (var command = new SqlCommand(trimmedBatch, connection))
                    {
                        command.ExecuteNonQuery();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"✗ Error: {ex.Message}");
                    return;
                }
            }
        }
    }
}
