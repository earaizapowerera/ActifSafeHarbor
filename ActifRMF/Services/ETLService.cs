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
            Console.WriteLine($"ETL - Compañía: {idCompania}, Año: {añoCalculo}");
            Console.WriteLine("===========================================\n");

            // 1. Obtener configuración de la compañía (connection string y query ETL)
            string? connectionStringOrigen = null;
            string? nombreCompania = null;
            string? queryETL = null;

            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                var sqlConfig = @"
                    SELECT ConnectionString_Actif, Nombre_Compania, Query_ETL
                    FROM dbo.ConfiguracionCompania
                    WHERE ID_Compania = @IdCompania AND Activo = 1";

                using var cmdConfig = new SqlCommand(sqlConfig, connRMF);
                cmdConfig.Parameters.AddWithValue("@IdCompania", idCompania);

                using var reader = await cmdConfig.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    connectionStringOrigen = reader.GetString(0);
                    nombreCompania = reader.GetString(1);
                    queryETL = reader.IsDBNull(2) ? null : reader.GetString(2);
                }
            }

            if (string.IsNullOrEmpty(connectionStringOrigen))
            {
                throw new Exception($"Compañía {idCompania} no existe o no está activa");
            }

            // Si no hay query personalizado en la compañía, usar el query predeterminado
            if (string.IsNullOrEmpty(queryETL))
            {
                queryETL = @"
                    SELECT
                        af.ID_NUM_ACTIVO,
                        af.ID_ACTIVO,
                        af.ID_TIPO_ACTIVO,
                        af.ID_SUBTIPO_ACTIVO,
                        ta.DESCRIPCION AS Nombre_TipoActivo,
                        af.DESCRIPCION,
                        af.COSTO_REVALUADO,
                        af.Costo_Fiscal,
                        af.ID_MONEDA,
                        m.DESCRIPCION AS Nombre_Moneda,
                        COALESCE(af.ID_PAIS, 1) AS ID_PAIS,
                        COALESCE(p.DESCRIPCION, 'México') AS Nombre_Pais,
                        af.FECHA_COMPRA,
                        af.FECHA_BAJA,
                        af.FECHA_INIC_DEPREC,
                        af.STATUS,
                        af.FLG_PROPIO,
                        td.TASA_ANUAL AS Tasa_Anual,
                        td.TASA_MENSUAL AS Tasa_Mensual,
                        COALESCE(dbo.fn_DepAcumInicio(@ID_COMPANIA, af.ID_NUM_ACTIVO, @AÑO_ANTERIOR), 0) AS Dep_Acum_Inicio_Año
                    FROM dbo.activo af
                    INNER JOIN dbo.tipo_activo ta ON af.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO
                    LEFT JOIN dbo.moneda m ON af.ID_MONEDA = m.ID_MONEDA
                    LEFT JOIN dbo.pais p ON af.ID_PAIS = p.ID_PAIS
                    LEFT JOIN dbo.tasa_deprec td ON af.ID_TIPO_ACTIVO = td.ID_TIPO_ACTIVO
                    WHERE af.ID_COMPANIA = @ID_COMPANIA
                      AND af.FLG_PROPIO = 0
                      AND (af.FECHA_COMPRA < DATEADD(YEAR, 1, DATEFROMPARTS(@AÑO_CALCULO, 1, 1))
                           OR af.FECHA_COMPRA IS NULL)
                      AND (af.FECHA_BAJA >= DATEFROMPARTS(@AÑO_CALCULO, 1, 1)
                           OR af.FECHA_BAJA IS NULL)
                    ORDER BY af.ID_NUM_ACTIVO";
            }

            Console.WriteLine($"Compañía: {nombreCompania}");
            Console.WriteLine($"Lote: {result.LoteImportacion}");
            Console.WriteLine($"Conectando a base origen...\n");

            // 2. Registrar inicio en log (MERGE para evitar duplicados)
            long idLog = 0;
            using (var connRMF = new SqlConnection(_connectionStringRMF))
            {
                await connRMF.OpenAsync();

                // Usar MERGE para insertar solo si no existe, o actualizar si ya existe
                var sqlLog = @"
                    MERGE INTO dbo.Log_Ejecucion_ETL AS target
                    USING (SELECT @LoteImportacion AS Lote_Importacion, 'ETL' AS Tipo_Proceso) AS source
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
                        VALUES (@IdCompania, @AñoCalculo, @LoteImportacion, 'ETL',
                                @FechaInicio, 'En Proceso', @Usuario);

                    SELECT ID_Log
                    FROM dbo.Log_Ejecucion_ETL
                    WHERE Lote_Importacion = @LoteImportacion
                      AND Tipo_Proceso = 'ETL';";

                using var cmdLog = new SqlCommand(sqlLog, connRMF);
                cmdLog.Parameters.AddWithValue("@IdCompania", idCompania);
                cmdLog.Parameters.AddWithValue("@AñoCalculo", añoCalculo);
                cmdLog.Parameters.AddWithValue("@LoteImportacion", result.LoteImportacion);
                cmdLog.Parameters.AddWithValue("@FechaInicio", result.FechaInicio);
                cmdLog.Parameters.AddWithValue("@Usuario", usuario);

                idLog = (long)await cmdLog.ExecuteScalarAsync();
            }

            // 3. Ejecutar query en base origen y cargar a staging
            int registrosImportados = 0;

            using (var connOrigen = new SqlConnection(connectionStringOrigen))
            {
                await connOrigen.OpenAsync();

                // Reemplazar parámetros en el query
                var añoAnterior = añoCalculo - 1;
                var queryFinal = queryETL
                    .Replace("@ID_COMPANIA", idCompania.ToString())
                    .Replace("@AÑO_CALCULO", añoCalculo.ToString())
                    .Replace("@AÑO_ANTERIOR", añoAnterior.ToString());

                // Inyectar TOP si se especificó maxRegistros (para pruebas)
                if (maxRegistros.HasValue)
                {
                    // Buscar la primera palabra SELECT e inyectar TOP después
                    var selectIndex = queryFinal.IndexOf("SELECT", StringComparison.OrdinalIgnoreCase);
                    if (selectIndex >= 0)
                    {
                        queryFinal = queryFinal.Insert(selectIndex + 6, $" TOP {maxRegistros.Value}");
                        Console.WriteLine($"⚠️  MODO PRUEBA: Limitando a {maxRegistros.Value} registros");
                    }
                }

                // Guardar el query ejecutado para mostrarlo al usuario
                result.QueryEjecutado = queryFinal;

                // 🔍 DEBUG: Mostrar query con sustituciones ANTES de ejecutar
                Console.WriteLine("\n🔍 DEBUG - Query a ejecutar:");
                Console.WriteLine("================================================================================");
                Console.WriteLine(queryFinal);
                Console.WriteLine("================================================================================\n");

                Console.WriteLine("Contando registros a extraer...");

                // Primero obtener el count total de registros
                var queryCount = $"SELECT COUNT(*) FROM ({queryFinal}) AS CountQuery";
                int totalRegistros = 0;

                using (var cmdCount = new SqlCommand(queryCount, connOrigen))
                {
                    cmdCount.CommandTimeout = 60;
                    totalRegistros = (int)await cmdCount.ExecuteScalarAsync();
                }

                Console.WriteLine($"Total de registros a procesar: {totalRegistros}");

                // Inicializar tracking de progreso con el total
                var progreso = new ETLProgress
                {
                    LoteImportacion = result.LoteImportacion,
                    RegistrosInsertados = 0,
                    TotalRegistros = totalRegistros,
                    Estado = "Extrayendo...",
                    FechaInicio = result.FechaInicio
                };
                _progressTracker[result.LoteImportacion] = progreso;

                Console.WriteLine("Extrayendo datos de base origen...");

                progreso.Estado = "Insertando registros...";

                using var cmdOrigen = new SqlCommand(queryFinal, connOrigen);
                cmdOrigen.CommandTimeout = 300;

                using var readerOrigen = await cmdOrigen.ExecuteReaderAsync();

                // 🔍 DEBUG: Mostrar columnas del DataReader
                Console.WriteLine("\n🔍 DEBUG - Columnas en el DataReader:");
                Console.WriteLine("================================================================================");
                for (int i = 0; i < readerOrigen.FieldCount; i++)
                {
                    Console.WriteLine($"  [{i}] {readerOrigen.GetName(i)}");
                }
                Console.WriteLine("================================================================================\n");

                // Preparar INSERT en staging
                using var connRMF = new SqlConnection(_connectionStringRMF);
                await connRMF.OpenAsync();

                while (await readerOrigen.ReadAsync())
                {
                    var sqlInsert = @"
                        INSERT INTO Actif_RMF.dbo.Staging_Activo
                            (ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
                             Nombre_TipoActivo, DESCRIPCION, COSTO_REVALUADO, ID_MONEDA, Nombre_Moneda,
                             ID_PAIS, Nombre_Pais, FECHA_COMPRA, FECHA_BAJA, FECHA_INICIO_DEP, STATUS,
                             FLG_PROPIO, Tasa_Anual, Tasa_Mensual, Dep_Acum_Inicio_Año,
                             Año_Calculo, Lote_Importacion)
                        VALUES
                            (@IdCompania, @IdNumActivo, @IdActivo, @IdTipoActivo, @IdSubtipoActivo,
                             @NombreTipoActivo, @Descripcion, @CostoRevaluado, @IdMoneda, @NombreMoneda,
                             @IdPais, @NombrePais, @FechaCompra, @FechaBaja, @FechaInicioDep, @Status,
                             @FlgPropio, @TasaAnual, @TasaMensual, @DepAcumInicioAño,
                             @AñoCalculo, @LoteImportacion)";

                    using var cmdInsert = new SqlCommand(sqlInsert, connRMF);
                    cmdInsert.Parameters.AddWithValue("@IdCompania", idCompania);
                    cmdInsert.Parameters.AddWithValue("@IdNumActivo", readerOrigen["ID_NUM_ACTIVO"]);
                    cmdInsert.Parameters.AddWithValue("@IdActivo", readerOrigen["ID_ACTIVO"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@IdTipoActivo", readerOrigen["ID_TIPO_ACTIVO"]);
                    cmdInsert.Parameters.AddWithValue("@IdSubtipoActivo", readerOrigen["ID_SUBTIPO_ACTIVO"]);
                    cmdInsert.Parameters.AddWithValue("@NombreTipoActivo", readerOrigen["Nombre_TipoActivo"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@Descripcion", readerOrigen["DESCRIPCION"] ?? DBNull.Value);

                    // Read COSTO_REVALUADO directly (no alias)
                    cmdInsert.Parameters.AddWithValue("@CostoRevaluado", readerOrigen["COSTO_REVALUADO"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@IdMoneda", readerOrigen["ID_MONEDA"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@NombreMoneda", readerOrigen["Nombre_Moneda"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@IdPais", readerOrigen["ID_PAIS"]);
                    cmdInsert.Parameters.AddWithValue("@NombrePais", readerOrigen["Nombre_Pais"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@FechaCompra", readerOrigen["FECHA_COMPRA"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@FechaBaja", readerOrigen["FECHA_BAJA"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@FechaInicioDep", readerOrigen["FECHA_INICIO_DEP"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@Status", readerOrigen["STATUS"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@FlgPropio", readerOrigen["FLG_PROPIO"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@TasaAnual", readerOrigen["Tasa_Anual"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@TasaMensual", readerOrigen["Tasa_Mensual"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@DepAcumInicioAño", readerOrigen["Dep_Acum_Inicio_Año"] ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue("@AñoCalculo", añoCalculo);
                    cmdInsert.Parameters.AddWithValue("@LoteImportacion", result.LoteImportacion);

                    await cmdInsert.ExecuteNonQueryAsync();
                    registrosImportados++;

                    // Actualizar progreso
                    progreso.RegistrosInsertados = registrosImportados;
                }
            }

            // 4. Actualizar log con éxito
            result.FechaFin = DateTime.Now;
            result.RegistrosImportados = registrosImportados;
            result.DuracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;
            result.Estado = "Completado";
            result.Exitoso = true;

            // Marcar progreso como completado
            if (_progressTracker.TryGetValue(result.LoteImportacion, out var progresoFinal))
            {
                progresoFinal.Estado = "Completado";
                progresoFinal.FechaFin = result.FechaFin;
            }

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
                cmdUpdateLog.Parameters.AddWithValue("@DuracionSegundos", result.DuracionSegundos);
                cmdUpdateLog.Parameters.AddWithValue("@RegistrosProcesados", registrosImportados);
                cmdUpdateLog.Parameters.AddWithValue("@IdLog", idLog);

                await cmdUpdateLog.ExecuteNonQueryAsync();
            }

            Console.WriteLine("\n✅ ETL Completado");
            Console.WriteLine($"Registros importados: {result.RegistrosImportados}");
            Console.WriteLine($"Duración: {result.DuracionSegundos} segundos");
            Console.WriteLine($"Lote: {result.LoteImportacion}\n");

            return result;
        }
        catch (Exception ex)
        {
            result.Exitoso = false;
            result.Estado = "Fallido";
            result.MensajeError = ex.Message;
            result.FechaFin = DateTime.Now;
            result.DuracionSegundos = (int)(result.FechaFin.Value - result.FechaInicio).TotalSeconds;

            // Marcar progreso como error
            if (_progressTracker.TryGetValue(result.LoteImportacion, out var progreso))
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
                      AND Tipo_Proceso = 'ETL'";

                using var cmdUpdateLog = new SqlCommand(sqlUpdateLog, connRMF);
                cmdUpdateLog.Parameters.AddWithValue("@FechaFin", result.FechaFin);
                cmdUpdateLog.Parameters.AddWithValue("@DuracionSegundos", result.DuracionSegundos);
                cmdUpdateLog.Parameters.AddWithValue("@MensajeError", ex.Message);
                cmdUpdateLog.Parameters.AddWithValue("@LoteImportacion", result.LoteImportacion);

                await cmdUpdateLog.ExecuteNonQueryAsync();
            }
            catch (Exception logEx)
            {
                Console.WriteLine($"⚠️  Error actualizando log: {logEx.Message}");
            }

            Console.WriteLine($"\n❌ ERROR en ETL: {ex.Message}\n");

            return result;
        }
    }

    public async Task<CalculoResult> EjecutarCalculoAsync(int idCompania, int añoCalculo, Guid loteImportacion, string usuario = "Sistema", Guid? loteCalculo = null)
    {
        var result = new CalculoResult
        {
            IdCompania = idCompania,
            AñoCalculo = añoCalculo,
            LoteImportacion = loteImportacion,
            LoteCalculo = loteCalculo ?? Guid.NewGuid(),
            FechaInicio = DateTime.Now
        };

        try
        {
            Console.WriteLine("===========================================");
            Console.WriteLine($"CÁLCULO RMF - Compañía: {idCompania}, Año: {añoCalculo}");
            Console.WriteLine($"Lote Cálculo: {result.LoteCalculo}");
            Console.WriteLine("===========================================\n");

            // Inicializar progreso
            var progreso = new CalculoProgress
            {
                LoteCalculo = result.LoteCalculo,
                Estado = "Iniciando cálculo...",
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
                                @FechaInicio, 'En Proceso', @Usuario);

                    SELECT ID_Log
                    FROM dbo.Log_Ejecucion_ETL
                    WHERE Lote_Importacion = @LoteImportacion
                      AND Tipo_Proceso = 'CALCULO';";

                using var cmdLog = new SqlCommand(sqlLog, connRMF);
                cmdLog.Parameters.AddWithValue("@IdCompania", idCompania);
                cmdLog.Parameters.AddWithValue("@AñoCalculo", añoCalculo);
                cmdLog.Parameters.AddWithValue("@LoteImportacion", result.LoteCalculo);
                cmdLog.Parameters.AddWithValue("@FechaInicio", result.FechaInicio);
                cmdLog.Parameters.AddWithValue("@Usuario", usuario);

                idLog = (long)await cmdLog.ExecuteScalarAsync();
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

            // Calcular activos extranjeros
            using (var command = new SqlCommand("dbo.sp_Calcular_RMF_Activos_Extranjeros", connection))
            {
                command.CommandType = CommandType.StoredProcedure;
                command.CommandTimeout = 300;

                command.Parameters.AddWithValue("@ID_Compania", idCompania);
                command.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
                command.Parameters.AddWithValue("@Lote_Importacion", loteImportacion);

                using var reader = await command.ExecuteReaderAsync();

                if (await reader.ReadAsync())
                {
                    result.LoteCalculo = reader.GetGuid(reader.GetOrdinal("Lote_Calculo"));
                    result.RegistrosCalculados = reader.GetInt32(reader.GetOrdinal("Registros_Calculados"));
                    result.TotalValorReportable = reader.GetDecimal(reader.GetOrdinal("Total_Valor_Reportable_MXN"));
                    result.ActivosCon10PctMOI = reader.GetInt32(reader.GetOrdinal("Activos_Con_Regla_10_Pct"));

                    progreso.RegistrosCalculados = result.RegistrosCalculados;
                    progreso.TotalValorReportable = result.TotalValorReportable;
                    progreso.ActivosCon10PctMOI = result.ActivosCon10PctMOI;
                }
            }

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
