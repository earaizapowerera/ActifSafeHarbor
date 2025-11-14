using Microsoft.Data.SqlClient;
using System.Data;
using System.Collections.Concurrent;

namespace ActifRMF.Services;

public class ETLService
{
    private readonly string _connectionStringRMF;

    // Diccionario estático para rastrear progreso de ETL en tiempo real
    private static readonly ConcurrentDictionary<Guid, ETLProgress> _progressTracker = new();

    // Diccionario estático para rastrear progreso de Cálculo en tiempo real
    private static readonly ConcurrentDictionary<Guid, CalculoProgress> _calculoProgressTracker = new();

    public ETLService(string connectionStringRMF)
    {
        _connectionStringRMF = connectionStringRMF;
    }

    public static ETLProgress? ObtenerProgreso(Guid loteImportacion)
    {
        _progressTracker.TryGetValue(loteImportacion, out var progreso);
        return progreso;
    }

    public static CalculoProgress? ObtenerProgresoCalculo(Guid loteCalculo)
    {
        _calculoProgressTracker.TryGetValue(loteCalculo, out var progreso);
        return progreso;
    }

    public async Task<ETLResult> EjecutarETLAsync(int idCompania, int añoCalculo, string usuario = "Sistema", int? maxRegistros = null, Guid? loteImportacion = null)
    {
        var result = new ETLResult
        {
            IdCompania = idCompania,
            AñoCalculo = añoCalculo,
            FechaInicio = DateTime.Now,
            LoteImportacion = loteImportacion ?? Guid.NewGuid()
        };

        try
        {
            Console.WriteLine("===========================================");
            Console.WriteLine($"ETL .NET - Compañía: {idCompania}, Año: {añoCalculo}");
            Console.WriteLine("===========================================\n");

            // NOTA: La limpieza de staging se hace en el ETL .NET para respetar foreign keys
            // El ETL .NET borra en el orden correcto: Calculo_RMF -> Calculo_Fiscal_Simulado -> Staging_Activo

            // Invocar el ETL .NET standalone en lugar de queries cross-database
            // Usar ruta relativa: buscar ETL en directorio padre o configuración
            var baseDir = Directory.GetCurrentDirectory();
            var etlPath = Path.Combine(baseDir, "..", "ETL_NET", "ActifRMF.ETL");
            var etlExe = Path.Combine(etlPath, "bin", "Release", "net8.0", "ActifRMF.ETL.dll");

            // Si no existe, intentar buscar desde el directorio de la aplicación
            if (!File.Exists(etlExe))
            {
                etlPath = Path.Combine(baseDir, "ETL");
                etlExe = Path.Combine(etlPath, "ActifRMF.ETL.dll");
            }

            var arguments = $"\"{etlExe}\" {idCompania} {añoCalculo}";
            if (maxRegistros.HasValue)
            {
                arguments += $" --limit {maxRegistros.Value}";
            }
            // Pasar el lote al ETL .NET para sincronizar con el polling
            arguments += $" --lote {result.LoteImportacion}";

            Console.WriteLine($"Ejecutando: dotnet {arguments}\n");

            var processInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            var process = new System.Diagnostics.Process { StartInfo = processInfo };
            var output = new System.Text.StringBuilder();
            var error = new System.Text.StringBuilder();

            process.OutputDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    Console.WriteLine(e.Data);
                    output.AppendLine(e.Data);
                }
            };

