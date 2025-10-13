using System;
using Microsoft.Data.SqlClient;

// Programa para ejecutar SP v4 y validar resultados contra Excel
class ValidarResultados
{
    static void Main()
    {
        string connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
        Guid lote = Guid.Parse("291633ac-047d-4982-8425-aca6c772348c");

        using (var connection = new SqlConnection(connectionString))
        {
            connection.Open();
            Console.WriteLine("========================================");
            Console.WriteLine("VALIDACIÓN SP v4 - CASOS DEL EXCEL");
            Console.WriteLine("========================================");
            Console.WriteLine();

            // Ejecutar el SP
            connection.InfoMessage += (sender, e) => Console.WriteLine(e.Message);

            using (var command = new SqlCommand("sp_Calcular_RMF_Activos_Extranjeros", connection))
            {
                command.CommandType = System.Data.CommandType.StoredProcedure;
                command.CommandTimeout = 120;
                command.Parameters.AddWithValue("@ID_Compania", 188);
                command.Parameters.AddWithValue("@Año_Calculo", 2024);
                command.Parameters.AddWithValue("@Lote_Importacion", lote);

                command.ExecuteNonQuery();
            }

            Console.WriteLine();
            Console.WriteLine("========================================");
            Console.WriteLine("RESULTADOS DETALLADOS POR CASO");
            Console.WriteLine("========================================");
            Console.WriteLine();

            // Consultar resultados detallados
            string query = @"
                SELECT
                    s.ID_ACTIVO,
                    s.DESCRIPCION,
                    c.MOI,
                    c.Tipo_Cambio_30_Junio,
                    c.Saldo_Inicio_Año,
                    c.Dep_Fiscal_Ejercicio,
                    c.Monto_Pendiente,
                    c.Proporcion,
                    c.Prueba_10_Pct_MOI,
                    c.Aplica_10_Pct,
                    c.Valor_Reportable_MXN,
                    c.Ruta_Calculo,
                    c.Descripcion_Ruta
                FROM Calculo_RMF c
                INNER JOIN Staging_Activo s ON c.ID_Staging = s.ID_Staging
                WHERE c.Version_SP = 'v4.2'
                  AND s.Lote_Importacion = @Lote
                ORDER BY s.ID_NUM_ACTIVO";

            using (var queryCmd = new SqlCommand(query, connection))
            {
                queryCmd.Parameters.AddWithValue("@Lote", lote);

                using (var reader = queryCmd.ExecuteReader())
                {
                    // Valores esperados del Excel
                    var expected = new decimal[] {
                        1021876.80m,  // CASO 1
                        881977.00m,   // CASO 2
                        4917782.10m,  // CASO 3
                        1313841.60m,  // CASO 4
                        1459824.00m   // CASO 5
                    };

                    int caso = 0;
                    while (reader.Read())
                    {
                        Console.WriteLine($"ID: {reader["ID_ACTIVO"]}");
                        Console.WriteLine($"Descripción: {reader["DESCRIPCION"]}");
                        Console.WriteLine($"MOI (USD): ${reader["MOI"]:N2}");
                        Console.WriteLine($"TC 30-Jun: {reader["Tipo_Cambio_30_Junio"]:N6}");
                        Console.WriteLine($"Saldo Inicio Año: ${reader["Saldo_Inicio_Año"]:N2}");
                        Console.WriteLine($"Dep Fiscal Ejercicio: ${reader["Dep_Fiscal_Ejercicio"]:N2}");
                        Console.WriteLine($"Monto Pendiente: ${reader["Monto_Pendiente"]:N2}");
                        Console.WriteLine($"Proporción: ${reader["Proporcion"]:N2}");
                        Console.WriteLine($"Prueba 10% MOI: ${reader["Prueba_10_Pct_MOI"]:N2}");
                        Console.WriteLine($"Aplica 10%: {(Convert.ToBoolean(reader["Aplica_10_Pct"]) ? "SÍ" : "NO")}");
                        Console.WriteLine($"Ruta: {reader["Ruta_Calculo"]}");
                        Console.WriteLine($"Descripción Ruta: {reader["Descripcion_Ruta"]}");
                        Console.WriteLine();

                        decimal calculated = Convert.ToDecimal(reader["Valor_Reportable_MXN"]);
                        decimal expectedVal = expected[caso];
                        decimal diff = calculated - expectedVal;
                        decimal pctDiff = (diff / expectedVal) * 100;

                        Console.WriteLine($"VALOR REPORTABLE (MXN): ${calculated:N2}");
                        Console.WriteLine($"ESPERADO (Excel):       ${expectedVal:N2}");
                        Console.WriteLine($"DIFERENCIA:             ${diff:N2} ({pctDiff:N2}%)");

                        if (Math.Abs(diff) < 1.0m)
                        {
                            Console.WriteLine("✓ CORRECTO (diferencia menor a $1)");
                        }
                        else if (Math.Abs(pctDiff) < 0.1m)
                        {
                            Console.WriteLine("⚠ ACEPTABLE (diferencia menor a 0.1%)");
                        }
                        else
                        {
                            Console.WriteLine("✗ ERROR - Revisar cálculo");
                        }

                        Console.WriteLine();
                        Console.WriteLine("----------------------------------------");
                        Console.WriteLine();

                        caso++;
                    }
                }
            }

            Console.WriteLine("========================================");
            Console.WriteLine("VALIDACIÓN COMPLETADA");
            Console.WriteLine("========================================");
        }
    }
}
