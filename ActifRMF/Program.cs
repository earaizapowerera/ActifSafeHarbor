using ActifRMF.Services;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddOpenApi();

// Configuration
var connectionStringRMF = builder.Configuration.GetConnectionString("ActifRMF") ?? "";

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();
app.UseDefaultFiles();
app.UseStaticFiles();

// =============================================
// ENDPOINT: Health Check
// =============================================
app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    timestamp = DateTime.UtcNow,
    version = "1.0.0"
}))
.WithName("HealthCheck");

// =============================================
// ENDPOINT: Setup Database
// =============================================
app.MapPost("/api/setup/database", async () =>
{
    try
    {
        var setupService = new DatabaseSetupService(connectionStringRMF);
        var success = await setupService.SetupDatabaseAsync();

        if (success)
        {
            var counts = await setupService.GetTableCountsAsync();

            return Results.Ok(new
            {
                message = "Base de datos configurada exitosamente",
                tableCounts = counts
            });
        }

        return Results.Problem("Error al configurar la base de datos");
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("SetupDatabase");

// =============================================
// ENDPOINT: Test IDENTITY_INSERT Direct
// =============================================
app.MapPost("/api/test/identity-insert", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var sql = @"
SET IDENTITY_INSERT dbo.ConfiguracionCompania ON;

DELETE FROM dbo.ConfiguracionCompania WHERE ID_Compania IN (123, 188);

INSERT INTO dbo.ConfiguracionCompania (ID_Compania, Nombre_Compania, Nombre_Corto, ConnectionString_Actif, Activo, UsuarioCreacion)
VALUES (123, 'CIMA', 'CIMA', 'Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;', 1, 'Sistema');

INSERT INTO dbo.ConfiguracionCompania (ID_Compania, Nombre_Compania, Nombre_Corto, ConnectionString_Actif, Activo, UsuarioCreacion)
VALUES (188, 'Compañia Prueba 188', 'CP188', 'Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;', 1, 'Sistema');

SET IDENTITY_INSERT dbo.ConfiguracionCompania OFF;

SELECT COUNT(*) FROM dbo.ConfiguracionCompania WHERE ID_Compania IN (123, 188);";

        using var command = new SqlCommand(sql, connection);
        command.CommandTimeout = 120;
        var count = (int)await command.ExecuteScalarAsync();

        return Results.Ok(new {
            message = "Test ejecutado exitosamente",
            companiesInserted = count
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}\n\nStack: {ex.StackTrace}");
    }
})
.WithName("TestIdentityInsert");

// =============================================
// ENDPOINT: Ejecutar ETL
// =============================================
app.MapPost("/api/etl/ejecutar", async (ETLRequest request) =>
{
    var loteImportacion = Guid.NewGuid();

    try
    {
        // Start ETL in background and return loteImportacion immediately
        var etlService = new ETLService(connectionStringRMF);

        // MODO PRUEBA: Limitar a 500 registros si no se especifica
        var maxRegistros = request.MaxRegistros ?? 500;

        // Run ETL in background task (fire and forget with proper error handling)
        _ = Task.Run(async () =>
        {
            try
            {
                await etlService.EjecutarETLAsync(
                    request.IdCompania,
                    request.AñoCalculo,
                    request.Usuario ?? "Web",
                    maxRegistros,
                    loteImportacion);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error en ETL background task: {ex.Message}");
            }
        });

        // Return immediately with loteImportacion for progress tracking
        return Results.Ok(new
        {
            message = "ETL iniciado",
            loteImportacion = loteImportacion,
            idCompania = request.IdCompania,
            añoCalculo = request.AñoCalculo
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("EjecutarETL");

// =============================================
// ENDPOINT: Obtener Progreso ETL
// =============================================
app.MapGet("/api/etl/progreso/{loteImportacion:guid}", async (Guid loteImportacion) =>
{
    try
    {
        Console.WriteLine($"[DEBUG] Buscando progreso para lote: {loteImportacion}");

        // Consultar progreso desde la base de datos (para ETL .NET standalone)
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT TOP 1
                Lote_Importacion,
                Registros_Procesados,
                Registros_Exitosos,
                Estado,
                Fecha_Inicio,
                Fecha_Fin
            FROM dbo.Log_Ejecucion_ETL
            WHERE Lote_Importacion = @Lote
              AND Tipo_Proceso = 'ETL_NET'
            ORDER BY Fecha_Inicio DESC";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Lote", loteImportacion);

        using var reader = await command.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
        {
            Console.WriteLine($"[DEBUG] No se encontró registro en BD para lote: {loteImportacion}");
            return Results.NotFound(new { message = "No se encontró progreso para este lote" });
        }

        Console.WriteLine($"[DEBUG] Registro encontrado, Estado: {reader.GetString(3)}");

        var registrosProcesados = reader.IsDBNull(1) ? 0 : reader.GetInt32(1);
        var registrosExitosos = reader.IsDBNull(2) ? 0 : reader.GetInt32(2);
        var estado = reader.GetString(3);
        var fechaInicio = reader.GetDateTime(4);
        DateTime? fechaFin = reader.IsDBNull(5) ? null : reader.GetDateTime(5);

        Console.WriteLine($"[DEBUG] Registros_Procesados: {registrosProcesados}, Registros_Exitosos: {registrosExitosos}");

        // CORREGIDO:
        // - Registros_Procesados: progreso actual (se actualiza cada 250 registros durante el proceso)
        // - Registros_Exitosos: total de registros a procesar (se establece al inicio después de extraer)
        return Results.Ok(new
        {
            loteImportacion = loteImportacion,
            registrosInsertados = registrosProcesados,  // Progreso actual
            totalRegistros = registrosExitosos,  // Total establecido al inicio
            estado = estado,
            fechaInicio = fechaInicio,
            fechaFin = fechaFin
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ObtenerProgresoETL");

// =============================================
// ENDPOINT: Limpiar procesos huérfanos "En Proceso"
// =============================================
app.MapPost("/api/etl/limpiar-huerfanos", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            UPDATE dbo.Log_Ejecucion_ETL
            SET Estado = 'Error',
                Fecha_Fin = GETDATE(),
                Duracion_Segundos = DATEDIFF(SECOND, Fecha_Inicio, GETDATE())
            WHERE Estado = 'En Proceso'
              AND Fecha_Inicio < DATEADD(MINUTE, -10, GETDATE());

            SELECT @@ROWCOUNT AS Registros_Actualizados;";

        using var command = new SqlCommand(query, connection);
        var count = (int)await command.ExecuteScalarAsync();

        return Results.Ok(new {
            message = $"Se limpiaron {count} registros huérfanos",
            registrosLimpiados = count
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("LimpiarHuerfanos");

// =============================================
// ENDPOINT: Historial de Extracciones ETL
// =============================================
app.MapGet("/api/etl/historial", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT TOP 20
                l.ID_Log,
                l.ID_Compania,
                c.Nombre_Compania,
                l.Año_Calculo,
                l.Lote_Importacion,
                l.Fecha_Inicio,
                l.Fecha_Fin,
                l.Duracion_Segundos,
                l.Registros_Procesados,
                l.Estado
            FROM dbo.Log_Ejecucion_ETL l
            INNER JOIN dbo.ConfiguracionCompania c ON l.ID_Compania = c.ID_Compania
            WHERE l.Tipo_Proceso IN ('ETL', 'ETL_NET')
            ORDER BY l.Fecha_Inicio DESC";

        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        var historial = new List<object>();
        while (await reader.ReadAsync())
        {
            historial.Add(new
            {
                idLog = reader.GetInt64(0),
                idCompania = reader.GetInt32(1),
                nombreCompania = reader.GetString(2),
                añoCalculo = reader.GetInt32(3),
                loteImportacion = reader.GetGuid(4),
                fechaInicio = reader.GetDateTime(5),
                fechaFin = reader.IsDBNull(6) ? (DateTime?)null : reader.GetDateTime(6),
                duracionSegundos = reader.IsDBNull(7) ? (int?)null : reader.GetInt32(7),
                registrosProcesados = reader.IsDBNull(8) ? (int?)null : reader.GetInt32(8),
                estado = reader.GetString(9)
            });
        }

        return Results.Ok(historial);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("HistorialETL");

// =============================================
// ENDPOINT: Ejecutar Cálculo (fire-and-forget)
// =============================================
app.MapPost("/api/calculo/ejecutar", async (CalculoRequest request) =>
{
    var loteCalculo = Guid.NewGuid();

    try
    {
        var etlService = new ETLService(connectionStringRMF);

        // Run cálculo in background task (fire and forget with proper error handling)
        _ = Task.Run(async () =>
        {
            try
            {
                await etlService.EjecutarCalculoAsync(
                    request.IdCompania,
                    request.AñoCalculo,
                    request.LoteImportacion,
                    request.Usuario ?? "Web",
                    loteCalculo);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error en Cálculo background task: {ex.Message}");
            }
        });

        // Return immediately with loteCalculo for progress tracking
        return Results.Ok(new
        {
            message = "Cálculo iniciado",
            loteCalculo = loteCalculo,
            idCompania = request.IdCompania,
            añoCalculo = request.AñoCalculo,
            loteImportacion = request.LoteImportacion
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("EjecutarCalculo");

// =============================================
// ENDPOINT: Obtener Progreso Cálculo
// =============================================
app.MapGet("/api/calculo/progreso/{loteCalculo:guid}", (Guid loteCalculo) =>
{
    try
    {
        var progreso = ETLService.ObtenerProgresoCalculo(loteCalculo);

        if (progreso == null)
        {
            return Results.NotFound(new { message = "No se encontró progreso para este lote de cálculo" });
        }

        return Results.Ok(new
        {
            loteCalculo = progreso.LoteCalculo,
            registrosCalculados = progreso.RegistrosCalculados,
            totalValorReportable = progreso.TotalValorReportable,
            activosCon10PctMOI = progreso.ActivosCon10PctMOI,
            estado = progreso.Estado,
            fechaInicio = progreso.FechaInicio,
            fechaFin = progreso.FechaFin
        });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ObtenerProgresoCalculo");

// =============================================
// ENDPOINT: Historial de Cálculos
// =============================================
app.MapGet("/api/calculo/historial", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT TOP 20
                l.ID_Log,
                l.ID_Compania,
                c.Nombre_Compania,
                l.Año_Calculo,
                l.Lote_Importacion,
                l.Fecha_Inicio,
                l.Fecha_Fin,
                l.Duracion_Segundos,
                l.Registros_Procesados,
                l.Estado
            FROM dbo.Log_Ejecucion_ETL l
            INNER JOIN dbo.ConfiguracionCompania c ON l.ID_Compania = c.ID_Compania
            WHERE l.Tipo_Proceso = 'CALCULO'
            ORDER BY l.Fecha_Inicio DESC";

        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        var historial = new List<object>();
        while (await reader.ReadAsync())
        {
            historial.Add(new
            {
                idLog = reader.GetInt64(0),
                idCompania = reader.GetInt32(1),
                nombreCompania = reader.GetString(2),
                añoCalculo = reader.GetInt32(3),
                loteCalculo = reader.GetGuid(4),
                fechaInicio = reader.GetDateTime(5),
                fechaFin = reader.IsDBNull(6) ? (DateTime?)null : reader.GetDateTime(6),
                duracionSegundos = reader.IsDBNull(7) ? (int?)null : reader.GetInt32(7),
                registrosProcesados = reader.IsDBNull(8) ? (int?)null : reader.GetInt32(8),
                estado = reader.GetString(9)
            });
        }

        return Results.Ok(historial);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("HistorialCalculo");

// =============================================
// ENDPOINT: Lotes disponibles para cálculo
// =============================================
app.MapGet("/api/calculo/lotes-disponibles/{idCompania}/{año}", async (int idCompania, int año) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                l.Lote_Importacion,
                l.Fecha_Inicio,
                l.Registros_Procesados
            FROM dbo.Log_Ejecucion_ETL l
            WHERE l.ID_Compania = @IdCompania
              AND l.Año_Calculo = @Año
              AND l.Tipo_Proceso IN ('ETL', 'ETL_NET')
              AND l.Estado = 'Completado'
            ORDER BY l.Fecha_Inicio DESC";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@IdCompania", idCompania);
        command.Parameters.AddWithValue("@Año", año);

        using var reader = await command.ExecuteReaderAsync();

        var lotes = new List<object>();
        while (await reader.ReadAsync())
        {
            lotes.Add(new
            {
                loteImportacion = reader.GetGuid(0),
                fechaImportacion = reader.GetDateTime(1),
                totalRegistros = reader.GetInt32(2)
            });
        }

        return Results.Ok(lotes);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("LotesDisponiblesCalculo");

// =============================================
// ENDPOINT: Obtener Resultado del Cálculo
// =============================================
app.MapGet("/api/calculo/resultado/{idCompania}/{añoCalculo}", async (int idCompania, int añoCalculo) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        // Obtener último cálculo
        var query = @"
            SELECT TOP 1
                c.Lote_Calculo,
                c.Fecha_Calculo,
                COUNT(*) AS Total_Activos,
                SUM(c.Valor_Reportable_MXN) AS Total_Valor_Reportable,
                SUM(CASE WHEN c.Tipo_Activo = 'Extranjero' THEN 1 ELSE 0 END) AS Activos_Extranjeros,
                SUM(CASE WHEN c.Tipo_Activo = 'Mexicano' THEN 1 ELSE 0 END) AS Activos_Mexicanos,
                SUM(CASE WHEN c.Aplica_10_Pct = 1 THEN 1 ELSE 0 END) AS Activos_Con_10_Pct
            FROM dbo.Calculo_RMF c
            WHERE c.ID_Compania = @IdCompania
              AND c.Año_Calculo = @AñoCalculo
            GROUP BY c.Lote_Calculo, c.Fecha_Calculo
            ORDER BY c.Fecha_Calculo DESC";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@IdCompania", idCompania);
        command.Parameters.AddWithValue("@AñoCalculo", añoCalculo);

        using var reader = await command.ExecuteReaderAsync();

        if (await reader.ReadAsync())
        {
            return Results.Ok(new
            {
                loteCalculo = reader.GetGuid(0),
                fechaCalculo = reader.GetDateTime(1),
                totalActivos = reader.GetInt32(2),
                totalValorReportable = reader.GetDecimal(3),
                activosExtranjeros = reader.GetInt32(4),
                activosMexicanos = reader.GetInt32(5),
                activosCon10Pct = reader.GetInt32(6)
            });
        }

        return Results.NotFound(new { message = "No se encontraron cálculos" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ObtenerResultadoCalculo");

// =============================================
// ENDPOINT: Analizar Excel (ya existente)
// =============================================
app.MapGet("/analizar-excel", () =>
{
    try
    {
        var excelPath = "/Users/enrique/ActifRMF/Propuesta reporte Calculo AF.xlsx";
        var analyzer = new ExcelAnalyzer();

        Console.WriteLine("\n\n");
        analyzer.AnalyzeExcelFile(excelPath);
        Console.WriteLine("\n\n");

        return Results.Ok(new { message = "Análisis completado. Revisa la consola para ver los resultados." });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error al analizar el archivo: {ex.Message}");
    }
})
.WithName("AnalizarExcel");

// =============================================
// ENDPOINTS CRUD: Compañías
// =============================================

// GET: Listar todas las compañías (filtrado: solo IDs específicas)
app.MapGet("/api/companias", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        // Filtrar solo compañías permitidas: 122, 123, 188, 1000, 1001, 1500, 12
        var query = @"SELECT * FROM dbo.ConfiguracionCompania
                      WHERE ID_Compania IN (12, 122, 123, 188, 1000, 1001, 1500)
                      ORDER BY ID_Compania";
        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        var companias = new List<object>();
        while (await reader.ReadAsync())
        {
            companias.Add(new
            {
                idConfiguracion = reader.GetInt32(reader.GetOrdinal("ID_Configuracion")),
                idCompania = reader.GetInt32(reader.GetOrdinal("ID_Compania")),
                nombreCompania = reader.GetString(reader.GetOrdinal("Nombre_Compania")),
                nombreCorto = reader.GetString(reader.GetOrdinal("Nombre_Corto")),
                connectionString = reader.GetString(reader.GetOrdinal("ConnectionString_Actif")),
                activo = reader.GetBoolean(reader.GetOrdinal("Activo"))
            });
        }

        return Results.Ok(companias);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ListarCompanias");

// GET: Obtener una compañía por ID
app.MapGet("/api/companias/{id}", async (int id) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = "SELECT * FROM dbo.ConfiguracionCompania WHERE ID_Configuracion = @Id";
        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Id", id);

        using var reader = await command.ExecuteReaderAsync();

        if (await reader.ReadAsync())
        {
            return Results.Ok(new
            {
                idConfiguracion = reader.GetInt32(reader.GetOrdinal("ID_Configuracion")),
                idCompania = reader.GetInt32(reader.GetOrdinal("ID_Compania")),
                nombreCompania = reader.GetString(reader.GetOrdinal("Nombre_Compania")),
                nombreCorto = reader.GetString(reader.GetOrdinal("Nombre_Corto")),
                connectionString = reader.GetString(reader.GetOrdinal("ConnectionString_Actif")),
                activo = reader.GetBoolean(reader.GetOrdinal("Activo"))
            });
        }

        return Results.NotFound(new { message = "Compañía no encontrada" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ObtenerCompania");

// POST: Crear nueva compañía
app.MapPost("/api/companias", async (CompaniaRequest request) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            INSERT INTO dbo.ConfiguracionCompania
                (ID_Compania, Nombre_Compania, Nombre_Corto, ConnectionString_Actif, Activo)
            VALUES
                (@IdCompania, @NombreCompania, @NombreCorto, @ConnectionString, @Activo);
            SELECT CAST(SCOPE_IDENTITY() AS INT);";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@IdCompania", request.IdCompania);
        command.Parameters.AddWithValue("@NombreCompania", request.NombreCompania);
        command.Parameters.AddWithValue("@NombreCorto", request.NombreCorto);
        command.Parameters.AddWithValue("@ConnectionString", request.ConnectionString);
        command.Parameters.AddWithValue("@Activo", request.Activo);

        var newId = (int)await command.ExecuteScalarAsync();

        return Results.Ok(new { message = "Compañía creada exitosamente", id = newId });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("CrearCompania");

// PUT: Actualizar compañía existente
app.MapPut("/api/companias/{id}", async (int id, CompaniaRequest request) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            UPDATE dbo.ConfiguracionCompania
            SET ID_Compania = @IdCompania,
                Nombre_Compania = @NombreCompania,
                Nombre_Corto = @NombreCorto,
                ConnectionString_Actif = @ConnectionString,
                Activo = @Activo
            WHERE ID_Configuracion = @Id";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Id", id);
        command.Parameters.AddWithValue("@IdCompania", request.IdCompania);
        command.Parameters.AddWithValue("@NombreCompania", request.NombreCompania);
        command.Parameters.AddWithValue("@NombreCorto", request.NombreCorto);
        command.Parameters.AddWithValue("@ConnectionString", request.ConnectionString);
        command.Parameters.AddWithValue("@Activo", request.Activo);

        var rowsAffected = await command.ExecuteNonQueryAsync();

        if (rowsAffected > 0)
            return Results.Ok(new { message = "Compañía actualizada exitosamente" });
        else
            return Results.NotFound(new { message = "Compañía no encontrada" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ActualizarCompania");

// DELETE: Eliminar compañía
app.MapDelete("/api/companias/{id}", async (int id) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = "DELETE FROM dbo.ConfiguracionCompania WHERE ID_Configuracion = @Id";
        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Id", id);

        var rowsAffected = await command.ExecuteNonQueryAsync();

        if (rowsAffected > 0)
            return Results.Ok(new { message = "Compañía eliminada exitosamente" });
        else
            return Results.NotFound(new { message = "Compañía no encontrada" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("EliminarCompania");

// =============================================
// ENDPOINT: Actualizar INPC
// =============================================
app.MapPost("/api/inpc/actualizar", async (int? idGrupoSimulacion) =>
{
    try
    {
        var inpcService = new INPCService(connectionStringRMF);
        var result = await inpcService.ActualizarINPCAsync(idGrupoSimulacion, "Web");

        if (result.Exitoso)
        {
            return Results.Ok(new
            {
                message = idGrupoSimulacion.HasValue
                    ? $"INPC actualizado exitosamente (Grupo {idGrupoSimulacion.Value})"
                    : "INPC actualizado exitosamente",
                registrosImportados = result.RegistrosImportados,
                duracionSegundos = result.DuracionSegundos,
                loteImportacion = result.LoteImportacion,
                idGrupoSimulacion = result.IdGrupoSimulacion
            });
        }

        return Results.Problem(result.MensajeError ?? "Error desconocido al actualizar INPC");
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ActualizarINPC");

// =============================================
// ENDPOINT: Estadísticas INPC
// =============================================
app.MapGet("/api/inpc/estadisticas", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                COUNT(*) AS Total_Registros,
                COUNT(DISTINCT Anio) AS Total_Años,
                MIN(Anio) AS Año_Minimo,
                MAX(Anio) AS Año_Maximo,
                MAX(Fecha_Importacion) AS Ultima_Importacion
            FROM dbo.INPC_Importado";

        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        if (await reader.ReadAsync())
        {
            return Results.Ok(new
            {
                totalRegistros = reader.GetInt32(0),
                años = reader.GetInt32(1),
                añoMinimo = reader.GetInt32(2),
                añoMaximo = reader.GetInt32(3),
                ultimaImportacion = reader.GetDateTime(4)
            });
        }

        return Results.NotFound(new { message = "No hay datos de INPC disponibles" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("EstadisticasINPC");

// =============================================
// ENDPOINT: Datos INPC Recientes
// =============================================
app.MapGet("/api/inpc/recientes", async () =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT TOP 50
                Anio,
                Mes,
                Indice,
                Fecha_Importacion
            FROM dbo.INPC_Importado
            ORDER BY Anio DESC, Mes DESC";

        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        var datos = new List<object>();
        while (await reader.ReadAsync())
        {
            datos.Add(new
            {
                anio = reader.GetInt32(0),
                mes = reader.GetInt32(1),
                indice = reader.GetDecimal(2),
                fechaImportacion = reader.GetDateTime(3)
            });
        }

        return Results.Ok(datos);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("DatosINPCRecientes");

// =============================================
// ENDPOINT: Dashboard - Status por compañía y año
// =============================================
app.MapGet("/api/dashboard/{año}", async (int año) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                cc.ID_Compania,
                cc.Nombre_Compania,
                cc.Nombre_Corto,
                ISNULL(e.Total_Registros_ETL, 0) AS Total_Registros_ETL,
                e.Fecha_ETL,
                ISNULL(c.Total_Registros_Calculo, 0) AS Total_Registros_Calculo,
                ISNULL(c.Total_MOI, 0) AS Total_MOI,
                ISNULL(c.Total_Saldo_Pendiente, 0) AS Total_Saldo_Pendiente,
                ISNULL(c.Total_Valor_Reportable, 0) AS Total_Valor_Reportable,
                ISNULL(c.Activos_Con_10Pct, 0) AS Activos_Con_10Pct,
                c.Fecha_Calculo,
                c.Lote_Calculo,
                CASE
                    WHEN c.Total_Registros_Calculo IS NULL OR c.Total_Registros_Calculo = 0 THEN 'Pendiente'
                    ELSE 'Completado'
                END AS Estado
            FROM dbo.ConfiguracionCompania cc
            LEFT JOIN (
                SELECT
                    ID_Compania,
                    COUNT(*) AS Total_Registros_ETL,
                    MAX(Fecha_Importacion) AS Fecha_ETL
                FROM dbo.Staging_Activo
                WHERE Año_Calculo = @Año
                GROUP BY ID_Compania
            ) e ON cc.ID_Compania = e.ID_Compania
            LEFT JOIN (
                SELECT
                    c.ID_Compania,
                    COUNT(*) AS Total_Registros_Calculo,
                    SUM(c.MOI) AS Total_MOI,
                    SUM(c.Monto_Pendiente) AS Total_Saldo_Pendiente,
                    SUM(c.Valor_Reportable_MXN) AS Total_Valor_Reportable,
                    SUM(CASE WHEN c.Aplica_10_Pct = 1 THEN 1 ELSE 0 END) AS Activos_Con_10Pct,
                    MAX(c.Fecha_Calculo) AS Fecha_Calculo,
                    MAX(c.Lote_Calculo) AS Lote_Calculo
                FROM dbo.Calculo_RMF c
                WHERE c.Año_Calculo = @Año
                GROUP BY c.ID_Compania
            ) c ON cc.ID_Compania = c.ID_Compania
            WHERE cc.Activo = 1
            ORDER BY cc.Nombre_Compania";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Año", año);

        using var reader = await command.ExecuteReaderAsync();

        var resultados = new List<object>();
        while (await reader.ReadAsync())
        {
            resultados.Add(new
            {
                idCompania = reader.GetInt32(0),
                nombreCompania = reader.GetString(1),
                nombreCorto = reader.GetString(2),
                totalRegistrosETL = reader.GetInt32(3),
                fechaETL = reader.IsDBNull(4) ? (DateTime?)null : reader.GetDateTime(4),
                totalRegistrosCalculo = reader.GetInt32(5),
                totalMOI = reader.GetDecimal(6),
                totalSaldoPendiente = reader.GetDecimal(7),
                totalValorReportable = reader.GetDecimal(8),
                activosCon10Pct = reader.GetInt32(9),
                fechaCalculo = reader.IsDBNull(10) ? (DateTime?)null : reader.GetDateTime(10),
                loteCalculo = reader.IsDBNull(11) ? (Guid?)null : reader.GetGuid(11),
                estado = reader.GetString(12)
            });
        }

        return Results.Ok(resultados);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("Dashboard");

// =============================================
// ENDPOINT: Obtener datos de reporte
// =============================================
app.MapGet("/api/reporte/{idCompania}/{añoCalculo}", async (int idCompania, int añoCalculo) =>
{
    try
    {
        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                c.ID_Calculo,
                c.ID_NUM_ACTIVO,
                s.ID_ACTIVO AS Placa,
                s.DESCRIPCION,
                s.Nombre_TipoActivo,
                s.Nombre_Pais,
                c.Ruta_Calculo,
                c.Descripcion_Ruta,
                c.MOI,
                c.INPC_Adqu,
                c.INPC_Mitad_Ejercicio,
                c.INPC_Mitad_Periodo,
                c.Meses_Uso_Inicio_Ejercicio,
                c.Meses_Uso_Hasta_Mitad_Periodo,
                c.Meses_Uso_En_Ejercicio,
                c.Saldo_Inicio_Año,
                c.Dep_Fiscal_Ejercicio,
                c.Monto_Pendiente,
                c.Proporcion,
                c.Prueba_10_Pct_MOI,
                c.Aplica_10_Pct,
                c.Tipo_Cambio_30_Junio,
                c.Valor_Reportable_MXN,
                c.Tasa_Anual,
                c.Dep_Anual,
                c.Valor_Reportable_USD,
                s.FECHA_COMPRA AS Fecha_Adquisicion,
                s.FECHA_BAJA AS Fecha_Baja,
                c.Observaciones,
                c.Fecha_Calculo,
                c.Lote_Calculo
            FROM dbo.Calculo_RMF c
            INNER JOIN dbo.Staging_Activo s ON c.ID_Staging = s.ID_Staging
            WHERE c.ID_Compania = @IdCompania
              AND c.Año_Calculo = @AñoCalculo
            ORDER BY c.ID_NUM_ACTIVO";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@IdCompania", idCompania);
        command.Parameters.AddWithValue("@AñoCalculo", añoCalculo);

        using var reader = await command.ExecuteReaderAsync();

        var resultados = new List<object>();
        while (await reader.ReadAsync())
        {
            resultados.Add(new
            {
                idCalculo = reader.GetInt64(0),
                idNumActivo = reader.GetInt32(1),
                placa = reader.IsDBNull(2) ? null : reader.GetString(2),
                descripcion = reader.IsDBNull(3) ? null : reader.GetString(3),
                tipoActivo = reader.IsDBNull(4) ? null : reader.GetString(4),
                pais = reader.IsDBNull(5) ? null : reader.GetString(5),
                rutaCalculo = reader.GetString(6),
                descripcionRuta = reader.GetString(7),
                moi = reader.GetDecimal(8),
                inpcAdquisicion = reader.IsDBNull(9) ? (decimal?)null : reader.GetDecimal(9),
                inpcMitadEjercicio = reader.IsDBNull(10) ? (decimal?)null : reader.GetDecimal(10),
                inpcMitadPeriodo = reader.IsDBNull(11) ? (decimal?)null : reader.GetDecimal(11),
                mesesInicio = reader.GetInt32(12),
                mesesMitad = reader.GetInt32(13),
                mesesEjercicio = reader.GetInt32(14),
                saldoInicio = reader.GetDecimal(15),
                depEjercicio = reader.GetDecimal(16),
                montoPendiente = reader.IsDBNull(17) ? (decimal?)null : reader.GetDecimal(17),
                proporcion = reader.IsDBNull(18) ? (decimal?)null : reader.GetDecimal(18),
                prueba10Pct = reader.IsDBNull(19) ? (decimal?)null : reader.GetDecimal(19),
                aplica10Pct = reader.IsDBNull(20) ? (bool?)null : reader.GetBoolean(20),
                tipoCambio = reader.IsDBNull(21) ? (decimal?)null : reader.GetDecimal(21),
                valorReportable = reader.GetDecimal(22),
                tasaAnual = reader.IsDBNull(23) ? (decimal?)null : reader.GetDecimal(23),
                depAnual = reader.IsDBNull(24) ? (decimal?)null : reader.GetDecimal(24),
                valorReportableUSD = reader.IsDBNull(25) ? (decimal?)null : reader.GetDecimal(25),
                fechaAdquisicion = reader.IsDBNull(26) ? (DateTime?)null : reader.GetDateTime(26),
                fechaBaja = reader.IsDBNull(27) ? (DateTime?)null : reader.GetDateTime(27),
                observaciones = reader.IsDBNull(28) ? null : reader.GetString(28),
                fechaCalculo = reader.GetDateTime(29),
                loteCalculo = reader.GetGuid(30)
            });
        }

        return Results.Ok(resultados);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Error: {ex.Message}");
    }
})
.WithName("ObtenerReporte");

app.Run();

// DTOs
public record ETLRequest(int IdCompania, int AñoCalculo, string? Usuario, int? MaxRegistros);
public record CalculoRequest(int IdCompania, int AñoCalculo, Guid LoteImportacion, string? Usuario);
public record CompaniaRequest(int IdCompania, string NombreCompania, string NombreCorto, string ConnectionString, bool Activo);