            process.ErrorDataReceived += (sender, e) =>
            {
                if (!string.IsNullOrEmpty(e.Data))
                {
                    Console.WriteLine($"ERROR: {e.Data}");
                    error.AppendLine(e.Data);
                }
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            await process.WaitForExitAsync();

            if (process.ExitCode != 0)
            {
                throw new Exception($"ETL .NET falló con código {process.ExitCode}. Error: {error}");
            }

            // Extraer información del output
            var outputText = output.ToString();

            // Buscar "Activos cargados: XXX"
            var match = System.Text.RegularExpressions.Regex.Match(outputText, @"Activos cargados:\s*(\d+)");
            if (match.Success)
            {
                result.RegistrosImportados = int.Parse(match.Groups[1].Value);
            }

            // Buscar "Lote: GUID"
            var matchLote = System.Text.RegularExpressions.Regex.Match(outputText, @"Lote:\s*([0-9a-f-]+)");
            if (matchLote.Success)
            {
                result.LoteImportacion = Guid.Parse(matchLote.Groups[1].Value);
            }

            result.FechaFin = DateTime.Now;
            result.DuracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;
            result.Estado = "Completado";
            result.Exitoso = true;
            result.QueryEjecutado = $"ETL .NET ejecutado: dotnet {arguments}";

            Console.WriteLine("\n✅ ETL .NET Completado");
            Console.WriteLine($"Registros importados: {result.RegistrosImportados}");
            Console.WriteLine($"Duración: {result.DuracionSegundos} segundos\n");

            return result;
        }
        catch (Exception ex)
        {
            result.Exitoso = false;
            result.Estado = "Fallido";
            result.MensajeError = ex.Message;
            result.FechaFin = DateTime.Now;
            result.DuracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;

            Console.WriteLine($"\n❌ ERROR en ETL: {ex.Message}\n");

            return result;
        }
    }

    public async Task<CalculoResult> EjecutarCalculoAsync(int idCompania, int añoCalculo, string usuario = "Sistema", Guid? loteCalculo = null)
    {
        var result = new CalculoResult
        {
            IdCompania = idCompania,
            AñoCalculo = añoCalculo,
            LoteCalculo = loteCalculo ?? Guid.NewGuid(),
            FechaInicio = DateTime.Now
        };

        try
        {
            Console.WriteLine("===========================================");
            Console.WriteLine($"CÁLCULO RMF - Compañía: {idCompania}, Año: {añoCalculo}");
            Console.WriteLine($"Procesando todos los activos del año en Staging_Activo");
            Console.WriteLine($"Lote Cálculo: {result.LoteCalculo}");
            Console.WriteLine("===========================================\n");

            // Inicializar progreso
            var progreso = new CalculoProgress
            {
                LoteCalculo = result.LoteCalculo,
                Estado = "Iniciando cálculo para todos los activos del año...",
                FechaInicio = result.FechaInicio,
                RegistrosCalculados = 0
            };
            _calculoProgressTracker[result.LoteCalculo] = progreso;

            // Registrar inicio en log (MERGE para evitar duplicados)
            long idLog = 0;
            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                // Usar MERGE para insertar solo si no existe, o actualizar si ya existe
                var sqlLog = @"
                    DECLARE @ID_Log_Result BIGINT;

                    MERGE INTO dbo.Log_Ejecucion_ETL AS target
                    USING (SELECT @LoteImportacion AS Lote_Importacion, 'CALCULO' AS Tipo_Proceso) AS source
                    ON target.Lote_Importacion = source.Lote_Importacion
                       AND target.Tipo_Proceso = source.Tipo_Proceso
                    WHEN MATCHED THEN
                        UPDATE SET
                            Fecha_Inicio = @FechaInicio,
                            Estado = 'En Proceso',
                            Usuario = @Usuario,
                            Fecha_Fin = NULL,
                            Duracion_Segundos = NULL,
                            Registros_Procesados = NULL,
                            Registros_Exitosos = NULL,
                            Registros_Error = NULL,
                            Mensaje_Error = NULL
                    WHEN NOT MATCHED THEN
                        INSERT (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
                                Fecha_Inicio, Estado, Usuario)
                        VALUES (@IdCompania, @AñoCalculo, @LoteImportacion, 'CALCULO',
                                @FechaInicio, 'En Proceso', @Usuario)
                    OUTPUT INSERTED.ID_Log;
                    ";

                using var cmdLog = new SqlCommand(sqlLog, connRMF);
                cmdLog.Parameters.AddWithValue("@IdCompania", idCompania);
                cmdLog.Parameters.AddWithValue("@AñoCalculo", añoCalculo);
                cmdLog.Parameters.AddWithValue("@LoteImportacion", result.LoteCalculo);
                cmdLog.Parameters.AddWithValue("@FechaInicio", result.FechaInicio);
                cmdLog.Parameters.AddWithValue("@Usuario", usuario);

                var idLogResult = await cmdLog.ExecuteScalarAsync();
                if (idLogResult == null || idLogResult == DBNull.Value)
                {
                    throw new Exception($"Error al crear/obtener log de cálculo. El query no retornó ID_Log. Compañía: {idCompania}, Año: {añoCalculo}, Lote: {result.LoteCalculo}");
                }
                idLog = Convert.ToInt64(idLogResult);
            }

            progreso.Estado = "Ejecutando stored procedure...";

            using var connection = new SqlConnection(_connectionStringRMF);
            await connection.OpenAsync();

            // Capturar mensajes PRINT y actualizar progreso
            connection.InfoMessage += (sender, e) =>
            {
                Console.WriteLine(e.Message);
                progreso.Estado = e.Message;
            };

            // Calcular activos EXTRANJEROS
            Console.WriteLine("=== Calculando activos EXTRANJEROS ===");

            using (var command = new SqlCommand("dbo.sp_Calcular_RMF_Activos_Extranjeros", connection))
            {
                command.CommandType = CommandType.StoredProcedure;
                command.CommandTimeout = 300;

                // Solo pasar ID_Compania y Año_Calculo
                command.Parameters.AddWithValue("@ID_Compania", idCompania);
                command.Parameters.AddWithValue("@Año_Calculo", añoCalculo);

                await command.ExecuteNonQueryAsync();
                Console.WriteLine("SP Extranjeros ejecutado");
            }

            // Calcular activos NACIONALES
            Console.WriteLine("=== Calculando activos NACIONALES ===");
            using (var command = new SqlCommand("dbo.sp_Calcular_RMF_Activos_Nacionales", connection))
            {
                command.CommandType = CommandType.StoredProcedure;
                command.CommandTimeout = 300;

                // Solo pasar ID_Compania y Año_Calculo
                command.Parameters.AddWithValue("@ID_Compania", idCompania);
                command.Parameters.AddWithValue("@Año_Calculo", añoCalculo);

                await command.ExecuteNonQueryAsync();
                Console.WriteLine("SP Nacionales ejecutado");
            }

            // Obtener totales de Calculo_RMF por compañía y año
            using (var command = new SqlCommand(@"
                SELECT
                    COUNT(*) AS Total_Registros,
                    SUM(Valor_Reportable_MXN) AS Total_MXN,
                    SUM(CASE WHEN Aplica_10_Pct = 1 THEN 1 ELSE 0 END) AS Con_10Pct
                FROM Calculo_RMF
                WHERE ID_Compania = @ID_Compania
                  AND Año_Calculo = @Año_Calculo", connection))
            {
                command.Parameters.AddWithValue("@ID_Compania", idCompania);
                command.Parameters.AddWithValue("@Año_Calculo", añoCalculo);

                using var reader = await command.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    result.RegistrosCalculados = reader.GetInt32(0);
                    result.TotalValorReportable = reader.IsDBNull(1) ? 0 : reader.GetDecimal(1);
                    result.ActivosCon10PctMOI = reader.GetInt32(2);

                    progreso.RegistrosCalculados = result.RegistrosCalculados;
                    progreso.TotalValorReportable = result.TotalValorReportable;
                    progreso.ActivosCon10PctMOI = result.ActivosCon10PctMOI;
                }
            }

            Console.WriteLine($"=== RESUMEN TOTAL ===");
            Console.WriteLine($"Total calculados: {result.RegistrosCalculados}");
            Console.WriteLine($"Total MXN: ${result.TotalValorReportable:N2}");
            Console.WriteLine($"Con regla 10%: {result.ActivosCon10PctMOI}");

            result.FechaFin = DateTime.Now;
            result.Exitoso = true;

            progreso.Estado = "Completado";
            progreso.FechaFin = result.FechaFin;

            // Actualizar log con éxito
            var duracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;
            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                var sqlUpdateLog = @"
                    UPDATE dbo.Log_Ejecucion_ETL
                    SET Fecha_Fin = @FechaFin,
                        Duracion_Segundos = @DuracionSegundos,
                        Registros_Procesados = @RegistrosProcesados,
                        Registros_Exitosos = @RegistrosProcesados,
                        Registros_Error = 0,
                        Estado = 'Completado'
                    WHERE ID_Log = @IdLog";

                using var cmdUpdateLog = new SqlCommand(sqlUpdateLog, connRMF);
                cmdUpdateLog.Parameters.AddWithValue("@FechaFin", result.FechaFin);
                cmdUpdateLog.Parameters.AddWithValue("@DuracionSegundos", duracionSegundos);
                cmdUpdateLog.Parameters.AddWithValue("@RegistrosProcesados", result.RegistrosCalculados);
                cmdUpdateLog.Parameters.AddWithValue("@IdLog", idLog);

                await cmdUpdateLog.ExecuteNonQueryAsync();
            }

            Console.WriteLine("\n✅ Cálculo Completado");
            Console.WriteLine($"Registros calculados: {result.RegistrosCalculados}");
            Console.WriteLine($"Total valor reportable: ${result.TotalValorReportable:N2} MXN");
            Console.WriteLine($"Activos con regla 10% MOI: {result.ActivosCon10PctMOI}");
            Console.WriteLine($"Lote cálculo: {result.LoteCalculo}\n");

            return result;
        }
        catch (Exception ex)
        {
            result.Exitoso = false;
            result.MensajeError = ex.Message;
            result.FechaFin = DateTime.Now;
            var duracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;

            // Marcar progreso como error
            if (_calculoProgressTracker.TryGetValue(result.LoteCalculo, out var progreso))
            {
                progreso.Estado = $"Error: {ex.Message}";
                progreso.FechaFin = result.FechaFin;
            }

            // Actualizar log en BD con el error
            try
            {
                using var connRMF = new SqlConnection(_connectionStringRMF);
                await connRMF.OpenAsync();

                var sqlUpdateLog = @"
                    UPDATE dbo.Log_Ejecucion_ETL
                    SET Fecha_Fin = @FechaFin,
                        Duracion_Segundos = @DuracionSegundos,
                        Estado = 'Fallido',
                        Mensaje_Error = @MensajeError
                    WHERE Lote_Importacion = @LoteImportacion
                      AND Tipo_Proceso = 'CALCULO'";

                using var cmdUpdateLog = new SqlCommand(sqlUpdateLog, connRMF);
                cmdUpdateLog.Parameters.AddWithValue("@FechaFin", result.FechaFin);
                cmdUpdateLog.Parameters.AddWithValue("@DuracionSegundos", duracionSegundos);
                cmdUpdateLog.Parameters.AddWithValue("@MensajeError", ex.Message);
                cmdUpdateLog.Parameters.AddWithValue("@LoteImportacion", result.LoteCalculo);

                await cmdUpdateLog.ExecuteNonQueryAsync();
            }
            catch (Exception logEx)
            {
                Console.WriteLine($"⚠️  Error actualizando log: {logEx.Message}");
            }

            Console.WriteLine($"\n❌ ERROR en Cálculo: {ex.Message}\n");

            return result;
        }
    }
}

