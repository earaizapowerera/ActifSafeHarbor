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

        // Procesar TODOS los registros por defecto (solo limitar si se especifica maxRegistros)
        var maxRegistros = request.MaxRegistros;

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
            añoCalculo = request.AñoCalculo
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

        // Filtrar solo compañías permitidas y contar registros en Staging_Activo
        var query = @"
            SELECT
                cc.ID_Configuracion,
                cc.ID_Compania,
                cc.Nombre_Compania,
                cc.Nombre_Corto,
                cc.ConnectionString_Actif,
                cc.Activo,
                COUNT(sa.ID_Staging) AS TotalRegistros
            FROM dbo.ConfiguracionCompania cc
            LEFT JOIN dbo.Staging_Activo sa ON cc.ID_Compania = sa.ID_Compania
            WHERE cc.ID_Compania IN (12, 122, 123, 188, 1000, 1001, 1500)
            GROUP BY cc.ID_Configuracion, cc.ID_Compania, cc.Nombre_Compania, cc.Nombre_Corto,
                     cc.ConnectionString_Actif, cc.Activo
            ORDER BY cc.ID_Compania";
        using var command = new SqlCommand(query, connection);
        using var reader = await command.ExecuteReaderAsync();

        var companias = new List<object>();
        while (await reader.ReadAsync())
        {
            var nombreCompaniaOrdinal = reader.GetOrdinal("Nombre_Compania");
            var nombreCortoOrdinal = reader.GetOrdinal("Nombre_Corto");
            var connectionStringOrdinal = reader.GetOrdinal("ConnectionString_Actif");
            var activoOrdinal = reader.GetOrdinal("Activo");
            var totalRegistrosOrdinal = reader.GetOrdinal("TotalRegistros");

            companias.Add(new
            {
                idConfiguracion = reader.GetInt32(reader.GetOrdinal("ID_Configuracion")),
                idCompania = reader.GetInt32(reader.GetOrdinal("ID_Compania")),
                nombreCompania = reader.IsDBNull(nombreCompaniaOrdinal) ? "Sin Nombre" : reader.GetString(nombreCompaniaOrdinal),
                nombreCorto = reader.IsDBNull(nombreCortoOrdinal) ? "N/A" : reader.GetString(nombreCortoOrdinal),
                connectionString = reader.IsDBNull(connectionStringOrdinal) ? "" : reader.GetString(connectionStringOrdinal),
                activo = reader.IsDBNull(activoOrdinal) ? false : reader.GetBoolean(activoOrdinal),
                totalRegistros = reader.GetInt32(totalRegistrosOrdinal)
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
            var nombreCompaniaOrdinal = reader.GetOrdinal("Nombre_Compania");
            var nombreCortoOrdinal = reader.GetOrdinal("Nombre_Corto");
            var connectionStringOrdinal = reader.GetOrdinal("ConnectionString_Actif");
            var activoOrdinal = reader.GetOrdinal("Activo");

            return Results.Ok(new
            {
                idConfiguracion = reader.GetInt32(reader.GetOrdinal("ID_Configuracion")),
                idCompania = reader.GetInt32(reader.GetOrdinal("ID_Compania")),
                nombreCompania = reader.IsDBNull(nombreCompaniaOrdinal) ? "Sin Nombre" : reader.GetString(nombreCompaniaOrdinal),
                nombreCorto = reader.IsDBNull(nombreCortoOrdinal) ? "N/A" : reader.GetString(nombreCortoOrdinal),
                connectionString = reader.IsDBNull(connectionStringOrdinal) ? "" : reader.GetString(connectionStringOrdinal),
                activo = reader.IsDBNull(activoOrdinal) ? false : reader.GetBoolean(activoOrdinal)
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
// ENDPOINT: Obtener compañías con registros calculados por año
// =============================================
app.MapGet("/api/reporte/companias-con-registros", async (int? año) =>
{
    try
    {
        if (!año.HasValue)
        {
            return Results.BadRequest(new { error = "Se requiere el parámetro 'año'" });
        }

        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                c.ID_Compania AS idCompania,
                c.Nombre_Compania AS nombreCompania,
                COUNT(calc.ID_Calculo) AS totalRegistros
            FROM ConfiguracionCompania c
            INNER JOIN Calculo_RMF calc ON c.ID_Compania = calc.ID_Compania
            WHERE calc.Año_Calculo = @Año
              AND c.Activo = 1
            GROUP BY c.ID_Compania, c.Nombre_Compania
            HAVING COUNT(calc.ID_Calculo) > 0
            ORDER BY c.Nombre_Compania";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Año", año.Value);

        var companias = new List<object>();
        using var reader = await command.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            companias.Add(new
            {
                idCompania = reader.GetInt32(0),
                nombreCompania = reader.GetString(1),
                totalRegistros = reader.GetInt32(2)
            });
        }

        return Results.Ok(companias);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Error al obtener compañías con registros: {ex.Message}");
        return Results.Problem($"Error al obtener compañías: {ex.Message}");
    }
})
.WithName("ObtenerCompaniasConRegistros");

// =============================================
// ENDPOINT: Obtener compañías con datos importados por año
// =============================================
app.MapGet("/api/calculo/companias-con-datos", async (int? año) =>
{
    try
    {
        if (!año.HasValue)
        {
            return Results.BadRequest(new { error = "Se requiere el parámetro 'año'" });
        }

        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        var query = @"
            SELECT
                c.ID_Compania AS idCompania,
                c.Nombre_Compania AS nombreCompania,
                COUNT(s.ID_Staging) AS totalRegistros
            FROM ConfiguracionCompania c
            INNER JOIN Staging_Activo s ON c.ID_Compania = s.ID_Compania
            WHERE s.Año_Calculo = @Año
              AND c.Activo = 1
            GROUP BY c.ID_Compania, c.Nombre_Compania
            HAVING COUNT(s.ID_Staging) > 0
            ORDER BY c.Nombre_Compania";

        using var command = new SqlCommand(query, connection);
        command.Parameters.AddWithValue("@Año", año.Value);

        var companias = new List<object>();
        using var reader = await command.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            companias.Add(new
            {
                idCompania = reader.GetInt32(0),
                nombreCompania = reader.GetString(1),
                totalRegistros = reader.GetInt32(2)
            });
        }

        return Results.Ok(companias);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Error al obtener compañías con datos importados: {ex.Message}");
        return Results.Problem($"Error al obtener compañías: {ex.Message}");
    }
})
.WithName("ObtenerCompaniasConDatos");

// =============================================
// ENDPOINT: Obtener datos de reporte
// =============================================
app.MapGet("/api/reporte", async (string? companias, int? año) =>
{
    try
    {
        if (string.IsNullOrEmpty(companias) || !año.HasValue)
        {
            return Results.BadRequest(new { error = "Se requieren los parámetros 'companias' y 'año'" });
        }

        // Convertir string de compañías separadas por coma a lista de IDs
        var listaCompanias = companias.Split(',').Select(int.Parse).ToList();
        var companiasParam = string.Join(",", listaCompanias);

        using var connection = new SqlConnection(connectionStringRMF);
        await connection.OpenAsync();

        // Query para ACTIVOS EXTRANJEROS
        var queryExtranjeros = @"
            SELECT
                cc.Nombre_Compania,
                c.ID_Compania,
                c.ID_NUM_ACTIVO AS Folio,
                s.ID_ACTIVO AS Placa,
                s.DESCRIPCION,
                s.Nombre_TipoActivo AS Tipo,
                s.FECHA_COMPRA AS Fecha_Adquisicion,
                s.FECHA_BAJA AS Fecha_Baja,
                c.MOI,
                c.Tasa_Anual AS Anual_Rate,
                c.Tasa_Mensual AS Month_Rate,
                c.Dep_Anual AS Deprec_Anual,
                c.Meses_Uso_Inicio_Ejercicio AS Meses_Uso_Al_Inicio_Ejercicio,
                c.Meses_Uso_Hasta_Mitad_Periodo AS Meses_Uso_Hasta_Mitad_Periodo,
                c.Meses_Uso_En_Ejercicio AS Meses_Uso_En_Ejercicio,
                c.Dep_Acum_Inicio AS Dep_Fiscal_Acumulada_Inicio_Año,
                c.Saldo_Inicio_Año AS Saldo_Por_Deducir_ISR_Al_Inicio_Año,
                c.Dep_Fiscal_Ejercicio AS Depreciacion_Fiscal_Del_Ejercicio,
                c.Monto_Pendiente AS Monto_Pendiente_Por_Deducir,
                c.Proporcion AS Proporcion_Monto_Pendiente_Por_Deducir,
                c.Prueba_10_Pct_MOI AS Prueba_Del_10_Pct_MOI,
                c.Tipo_Cambio_30_Junio AS Tipo_Cambio_30_Junio,
                c.Valor_Reportable_MXN AS Valor_Proporcional_Año_Pesos,
                c.Descripcion_Ruta AS Observaciones
            FROM dbo.Calculo_RMF c
            INNER JOIN dbo.Staging_Activo s ON c.ID_Staging = s.ID_Staging
            INNER JOIN dbo.ConfiguracionCompania cc ON c.ID_Compania = cc.ID_Compania
            WHERE c.ID_Compania IN (" + companiasParam + @")
              AND c.Año_Calculo = @AñoCalculo
              AND c.Tipo_Activo = 'Extranjero'
              AND c.Fecha_Calculo = (
                  SELECT MAX(c2.Fecha_Calculo)
                  FROM dbo.Calculo_RMF c2
                  WHERE c2.ID_Compania = c.ID_Compania
                    AND c2.Año_Calculo = c.Año_Calculo
                    AND c2.Tipo_Activo = c.Tipo_Activo
              )
            ORDER BY cc.Nombre_Compania, c.ID_NUM_ACTIVO";

        // Query para ACTIVOS NACIONALES (MEXICANOS)
        var queryNacionales = @"
            SELECT
                cc.Nombre_Compania,
                c.ID_Compania,
                c.ID_NUM_ACTIVO AS Folio,
                s.ID_ACTIVO AS Placa,
                s.DESCRIPCION,
                s.Nombre_TipoActivo AS Tipo,
                s.FECHA_COMPRA AS Fecha_Adquisicion,
                s.FECHA_BAJA AS Fecha_Baja,
                c.MOI,
                c.Tasa_Anual AS Anual_Rate,
                c.Tasa_Mensual AS Month_Rate,
                c.Dep_Anual AS Deprec_Anual,
                c.Meses_Uso_Inicio_Ejercicio AS Meses_Uso_Al_Ejercicio_Anterior,
                c.Meses_Uso_En_Ejercicio AS Meses_Uso_En_Ejercicio,
                c.Dep_Acum_Inicio AS Dep_Fiscal_Acumulada_Inicio_Año,
                c.Saldo_Inicio_Año AS Saldo_Por_Deducir_ISR_Al_Inicio_Año,
                c.INPC_Adqu AS INPC_Adquisicion,
                c.INPC_Mitad_Ejercicio AS INPC_Mitad_Ejercicio,
                -- Factor de actualización paso 1
                CASE
                    WHEN c.INPC_Adqu > 0 THEN ROUND(c.INPC_Mitad_Ejercicio / c.INPC_Adqu, 4)
                    ELSE NULL
                END AS Factor_Actualizacion_Paso1,
                -- Saldo actualizado paso 1
                CASE
                    WHEN c.INPC_Adqu > 0 THEN c.Saldo_Inicio_Año * ROUND(c.INPC_Mitad_Ejercicio / c.INPC_Adqu, 4)
                    ELSE c.Saldo_Inicio_Año
                END AS Saldo_Actualizado_Paso1,
                c.Dep_Fiscal_Ejercicio AS Depreciacion_Fiscal_Del_Ejercicio,
                c.INPC_Adqu AS INPC_Adqu_Paso2,
                c.INPC_Mitad_Periodo AS INPC_Mitad_Periodo,
                -- Factor de actualización paso 2
                CASE
                    WHEN c.INPC_Adqu > 0 THEN ROUND(c.INPC_Mitad_Periodo / c.INPC_Adqu, 4)
                    ELSE NULL
                END AS Factor_Actualizacion_Paso2,
                -- Depreciación fiscal actualizada
                CASE
                    WHEN c.INPC_Adqu > 0 THEN c.Dep_Fiscal_Ejercicio * ROUND(c.INPC_Mitad_Periodo / c.INPC_Adqu, 4)
                    ELSE c.Dep_Fiscal_Ejercicio
                END AS Depreciacion_Fiscal_Actualizada,
                -- 50% de la depreciación fiscal
                CASE
                    WHEN c.INPC_Adqu > 0 THEN (c.Dep_Fiscal_Ejercicio * ROUND(c.INPC_Mitad_Periodo / c.INPC_Adqu, 4)) * 0.5
                    ELSE c.Dep_Fiscal_Ejercicio * 0.5
                END AS Mitad_Depreciacion_Fiscal,
                -- Valor promedio (paso 3)
                c.Monto_Pendiente AS Valor_Promedio,
                c.Proporcion AS Valor_Promedio_Proporcional_Año,
                c.Prueba_10_Pct_MOI AS Prueba_Del_10_Pct_MOI,
                c.Valor_Reportable_MXN AS Valor_Reportable_Safe_Harbor,
                -- Saldo fiscal histórico y actualizado
                (c.MOI - c.Dep_Acum_Inicio - c.Dep_Fiscal_Ejercicio) AS Saldo_Fiscal_Por_Deducir_Historico,
                CASE
                    WHEN c.INPC_Adqu > 0 THEN (c.MOI - c.Dep_Acum_Inicio - c.Dep_Fiscal_Ejercicio) * ROUND(c.INPC_Mitad_Periodo / c.INPC_Adqu, 4)
                    ELSE (c.MOI - c.Dep_Acum_Inicio - c.Dep_Fiscal_Ejercicio)
                END AS Saldo_Fiscal_Por_Deducir_Actualizado,
                CASE
                    WHEN s.FECHA_BAJA IS NOT NULL THEN 'B'
                    ELSE 'A'
                END AS Estado_Activo_Baja,
                c.Descripcion_Ruta AS Observaciones
            FROM dbo.Calculo_RMF c
            INNER JOIN dbo.Staging_Activo s ON c.ID_Staging = s.ID_Staging
            INNER JOIN dbo.ConfiguracionCompania cc ON c.ID_Compania = cc.ID_Compania
            WHERE c.ID_Compania IN (" + companiasParam + @")
              AND c.Año_Calculo = @AñoCalculo
              AND c.Tipo_Activo = 'Nacional'
              AND c.Fecha_Calculo = (
                  SELECT MAX(c2.Fecha_Calculo)
                  FROM dbo.Calculo_RMF c2
                  WHERE c2.ID_Compania = c.ID_Compania
                    AND c2.Año_Calculo = c.Año_Calculo
                    AND c2.Tipo_Activo = c.Tipo_Activo
              )
            ORDER BY cc.Nombre_Compania, c.ID_NUM_ACTIVO";

        // Ejecutar query para extranjeros
        var extranjeros = new List<object>();
        using (var command = new SqlCommand(queryExtranjeros, connection))
        {
            command.Parameters.AddWithValue("@AñoCalculo", año.Value);

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                extranjeros.Add(new
                {
                    nombreCompania = reader.IsDBNull(0) ? null : reader.GetString(0),
                    idCompania = reader.GetInt32(1),
                    folio = reader.IsDBNull(2) ? (int?)null : reader.GetInt32(2),
                    placa = reader.IsDBNull(3) ? null : reader.GetString(3),
                    descripcion = reader.IsDBNull(4) ? null : reader.GetString(4),
                    tipo = reader.IsDBNull(5) ? null : reader.GetString(5),
                    fechaAdquisicion = reader.IsDBNull(6) ? (DateTime?)null : reader.GetDateTime(6),
                    fechaBaja = reader.IsDBNull(7) ? (DateTime?)null : reader.GetDateTime(7),
                    moi = reader.GetDecimal(8),
                    anualRate = reader.IsDBNull(9) ? (decimal?)null : reader.GetDecimal(9),
                    monthRate = reader.IsDBNull(10) ? (decimal?)null : reader.GetDecimal(10),
                    deprecAnual = reader.IsDBNull(11) ? (decimal?)null : reader.GetDecimal(11),
                    mesesUsoAlInicioEjercicio = reader.GetInt32(12),
                    mesesUsoHastaMitadPeriodo = reader.GetInt32(13),
                    mesesUsoEnEjercicio = reader.GetInt32(14),
                    depFiscalAcumuladaInicioAño = reader.GetDecimal(15),
                    saldoPorDeducirISRAlInicioAño = reader.GetDecimal(16),
                    depreciacionFiscalDelEjercicio = reader.GetDecimal(17),
                    montoPendientePorDeducir = reader.IsDBNull(18) ? (decimal?)null : reader.GetDecimal(18),
                    proporcionMontoPendientePorDeducir = reader.IsDBNull(19) ? (decimal?)null : reader.GetDecimal(19),
                    pruebaDel10PctMOI = reader.IsDBNull(20) ? (decimal?)null : reader.GetDecimal(20),
                    tipoCambio30Junio = reader.IsDBNull(21) ? (decimal?)null : reader.GetDecimal(21),
                    valorProporcionalAñoPesos = reader.GetDecimal(22),
                    observaciones = reader.IsDBNull(23) ? null : reader.GetString(23)
                });
            }
        }

        // Ejecutar query para nacionales
        var nacionales = new List<object>();
        using (var command = new SqlCommand(queryNacionales, connection))
        {
            command.Parameters.AddWithValue("@AñoCalculo", año.Value);

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                nacionales.Add(new
                {
                    nombreCompania = reader.IsDBNull(0) ? null : reader.GetString(0),
                    idCompania = reader.GetInt32(1),
                    folio = reader.IsDBNull(2) ? (int?)null : reader.GetInt32(2),
                    placa = reader.IsDBNull(3) ? null : reader.GetString(3),
                    descripcion = reader.IsDBNull(4) ? null : reader.GetString(4),
                    tipo = reader.IsDBNull(5) ? null : reader.GetString(5),
                    fechaAdquisicion = reader.IsDBNull(6) ? (DateTime?)null : reader.GetDateTime(6),
                    fechaBaja = reader.IsDBNull(7) ? (DateTime?)null : reader.GetDateTime(7),
                    moi = reader.GetDecimal(8),
                    anualRate = reader.IsDBNull(9) ? (decimal?)null : reader.GetDecimal(9),
                    monthRate = reader.IsDBNull(10) ? (decimal?)null : reader.GetDecimal(10),
                    deprecAnual = reader.IsDBNull(11) ? (decimal?)null : reader.GetDecimal(11),
                    mesesUsoAlEjercicioAnterior = reader.GetInt32(12),
                    mesesUsoEnEjercicio = reader.GetInt32(13),
                    depFiscalAcumuladaInicioAño = reader.GetDecimal(14),
                    saldoPorDeducirISRAlInicioAño = reader.GetDecimal(15),
                    inpcAdquisicion = reader.IsDBNull(16) ? (decimal?)null : reader.GetDecimal(16),
                    inpcMitadEjercicio = reader.IsDBNull(17) ? (decimal?)null : reader.GetDecimal(17),
                    factorActualizacionPaso1 = reader.IsDBNull(18) ? (decimal?)null : reader.GetDecimal(18),
                    saldoActualizadoPaso1 = reader.IsDBNull(19) ? (decimal?)null : reader.GetDecimal(19),
                    depreciacionFiscalDelEjercicio = reader.GetDecimal(20),
                    inpcAdquPaso2 = reader.IsDBNull(21) ? (decimal?)null : reader.GetDecimal(21),
                    inpcMitadPeriodo = reader.IsDBNull(22) ? (decimal?)null : reader.GetDecimal(22),
                    factorActualizacionPaso2 = reader.IsDBNull(23) ? (decimal?)null : reader.GetDecimal(23),
                    depreciacionFiscalActualizada = reader.IsDBNull(24) ? (decimal?)null : reader.GetDecimal(24),
                    mitadDepreciacionFiscal = reader.IsDBNull(25) ? (decimal?)null : reader.GetDecimal(25),
                    valorPromedio = reader.IsDBNull(26) ? (decimal?)null : reader.GetDecimal(26),
                    valorPromedioProporcionalAño = reader.IsDBNull(27) ? (decimal?)null : reader.GetDecimal(27),
                    saldoFiscalPorDeducirHistorico = reader.IsDBNull(28) ? (decimal?)null : reader.GetDecimal(28),
                    saldoFiscalPorDeducirActualizado = reader.IsDBNull(29) ? (decimal?)null : reader.GetDecimal(29),
                    estadoActivoBaja = reader.IsDBNull(30) ? null : reader.GetString(30),
                    observaciones = reader.IsDBNull(31) ? null : reader.GetString(31)
                });
            }
        }

        return Results.Ok(new
        {
            extranjeros = extranjeros,
            nacionales = nacionales,
            totales = new
            {
                totalExtranjeros = extranjeros.Count,
                totalNacionales = nacionales.Count,
                totalGeneral = extranjeros.Count + nacionales.Count
            }
        });
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
public record CalculoRequest(int IdCompania, int AñoCalculo, string? Usuario);
public record CompaniaRequest(int IdCompania, string NombreCompania, string NombreCorto, string ConnectionString, bool Activo);
