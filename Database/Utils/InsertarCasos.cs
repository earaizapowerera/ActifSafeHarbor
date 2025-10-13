using System;
using Microsoft.Data.SqlClient;
using System.IO;

// Programa para insertar casos de prueba del Excel
class InsertarCasos
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        string sqlFile = "/Users/enrique/ActifRMF/Database/InsertarCasosExcel.sql";

        string sqlScript = File.ReadAllText(sqlFile);

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com - Base de datos: Actif_RMF");
            Console.WriteLine();

            connection.InfoMessage += (sender, e) => Console.WriteLine(e.Message);

            using (var command = new SqlCommand(sqlScript, connection))
            {
                command.CommandTimeout = 120;

                using (var reader = command.ExecuteReader())
                {
                    do
                    {
                        while (reader.Read())
                        {
                            for (int i = 0; i < reader.FieldCount; i++)
                            {
                                Console.WriteLine($"{reader.GetName(i)}: {reader.GetValue(i)}");
                            }
                            Console.WriteLine();
                        }
                    } while (reader.NextResult());
                }
            }
        }
    }
}
