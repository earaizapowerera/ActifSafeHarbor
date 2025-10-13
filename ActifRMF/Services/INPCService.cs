using Microsoft.Data.SqlClient;

namespace ActifRMF.Services;

public class INPCService
{
    private readonly string _connectionStringRMF;

    public INPCService(string connectionStringRMF)
    {
        _connectionStringRMF = connectionStringRMF;
    }

    public async Task<INPCResult> ActualizarINPCAsync(int? idGrupoSimulacion = null, string usuario = "Sistema")
    {
        var result = new INPCResult
        {
            FechaInicio = DateTime.Now,
            LoteImportacion = Guid.NewGuid(),
            IdGrupoSimulacion = idGrupoSimulacion
        };

        try
        {
            Console.WriteLine("===========================================");
            Console.WriteLine("Actualización de INPC");
            if (idGrupoSimulacion.HasValue)
                Console.WriteLine($"Grupo Simulación: {idGrupoSimulacion.Value}");
            Console.WriteLine("===========================================\n");

            // 1. Obtener configuración de INPC
            string? connectionStringINPC = null;
            string? queryINPC = null;

            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                var sqlConfig = @"
                    SELECT ConnectionString_INPC, Query_Actualizacion_INPC
                    FROM dbo.ConfiguracionINPC
                    WHERE Activo = 1";

                using var cmdConfig = new SqlCommand(sqlConfig, connRMF);
                using var reader = await cmdConfig.ExecuteReaderAsync();

                if (await reader.ReadAsync())
                {
                    connectionStringINPC = reader.GetString(0);
                    queryINPC = reader.GetString(1);
                }
            }

            if (string.IsNullOrEmpty(connectionStringINPC) || string.IsNullOrEmpty(queryINPC))
            {
                throw new Exception("No existe configuración activa de INPC");
            }

            Console.WriteLine($"Lote: {result.LoteImportacion}");
            Console.WriteLine("Conectando a base origen de INPC...\n");

            // 2. Limpiar datos de INPC antes de importar
            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                string sqlDelete;
                if (idGrupoSimulacion.HasValue)
                {
                    // Borrar solo el grupo de simulación específico
                    sqlDelete = "DELETE FROM dbo.INPC_Importado WHERE Id_GrupoSimulacion = @IdGrupoSimulacion OR Id_GrupoSimulacion IS NULL";
                    using var cmdDelete = new SqlCommand(sqlDelete, connRMF);
                    cmdDelete.Parameters.AddWithValue("@IdGrupoSimulacion", idGrupoSimulacion.Value);
                    await cmdDelete.ExecuteNonQueryAsync();
                    Console.WriteLine($"Datos de INPC del grupo {idGrupoSimulacion.Value} eliminados");
                }
                else
                {
                    // Borrar todos los datos
                    sqlDelete = "TRUNCATE TABLE dbo.INPC_Importado";
                    using var cmdDelete = new SqlCommand(sqlDelete, connRMF);
                    await cmdDelete.ExecuteNonQueryAsync();
                    Console.WriteLine("Tabla INPC_Importado limpiada completamente");
                }
            }

            // 3. Importar datos de INPC
            int registrosImportados = 0;

            using (var connOrigen = new SqlConnection(connectionStringINPC))
            {
                await connOrigen.OpenAsync();

                Console.WriteLine("Extrayendo datos de INPC...");

                using var cmdOrigen = new SqlCommand(queryINPC, connOrigen);
                cmdOrigen.CommandTimeout = 300;

                using var readerOrigen = await cmdOrigen.ExecuteReaderAsync();

                // Preparar INSERT en INPC_Importado
                using var connRMF = new SqlConnection(_connectionStringRMF);
                await connRMF.OpenAsync();

                while (await readerOrigen.ReadAsync())
                {
                    var sqlInsert = @"
                        INSERT INTO dbo.INPC_Importado
                            (Anio, Mes, Id_Pais, Indice, Id_GrupoSimulacion, Fecha_Importacion, Lote_Importacion)
                        VALUES
                            (@Anio, @Mes, @IdPais, @Indice, @IdGrupoSimulacion, @FechaImportacion, @LoteImportacion)";

                    using var cmdInsert = new SqlCommand(sqlInsert, connRMF);
                    cmdInsert.Parameters.AddWithValue("@Anio", readerOrigen["Anio"]);
                    cmdInsert.Parameters.AddWithValue("@Mes", readerOrigen["Mes"]);
                    cmdInsert.Parameters.AddWithValue("@IdPais", readerOrigen["Id_Pais"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@Indice", readerOrigen["Indice"]);
                    cmdInsert.Parameters.AddWithValue("@IdGrupoSimulacion",
                        idGrupoSimulacion.HasValue ? (object)idGrupoSimulacion.Value : DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@FechaImportacion", DateTime.Now);
                    cmdInsert.Parameters.AddWithValue("@LoteImportacion", result.LoteImportacion);

                    await cmdInsert.ExecuteNonQueryAsync();
                    registrosImportados++;
                }
            }

            result.FechaFin = DateTime.Now;
            result.RegistrosImportados = registrosImportados;
            result.DuracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;
            result.Exitoso = true;

            Console.WriteLine("\n✅ Actualización de INPC Completada");
            Console.WriteLine($"Registros importados: {result.RegistrosImportados}");
            Console.WriteLine($"Duración: {result.DuracionSegundos} segundos");
            Console.WriteLine($"Lote: {result.LoteImportacion}\n");

            return result;
        }
        catch (Exception ex)
        {
            result.Exitoso = false;
            result.MensajeError = ex.Message;
            result.FechaFin = DateTime.Now;

            Console.WriteLine($"\n❌ ERROR en actualización de INPC: {ex.Message}\n");

            return result;
        }
    }
}

public class INPCResult
{
    public int RegistrosImportados { get; set; }
    public DateTime FechaInicio { get; set; }
    public DateTime? FechaFin { get; set; }
    public int DuracionSegundos { get; set; }
    public Guid LoteImportacion { get; set; }
    public int? IdGrupoSimulacion { get; set; }
    public bool Exitoso { get; set; }
    public string? MensajeError { get; set; }
}
