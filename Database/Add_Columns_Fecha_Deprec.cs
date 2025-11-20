using System;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

        string sql = @"
            -- Verificar si las columnas ya existen antes de agregarlas
            IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Calculo_RMF' AND COLUMN_NAME = 'Fecha_Inicio_Depreciacion')
            BEGIN
                ALTER TABLE Calculo_RMF ADD Fecha_Inicio_Depreciacion DATE NULL;
                PRINT 'Columna Fecha_Inicio_Depreciacion agregada';
            END
            ELSE
            BEGIN
                PRINT 'Columna Fecha_Inicio_Depreciacion ya existe';
            END

            IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Calculo_RMF' AND COLUMN_NAME = 'Fecha_Fin_Depreciacion')
            BEGIN
                ALTER TABLE Calculo_RMF ADD Fecha_Fin_Depreciacion DATE NULL;
                PRINT 'Columna Fecha_Fin_Depreciacion agregada';
            END
            ELSE
            BEGIN
                PRINT 'Columna Fecha_Fin_Depreciacion ya existe';
            END
        ";

        try
        {
            using (var connection = new SqlConnection(connectionString))
            {
                connection.Open();
                Console.WriteLine("Conexión exitosa a Actif_RMF");
                Console.WriteLine("Agregando columnas Fecha_Inicio_Depreciacion y Fecha_Fin_Depreciacion...");
                Console.WriteLine();

                using (var command = new SqlCommand(sql, connection))
                {
                    command.CommandTimeout = 120;

                    using (var reader = command.ExecuteReader())
                    {
                        do
                        {
                            while (reader.Read())
                            {
                                // Leer resultados si los hay
                            }
                        } while (reader.NextResult());
                    }
                }

                Console.WriteLine();
                Console.WriteLine("✅ Columnas agregadas exitosamente");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error: {ex.Message}");
            Environment.Exit(1);
        }
    }
}
