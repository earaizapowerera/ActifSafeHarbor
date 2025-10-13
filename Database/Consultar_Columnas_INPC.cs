using System;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("✓ Conectado a dbdev.powerera.com - Base de datos: Actif_RMF\n");

            // Consultar columnas INPC en Staging_Activo
            string query = @"
                SELECT
                    COLUMN_NAME,
                    DATA_TYPE,
                    CHARACTER_MAXIMUM_LENGTH,
                    IS_NULLABLE
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'Staging_Activo'
                    AND (COLUMN_NAME LIKE '%INPC%' OR COLUMN_NAME LIKE '%Inpc%')
                ORDER BY ORDINAL_POSITION;
            ";

            using (var command = new SqlCommand(query, connection))
            {
                using (var reader = command.ExecuteReader())
                {
                    Console.WriteLine("Columnas INPC en Staging_Activo:");
                    Console.WriteLine("=".PadRight(80, '='));

                    bool found = false;
                    while (reader.Read())
                    {
                        found = true;
                        string columnName = reader.GetString(0);
                        string dataType = reader.GetString(1);
                        string maxLength = reader.IsDBNull(2) ? "N/A" : reader.GetInt32(2).ToString();
                        string nullable = reader.GetString(3);

                        Console.WriteLine($"{columnName,-30} {dataType,-15} MaxLen:{maxLength,-10} Nullable:{nullable}");
                    }

                    if (!found)
                    {
                        Console.WriteLine("No se encontraron columnas INPC en Staging_Activo");
                    }
                }
            }

            Console.WriteLine();

            // También revisar en Calculo_RMF
            query = @"
                SELECT
                    COLUMN_NAME,
                    DATA_TYPE,
                    CHARACTER_MAXIMUM_LENGTH,
                    IS_NULLABLE
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'Calculo_RMF'
                    AND (COLUMN_NAME LIKE '%INPC%' OR COLUMN_NAME LIKE '%Inpc%')
                ORDER BY ORDINAL_POSITION;
            ";

            using (var command = new SqlCommand(query, connection))
            {
                using (var reader = command.ExecuteReader())
                {
                    Console.WriteLine("\nColumnas INPC en Calculo_RMF:");
                    Console.WriteLine("=".PadRight(80, '='));

                    bool found = false;
                    while (reader.Read())
                    {
                        found = true;
                        string columnName = reader.GetString(0);
                        string dataType = reader.GetString(1);
                        string maxLength = reader.IsDBNull(2) ? "N/A" : reader.GetInt32(2).ToString();
                        string nullable = reader.GetString(3);

                        Console.WriteLine($"{columnName,-30} {dataType,-15} MaxLen:{maxLength,-10} Nullable:{nullable}");
                    }

                    if (!found)
                    {
                        Console.WriteLine("No se encontraron columnas INPC en Calculo_RMF");
                    }
                }
            }
        }
    }
}
