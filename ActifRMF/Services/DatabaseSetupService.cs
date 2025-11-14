using Microsoft.Data.SqlClient;
using System.Text;

namespace ActifRMF.Services;

public class DatabaseSetupService
{
    private readonly string _connectionString;

    public DatabaseSetupService(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<bool> SetupDatabaseAsync()
    {
        try
        {
            Console.WriteLine("===========================================");
            Console.WriteLine("CONFIGURACIÓN DE BASE DE DATOS Actif_RMF");
            Console.WriteLine("===========================================\n");

            // Script 1: Create database - must run against 'master'
            // Usar ruta relativa al directorio de la aplicación
            var sqlPath = Path.Combine(Directory.GetCurrentDirectory(), "SQL");
            var createDbScript = Path.Combine(sqlPath, "01_CREATE_DATABASE.sql");
            Console.WriteLine($"Ejecutando: {Path.GetFileName(createDbScript)}");

            if (!File.Exists(createDbScript))
            {
                Console.WriteLine($"  ❌ Archivo no encontrado: {createDbScript}");
                return false;
            }

            // Use connection string without database name (connect to master)
            var builder = new SqlConnectionStringBuilder(_connectionString);
            var masterConnectionString = $"Server={builder.DataSource};User ID={builder.UserID};Password={builder.Password};TrustServerCertificate=True;";

            var sql = await File.ReadAllTextAsync(createDbScript);
            var batches = sql.Split(new[] { "\nGO\n", "\nGO\r\n", "\r\nGO\r\n" },
                StringSplitOptions.RemoveEmptyEntries);

            using (var connection = new SqlConnection(masterConnectionString))
            {
                await connection.OpenAsync();

                foreach (var batch in batches)
                {
                    var cleanBatch = batch.Trim();
                    if (string.IsNullOrWhiteSpace(cleanBatch) || cleanBatch.StartsWith("--"))
                        continue;

                    try
                    {
                        using var command = new SqlCommand(cleanBatch, connection);
                        command.CommandTimeout = 120;
                        await command.ExecuteNonQueryAsync();
                    }
                    catch (Exception ex)
                    {
                        if (!ex.Message.Contains("ya existe") && !ex.Message.Contains("already exists"))
                        {
                            Console.WriteLine($"  ⚠️  Warning: {ex.Message}");
                        }
                    }
                }
            }

            Console.WriteLine($"  ✅ Completado\n");

            // Scripts 0-10: Run against Actif_RMF database
            var scripts = new[]
            {
                Path.Combine(sqlPath, "00_CLEANUP_Calculo_RMF.sql"),
                Path.Combine(sqlPath, "02_CREATE_TABLES.sql"),
                Path.Combine(sqlPath, "03_INSERT_CATALOGOS.sql"),
                Path.Combine(sqlPath, "09_INSERT_COMPANIAS_REALES.sql"), // Compañías con IDs reales (123, 188)
                Path.Combine(sqlPath, "04_SP_ETL_Importar_Activos.sql"),
                Path.Combine(sqlPath, "05_SP_Calcular_RMF_Activos_Extranjeros.sql"),
                // Path.Combine(sqlPath, "06_AJUSTES_TABLAS.sql"), // SKIP: Renombra Calculo_RMF
                Path.Combine(sqlPath, "07_FIX_LOG_DUPLICADOS.sql")
                // Scripts 08, 10 no son necesarios ya que 02 crea la tabla correctamente
            };

            foreach (var scriptPath in scripts)
            {
                Console.WriteLine($"Ejecutando: {Path.GetFileName(scriptPath)}");

                if (!File.Exists(scriptPath))
                {
                    Console.WriteLine($"  ❌ Archivo no encontrado: {scriptPath}");
                    return false;
                }

                sql = await File.ReadAllTextAsync(scriptPath);

                // Improved GO splitting to handle all common line endings
                batches = sql.Split(new[] { "\r\nGO\r\n", "\nGO\n", "\rGO\r", "\nGO\r\n", "\r\nGO\n" },
                    StringSplitOptions.RemoveEmptyEntries);

                using var connection = new SqlConnection(_connectionString);
                await connection.OpenAsync();

                foreach (var batch in batches)
                {
                    var cleanBatch = batch.Trim();
                    if (string.IsNullOrWhiteSpace(cleanBatch))
                        continue;

                    // Skip comment-only batches
                    var lines = cleanBatch.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    if (lines.All(l => l.Trim().StartsWith("--")))
                        continue;

                    try
                    {
                        using var command = new SqlCommand(cleanBatch, connection);
                        command.CommandTimeout = 120;
                        await command.ExecuteNonQueryAsync();
                    }
                    catch (Exception ex)
                    {
                        // Only ignore specific "already exists" errors
                        if (!ex.Message.Contains("ya existe") &&
                            !ex.Message.Contains("already exists") &&
                            !ex.Message.Contains("There is already an object"))
                        {
                            Console.WriteLine($"  ⚠️  Error en batch: {ex.Message}");
                            Console.WriteLine($"  Batch content (first 500 chars): {cleanBatch.Substring(0, Math.Min(500, cleanBatch.Length))}");
                        }
                        else
                        {
                            Console.WriteLine($"  ℹ️  Object already exists (ignored): {ex.Message.Substring(0, Math.Min(100, ex.Message.Length))}");
                        }
                    }
                }

                Console.WriteLine($"  ✅ Completado\n");
            }

            Console.WriteLine("===========================================");
            Console.WriteLine("✅ BASE DE DATOS CONFIGURADA EXITOSAMENTE");
            Console.WriteLine("===========================================\n");

            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\n❌ ERROR: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            return false;
        }
    }

    public async Task<Dictionary<string, int>> GetTableCountsAsync()
    {
        var counts = new Dictionary<string, int>();

        var tables = new[]
        {
            "ConfiguracionCompania",
            "Catalogo_Rutas_Calculo",
            "Tipo_Cambio",
            "Staging_Activo",
            "Calculo_RMF",
            "Control_ETL_Compania",
            "Log_Ejecucion_ETL"
        };

        // Usar connection string con la base de datos Actif_RMF
        var builder = new SqlConnectionStringBuilder(_connectionString)
        {
            InitialCatalog = "Actif_RMF"
        };

        using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync();

        foreach (var table in tables)
        {
            try
            {
                using var command = new SqlCommand(
                    $"SELECT COUNT(*) FROM dbo.{table}", connection);
                var count = (int)await command.ExecuteScalarAsync();
                counts[table] = count;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️  Error counting {table}: {ex.Message}");
                counts[table] = -1; // Tabla no existe
            }
        }

        return counts;
    }
}