public class ETLResult
{
    public int IdCompania { get; set; }
    public int AñoCalculo { get; set; }
    public Guid LoteImportacion { get; set; }
    public int RegistrosImportados { get; set; }
    public DateTime FechaInicio { get; set; }
    public DateTime? FechaFin { get; set; }
    public int DuracionSegundos { get; set; }
    public string Estado { get; set; } = "";
    public bool Exitoso { get; set; }
    public string? MensajeError { get; set; }
    public string? QueryEjecutado { get; set; }  // Query con sustituciones de parámetros
}

public class CalculoResult
{
    public int IdCompania { get; set; }
    public int AñoCalculo { get; set; }
    public Guid LoteImportacion { get; set; }
    public Guid LoteCalculo { get; set; }
    public int RegistrosCalculados { get; set; }
    public decimal TotalValorReportable { get; set; }
    public int ActivosCon10PctMOI { get; set; }
    public DateTime FechaInicio { get; set; }
    public DateTime? FechaFin { get; set; }
    public bool Exitoso { get; set; }
    public string? MensajeError { get; set; }
}

public class ETLProgress
{
    public Guid LoteImportacion { get; set; }
    public int RegistrosInsertados { get; set; }
    public int TotalRegistros { get; set; }
    public string Estado { get; set; } = "";
    public DateTime FechaInicio { get; set; }
    public DateTime? FechaFin { get; set; }
}

public class CalculoProgress
{
    public Guid LoteCalculo { get; set; }
    public int RegistrosCalculados { get; set; }
    public decimal TotalValorReportable { get; set; }
    public int ActivosCon10PctMOI { get; set; }
    public string Estado { get; set; } = "";
    public DateTime FechaInicio { get; set; }
    public DateTime? FechaFin { get; set; }
}
