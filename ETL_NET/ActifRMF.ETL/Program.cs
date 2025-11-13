using Microsoft.Data.SqlClient;
using System.Data;

namespace ActifRMF.ETL;

class Program
{
    static async Task Main(string[] args)
    {
        Console.WriteLine("===========================================");
        Console.WriteLine("ETL ACTIF RMF - IMPORTACIÓN DE ACTIVOS");
        Console.WriteLine("===========================================");
        Console.WriteLine();

        // Parámetros
        int idCompania = args.Length > 0 ? int.Parse(args[0]) : 122;
        int añoCalculo = args.Length > 1 ? int.Parse(args[1]) : 2024;
        int? limiteRegistros = null;
        Guid? loteImportacion = null;

        // Buscar parámetros opcionales
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--limit" && i + 1 < args.Length)
            {
                limiteRegistros = int.Parse(args[i + 1]);
            }
            else if (args[i] == "--lote" && i + 1 < args.Length)
            {
                loteImportacion = Guid.Parse(args[i + 1]);
            }
        }

        Console.WriteLine($"Compañía: {idCompania}");
        Console.WriteLine($"Año: {añoCalculo}");
        if (limiteRegistros.HasValue)
            Console.WriteLine($"Límite: {limiteRegistros.Value} registros (TEST MODE)");
        Console.WriteLine();

        var etl = new ETLActivos();
        await etl.EjecutarETL(idCompania, añoCalculo, limiteRegistros, loteImportacion);

        Console.WriteLine();
        Console.WriteLine("Proceso completado.");

        // Solo esperar tecla si no es modo test
        // COMENTADO para permitir ejecución automatizada
        // if (!limiteRegistros.HasValue)
        // {
        //     Console.WriteLine("Presiona cualquier tecla para salir...");
        //     Console.ReadKey();
        // }
    }
}

public class ETLActivos
{
    // Connection string DESTINO (Actif_RMF) - siempre la misma
    private const string ConnStrDestino = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

    // Connection string ORIGEN - se obtiene dinámicamente de ConfiguracionCompania por compañía
    // (Eliminado hardcoded, ahora se lee desde BD)

    public async Task EjecutarETL(int idCompania, int añoCalculo, int? limiteRegistros = null, Guid? loteParam = null)
    {
        Guid loteImportacion = loteParam ?? Guid.NewGuid();
        DateTime fechaInicio = DateTime.Now;
        int registrosProcesados = 0;

        try
        {
            // 0. Obtener configuración de la compañía (ConnectionString + Query)
            Console.WriteLine("Obteniendo configuración de la compañía...");
            var (connectionStringOrigen, queryETL, nombreCompania) = await ObtenerConfiguracionCompania(idCompania);

            // 1. Verificar y eliminar constraint de unicidad (si existe)
            await EliminarConstraintUnicidad();

            // 2. Limpiar datos previos de staging para esta compañía/año
            await LimpiarStagingPrevio(idCompania, añoCalculo);

            // 3. Obtener tipo de cambio del 30 de junio
            decimal tipoCambio30Junio = await ObtenerTipoCambio30Junio(añoCalculo);
            Console.WriteLine($"Tipo de cambio 30-Jun-{añoCalculo}: {tipoCambio30Junio:N6}");
            Console.WriteLine();

            // 4. Registrar inicio en log
            long idLog = await RegistrarInicioLog(idCompania, añoCalculo, loteImportacion);
            Console.WriteLine($"Log ID: {idLog}");
            Console.WriteLine($"Lote: {loteImportacion}");
            Console.WriteLine();

            // 5. Extraer datos de origen usando configuración de la BD
            Console.WriteLine("Extrayendo datos de origen...");
            DataTable dtActivos = await ExtraerActivosOrigen(connectionStringOrigen, queryETL, idCompania, añoCalculo, limiteRegistros);
            Console.WriteLine($"Activos extraídos: {dtActivos.Rows.Count}");
            Console.WriteLine();

            // 3.5. Actualizar log con el total de registros a procesar
            await ActualizarTotalRegistrosLog(idLog, dtActivos.Rows.Count);

            // 4. Procesar y cargar datos
            Console.WriteLine("Procesando y cargando datos...");
            registrosProcesados = await ProcesarYCargarActivos(
                dtActivos, idCompania, añoCalculo, loteImportacion, tipoCambio30Junio, idLog);
            Console.WriteLine($"Activos cargados: {registrosProcesados}");
            Console.WriteLine();

            // 5. Actualizar log como completado
            await ActualizarLogCompletado(idLog, fechaInicio, registrosProcesados);

            // 6. Mostrar resumen
            await MostrarResumen(idCompania, añoCalculo, loteImportacion);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            throw;
        }
    }

    private async Task EliminarConstraintUnicidad()
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            IF EXISTS (
                SELECT 1
                FROM sys.key_constraints
                WHERE name = 'UQ_Staging_Activo'
                  AND parent_object_id = OBJECT_ID('dbo.Staging_Activo')
            )
            BEGIN
                ALTER TABLE dbo.Staging_Activo DROP CONSTRAINT UQ_Staging_Activo;
                SELECT 1;
            END
            ELSE
            BEGIN
                SELECT 0;
            END", conn);

        var result = await cmd.ExecuteScalarAsync();
        if (result != null && Convert.ToInt32(result) == 1)
        {
            Console.WriteLine("Constraint UQ_Staging_Activo eliminado");
        }
    }

    private async Task LimpiarStagingPrevio(int idCompania, int añoCalculo)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        // Eliminar cálculos previos
        var cmdCalculo = new SqlCommand(@"
            DELETE FROM Calculo_RMF
            WHERE ID_Compania = @ID_Compania
              AND Año_Calculo = @Año_Calculo", conn);
        cmdCalculo.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmdCalculo.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        int calculosDeleted = await cmdCalculo.ExecuteNonQueryAsync();

        // Calculo_Fiscal_Simulado - solo si existe la tabla
        int simuladosDeleted = 0;
        var cmdCheckSimulado = new SqlCommand(@"
            SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_NAME = 'Calculo_Fiscal_Simulado'", conn);
        int tableExists = (int)await cmdCheckSimulado.ExecuteScalarAsync();

        if (tableExists > 0)
        {
            var cmdSimulado = new SqlCommand(@"
                DELETE FROM Calculo_Fiscal_Simulado
                WHERE ID_Compania = @ID_Compania
                  AND Año_Calculo = @Año_Calculo", conn);
            cmdSimulado.Parameters.AddWithValue("@ID_Compania", idCompania);
            cmdSimulado.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
            simuladosDeleted = await cmdSimulado.ExecuteNonQueryAsync();
        }

        // Eliminar staging previo para reimportar
        var cmdStaging = new SqlCommand(@"
            DELETE FROM Staging_Activo
            WHERE ID_Compania = @ID_Compania
              AND Año_Calculo = @Año_Calculo", conn);
        cmdStaging.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmdStaging.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        int stagingDeleted = await cmdStaging.ExecuteNonQueryAsync();

        if (calculosDeleted > 0 || simuladosDeleted > 0 || stagingDeleted > 0)
        {
            Console.WriteLine($"Datos previos eliminados:");
            if (stagingDeleted > 0) Console.WriteLine($"  - Staging_Activo: {stagingDeleted}");
            if (calculosDeleted > 0) Console.WriteLine($"  - Calculo_RMF: {calculosDeleted}");
            if (simuladosDeleted > 0) Console.WriteLine($"  - Calculo_Fiscal_Simulado: {simuladosDeleted}");
        }
    }

    private async Task<decimal> ObtenerTipoCambio30Junio(int añoCalculo)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            SELECT Tipo_Cambio
            FROM Tipo_Cambio
            WHERE Año = @Año
              AND MONTH(Fecha) = 6
              AND DAY(Fecha) = 30
              AND ID_Moneda = 2", conn);

        cmd.Parameters.AddWithValue("@Año", añoCalculo);

        var result = await cmd.ExecuteScalarAsync();
        if (result == null || result == DBNull.Value)
            throw new Exception($"No se encontró tipo de cambio para el 30 de junio de {añoCalculo}");

        return Convert.ToDecimal(result);
    }

    private async Task<long> RegistrarInicioLog(int idCompania, int añoCalculo, Guid loteImportacion)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            INSERT INTO Log_Ejecucion_ETL
                (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
                 Fecha_Inicio, Estado, Usuario)
            VALUES
                (@ID_Compania, @Año_Calculo, @Lote_Importacion, 'ETL_NET',
                 @Fecha_Inicio, 'En Proceso', 'ETL.NET');
            SELECT CAST(SCOPE_IDENTITY() AS BIGINT);", conn);

        cmd.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmd.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        cmd.Parameters.AddWithValue("@Lote_Importacion", loteImportacion);
        cmd.Parameters.AddWithValue("@Fecha_Inicio", DateTime.Now);

        return (long)(await cmd.ExecuteScalarAsync() ?? 0);
    }

    private async Task ActualizarTotalRegistrosLog(long idLog, int totalRegistros)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            UPDATE Log_Ejecucion_ETL
            SET Registros_Exitosos = @Total_Registros
            WHERE ID_Log = @ID_Log", conn);

        cmd.Parameters.AddWithValue("@ID_Log", idLog);
        cmd.Parameters.AddWithValue("@Total_Registros", totalRegistros);

        await cmd.ExecuteNonQueryAsync();
        Console.WriteLine($"[TOTAL] {totalRegistros} registros a procesar");
    }

    private async Task<(string ConnectionString, string QueryETL, string NombreCompania)> ObtenerConfiguracionCompania(int idCompania)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            SELECT
                ConnectionString_Actif,
                Query_ETL,
                Nombre_Compania
            FROM ConfiguracionCompania
            WHERE ID_Compania = @ID_Compania
              AND Activo = 1", conn);

        cmd.Parameters.AddWithValue("@ID_Compania", idCompania);

        using var reader = await cmd.ExecuteReaderAsync();

        if (!await reader.ReadAsync())
        {
            throw new Exception($"No se encontró configuración para compañía {idCompania}");
        }

        string connectionString = reader["ConnectionString_Actif"]?.ToString() ?? "";
        string queryETL = reader["Query_ETL"]?.ToString() ?? "";
        string nombreCompania = reader["Nombre_Compania"]?.ToString() ?? $"Compañía {idCompania}";

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new Exception($"ConnectionString_Actif no configurado para compañía {idCompania}. Debe configurarse en la tabla ConfiguracionCompania.");
        }

        if (string.IsNullOrWhiteSpace(queryETL))
        {
            throw new Exception($"Query_ETL no configurado para compañía {idCompania}. Debe configurarse en la tabla ConfiguracionCompania.");
        }

        Console.WriteLine($"✅ Configuración obtenida para: {nombreCompania}");
        Console.WriteLine($"   Connection String: {connectionString.Substring(0, Math.Min(50, connectionString.Length))}...");
        Console.WriteLine();

        return (connectionString, queryETL, nombreCompania);
    }

    private async Task<DataTable> ExtraerActivosOrigen(string connectionStringOrigen, string queryETL, int idCompania, int añoCalculo, int? limiteRegistros = null)
    {
        int añoAnterior = añoCalculo - 1;

        // Usar el query configurado
        string queryBase = queryETL;

        // Si hay límite, agregar TOP al query
        if (limiteRegistros.HasValue)
        {
            // Insertar TOP después del primer SELECT (sin comentarios)
            int selectIndex = queryBase.IndexOf("SELECT", StringComparison.OrdinalIgnoreCase);
            if (selectIndex >= 0)
            {
                queryBase = queryBase.Insert(selectIndex + 6, $" TOP {limiteRegistros.Value}");
            }
        }

        // Usar el connection string obtenido de la BD
        using var conn = new SqlConnection(connectionStringOrigen);
        await conn.OpenAsync();

        // Usar el query configurado en la BD
        var cmd = new SqlCommand(queryBase, conn);

        // Pasar parámetros al query
        cmd.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmd.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        cmd.Parameters.AddWithValue("@Año_Anterior", añoAnterior);
        cmd.CommandTimeout = 300; // 5 minutos

        var dt = new DataTable();
        using var reader = await cmd.ExecuteReaderAsync();
        dt.Load(reader);

        return dt;
    }

    private async Task<int> ProcesarYCargarActivos(
        DataTable dtActivos, int idCompania, int añoCalculo, Guid loteImportacion, decimal tipoCambio30Junio, long idLog)
    {
        // 1. PREPARAR DataTable con todas las transformaciones
        Console.WriteLine("Transformando datos en memoria...");
        DataTable dtStaging = PrepararDataTableStaging(dtActivos, idCompania, añoCalculo, loteImportacion, tipoCambio30Junio);

        int totalRows = dtStaging.Rows.Count;
        Console.WriteLine($"Total preparado: {totalRows} registros");
        Console.WriteLine();

        // 2. BULK INSERT usando SqlBulkCopy
        Console.WriteLine("Insertando datos con SqlBulkCopy...");
        using var bulkCopy = new SqlBulkCopy(ConnStrDestino);
        bulkCopy.DestinationTableName = "Staging_Activo";
        bulkCopy.BatchSize = 1000;
        bulkCopy.BulkCopyTimeout = 300; // 5 minutos

        // 3. Mapear columnas
        MapearColumnasBulkCopy(bulkCopy);

        // 4. Progreso
        int registrosProcesados = 0;
        bulkCopy.NotifyAfter = 100;
        bulkCopy.SqlRowsCopied += (sender, e) => {
            registrosProcesados = (int)e.RowsCopied;
            Console.WriteLine($"  Procesados: {e.RowsCopied} / {totalRows}");

            // Actualizar progreso en BD
            Task.Run(async () => await ActualizarProgresoEnBD(idLog, (int)e.RowsCopied, totalRows)).Wait();
        };

        // 5. Insertar TODO
        await bulkCopy.WriteToServerAsync(dtStaging);

        Console.WriteLine($"✅ SqlBulkCopy completado: {totalRows} registros");

        return totalRows;
    }

    private DataTable PrepararDataTableStaging(DataTable dtOrigen, int idCompania, int añoCalculo, Guid loteImportacion, decimal tipoCambio30Junio)
    {
        // Crear estructura de tabla Staging_Activo
        DataTable dtStaging = new DataTable();

        // Definir columnas
        dtStaging.Columns.Add("ID_Compania", typeof(int));
        dtStaging.Columns.Add("ID_NUM_ACTIVO", typeof(int));
        dtStaging.Columns.Add("ID_ACTIVO", typeof(string));
        dtStaging.Columns.Add("ID_TIPO_ACTIVO", typeof(int));
        dtStaging.Columns.Add("ID_SUBTIPO_ACTIVO", typeof(int));
        dtStaging.Columns.Add("Nombre_TipoActivo", typeof(string));
        dtStaging.Columns.Add("DESCRIPCION", typeof(string));
        dtStaging.Columns.Add("ID_MONEDA", typeof(int));
        dtStaging.Columns.Add("Nombre_Moneda", typeof(string));
        dtStaging.Columns.Add("ID_PAIS", typeof(int));
        dtStaging.Columns.Add("Nombre_Pais", typeof(string));
        dtStaging.Columns.Add("FECHA_COMPRA", typeof(DateTime));
        dtStaging.Columns.Add("FECHA_BAJA", typeof(DateTime));
        dtStaging.Columns.Add("FECHA_INICIO_DEP", typeof(DateTime));
        dtStaging.Columns.Add("STATUS", typeof(string));
        dtStaging.Columns.Add("FLG_PROPIO", typeof(int));
        dtStaging.Columns.Add("Tasa_Anual", typeof(decimal));
        dtStaging.Columns.Add("Tasa_Mensual", typeof(decimal));
        dtStaging.Columns.Add("Dep_Acum_Inicio_Año", typeof(decimal));
        dtStaging.Columns.Add("ManejaFiscal", typeof(string));
        dtStaging.Columns.Add("ManejaUSGAAP", typeof(string));
        dtStaging.Columns.Add("FECHA_INIC_DEPREC_3", typeof(DateTime));
        dtStaging.Columns.Add("CostoUSD", typeof(decimal));
        dtStaging.Columns.Add("CostoMXN", typeof(decimal));
        dtStaging.Columns.Add("Año_Calculo", typeof(int));
        dtStaging.Columns.Add("Lote_Importacion", typeof(Guid));

        // Transformar y copiar datos
        foreach (DataRow rowOrigen in dtOrigen.Rows)
        {
            string manejaFiscal = rowOrigen["ManejaFiscal"].ToString() ?? "N";
            string manejaUSGAAP = rowOrigen["ManejaUSGAAP"].ToString() ?? "N";

            // ERROR DE DEDO: Si ambos están activos, omitir
            if (manejaFiscal == "S" && manejaUSGAAP == "S")
            {
                Console.WriteLine($"⚠️  ADVERTENCIA: Activo {rowOrigen["ID_NUM_ACTIVO"]} tiene ambos flags activos - OMITIDO");
                continue;
            }

            // Calcular costos según tipo
            decimal? costoUSD = null;
            decimal? costoMXN = null;

            if (manejaUSGAAP == "S")
            {
                decimal costoReexpresado = rowOrigen["COSTO_REEXPRESADO"] != DBNull.Value
                    ? Convert.ToDecimal(rowOrigen["COSTO_REEXPRESADO"])
                    : 0;

                if (costoReexpresado > 0)
                {
                    costoUSD = costoReexpresado;
                }
                else if (rowOrigen["COSTO_ADQUISICION"] != DBNull.Value)
                {
                    decimal costoAdquisicion = Convert.ToDecimal(rowOrigen["COSTO_ADQUISICION"]);
                    if (costoAdquisicion > 0)
                        costoUSD = costoAdquisicion;
                }

                if (costoUSD.HasValue)
                    costoMXN = costoUSD * tipoCambio30Junio;
            }
            else if (manejaFiscal == "S")
            {
                decimal costoRevaluado = rowOrigen["COSTO_REVALUADO"] != DBNull.Value
                    ? Convert.ToDecimal(rowOrigen["COSTO_REVALUADO"])
                    : 0;

                if (costoRevaluado > 0)
                {
                    costoMXN = costoRevaluado;
                }
                else if (rowOrigen["COSTO_ADQUISICION"] != DBNull.Value)
                {
                    decimal costoAdquisicion = Convert.ToDecimal(rowOrigen["COSTO_ADQUISICION"]);
                    if (costoAdquisicion > 0)
                        costoMXN = costoAdquisicion;
                }
            }
            else
            {
                if (rowOrigen["COSTO_ADQUISICION"] != DBNull.Value)
                    costoMXN = Convert.ToDecimal(rowOrigen["COSTO_ADQUISICION"]);
            }

            // Calcular Tasa_Mensual
            decimal? tasaMensual = null;
            if (rowOrigen["Tasa_Anual"] != DBNull.Value)
            {
                tasaMensual = Convert.ToDecimal(rowOrigen["Tasa_Anual"]) / 100.0m / 12.0m;
            }

            // Crear fila staging
            DataRow rowStaging = dtStaging.NewRow();

            rowStaging["ID_Compania"] = rowOrigen["ID_COMPANIA"];
            rowStaging["ID_NUM_ACTIVO"] = rowOrigen["ID_NUM_ACTIVO"];
            rowStaging["ID_ACTIVO"] = rowOrigen["ID_ACTIVO"] ?? DBNull.Value;
            rowStaging["ID_TIPO_ACTIVO"] = rowOrigen["ID_TIPO_ACTIVO"] ?? DBNull.Value;
            rowStaging["ID_SUBTIPO_ACTIVO"] = rowOrigen["ID_SUBTIPO_ACTIVO"] ?? DBNull.Value;
            rowStaging["Nombre_TipoActivo"] = rowOrigen["Nombre_TipoActivo"] ?? DBNull.Value;
            rowStaging["DESCRIPCION"] = rowOrigen["DESCRIPCION"] ?? DBNull.Value;
            rowStaging["ID_MONEDA"] = rowOrigen["ID_MONEDA"] ?? DBNull.Value;
            rowStaging["Nombre_Moneda"] = rowOrigen["Nombre_Moneda"] ?? DBNull.Value;
            rowStaging["ID_PAIS"] = rowOrigen["ID_PAIS"];
            rowStaging["Nombre_Pais"] = rowOrigen["Nombre_Pais"] ?? DBNull.Value;
            rowStaging["FECHA_COMPRA"] = rowOrigen["FECHA_COMPRA"] ?? DBNull.Value;
            rowStaging["FECHA_BAJA"] = rowOrigen["FECHA_BAJA"] ?? DBNull.Value;
            rowStaging["FECHA_INICIO_DEP"] = rowOrigen["FECHA_INIC_DEPREC"] ?? DBNull.Value;
            rowStaging["STATUS"] = rowOrigen["STATUS"] ?? DBNull.Value;

            int flgPropio = rowOrigen["FLG_PROPIO"].ToString() == "S" ? 1 : 0;
            rowStaging["FLG_PROPIO"] = flgPropio;

            rowStaging["Tasa_Anual"] = rowOrigen["Tasa_Anual"] ?? DBNull.Value;
            rowStaging["Tasa_Mensual"] = tasaMensual.HasValue ? (object)tasaMensual.Value : DBNull.Value;
            rowStaging["Dep_Acum_Inicio_Año"] = rowOrigen["Dep_Acum_Inicio_Año"] ?? DBNull.Value;
            rowStaging["ManejaFiscal"] = manejaFiscal;
            rowStaging["ManejaUSGAAP"] = manejaUSGAAP;
            rowStaging["FECHA_INIC_DEPREC_3"] = rowOrigen["FECHA_INIC_DEPREC3"] ?? DBNull.Value;
            rowStaging["CostoUSD"] = costoUSD.HasValue ? (object)costoUSD.Value : DBNull.Value;
            rowStaging["CostoMXN"] = costoMXN.HasValue ? (object)costoMXN.Value : DBNull.Value;
            rowStaging["Año_Calculo"] = añoCalculo;
            rowStaging["Lote_Importacion"] = loteImportacion;

            dtStaging.Rows.Add(rowStaging);
        }

        return dtStaging;
    }

    private void MapearColumnasBulkCopy(SqlBulkCopy bulkCopy)
    {
        bulkCopy.ColumnMappings.Add("ID_Compania", "ID_Compania");
        bulkCopy.ColumnMappings.Add("ID_NUM_ACTIVO", "ID_NUM_ACTIVO");
        bulkCopy.ColumnMappings.Add("ID_ACTIVO", "ID_ACTIVO");
        bulkCopy.ColumnMappings.Add("ID_TIPO_ACTIVO", "ID_TIPO_ACTIVO");
        bulkCopy.ColumnMappings.Add("ID_SUBTIPO_ACTIVO", "ID_SUBTIPO_ACTIVO");
        bulkCopy.ColumnMappings.Add("Nombre_TipoActivo", "Nombre_TipoActivo");
        bulkCopy.ColumnMappings.Add("DESCRIPCION", "DESCRIPCION");
        bulkCopy.ColumnMappings.Add("ID_MONEDA", "ID_MONEDA");
        bulkCopy.ColumnMappings.Add("Nombre_Moneda", "Nombre_Moneda");
        bulkCopy.ColumnMappings.Add("ID_PAIS", "ID_PAIS");
        bulkCopy.ColumnMappings.Add("Nombre_Pais", "Nombre_Pais");
        bulkCopy.ColumnMappings.Add("FECHA_COMPRA", "FECHA_COMPRA");
        bulkCopy.ColumnMappings.Add("FECHA_BAJA", "FECHA_BAJA");
        bulkCopy.ColumnMappings.Add("FECHA_INICIO_DEP", "FECHA_INICIO_DEP");
        bulkCopy.ColumnMappings.Add("STATUS", "STATUS");
        bulkCopy.ColumnMappings.Add("FLG_PROPIO", "FLG_PROPIO");
        bulkCopy.ColumnMappings.Add("Tasa_Anual", "Tasa_Anual");
        bulkCopy.ColumnMappings.Add("Tasa_Mensual", "Tasa_Mensual");
        bulkCopy.ColumnMappings.Add("Dep_Acum_Inicio_Año", "Dep_Acum_Inicio_Año");
        bulkCopy.ColumnMappings.Add("ManejaFiscal", "ManejaFiscal");
        bulkCopy.ColumnMappings.Add("ManejaUSGAAP", "ManejaUSGAAP");
        bulkCopy.ColumnMappings.Add("FECHA_INIC_DEPREC_3", "FECHA_INIC_DEPREC_3");
        bulkCopy.ColumnMappings.Add("CostoUSD", "CostoUSD");
        bulkCopy.ColumnMappings.Add("CostoMXN", "CostoMXN");
        bulkCopy.ColumnMappings.Add("Año_Calculo", "Año_Calculo");
        bulkCopy.ColumnMappings.Add("Lote_Importacion", "Lote_Importacion");
    }

    private async Task ActualizarProgresoEnBD(long idLog, int registrosProcesados, int totalRegistros)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            UPDATE Log_Ejecucion_ETL
            SET Registros_Procesados = @Registros_Procesados
            WHERE ID_Log = @ID_Log", conn);

        cmd.Parameters.AddWithValue("@ID_Log", idLog);
        cmd.Parameters.AddWithValue("@Registros_Procesados", registrosProcesados);

        await cmd.ExecuteNonQueryAsync();
        Console.WriteLine($"[PROGRESO] Actualizado en BD: {registrosProcesados}/{totalRegistros}");
    }


    private async Task ActualizarLogCompletado(long idLog, DateTime fechaInicio, int registrosProcesados)
    {
        Console.WriteLine($"[DEBUG] Actualizando log ID={idLog} a Completado con {registrosProcesados} registros");

        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            UPDATE Log_Ejecucion_ETL
            SET
                Fecha_Fin = @Fecha_Fin,
                Duracion_Segundos = DATEDIFF(SECOND, @Fecha_Inicio, @Fecha_Fin),
                Registros_Procesados = @Registros_Procesados,
                Registros_Exitosos = @Registros_Procesados,
                Registros_Error = 0,
                Estado = 'Completado'
            WHERE ID_Log = @ID_Log", conn);

        cmd.Parameters.AddWithValue("@ID_Log", idLog);
        cmd.Parameters.AddWithValue("@Fecha_Inicio", fechaInicio);
        cmd.Parameters.AddWithValue("@Fecha_Fin", DateTime.Now);
        cmd.Parameters.AddWithValue("@Registros_Procesados", registrosProcesados);

        int rowsAffected = await cmd.ExecuteNonQueryAsync();
        Console.WriteLine($"[DEBUG] Filas actualizadas: {rowsAffected}");

        if (rowsAffected == 0)
        {
            Console.WriteLine($"[ERROR] No se pudo actualizar el registro con ID_Log={idLog}");
        }
    }

    private async Task MostrarResumen(int idCompania, int añoCalculo, Guid loteImportacion)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            SELECT
                COUNT(*) AS Total_Importados,
                COUNT(CASE WHEN FLG_PROPIO = 1 THEN 1 END) AS Total_Propios,
                COUNT(CASE WHEN FLG_PROPIO <> 1 THEN 1 END) AS Total_No_Propios,
                COUNT(CASE WHEN ID_PAIS > 1 THEN 1 END) AS Total_Extranjeros,
                COUNT(CASE WHEN ID_PAIS = 1 THEN 1 END) AS Total_Mexicanos,
                COUNT(CASE WHEN ManejaFiscal = 'S' THEN 1 END) AS Con_Fiscal,
                COUNT(CASE WHEN ManejaUSGAAP = 'S' THEN 1 END) AS Con_USGAAP,
                COUNT(CASE WHEN ManejaUSGAAP = 'S' AND ISNULL(ManejaFiscal, 'N') <> 'S' THEN 1 END) AS Requiere_Fiscal_Simulado
            FROM Staging_Activo
            WHERE ID_Compania = @ID_Compania
              AND Año_Calculo = @Año_Calculo
              AND Lote_Importacion = @Lote_Importacion", conn);

        cmd.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmd.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        cmd.Parameters.AddWithValue("@Lote_Importacion", loteImportacion);

        using var reader = await cmd.ExecuteReaderAsync();
        if (await reader.ReadAsync())
        {
            Console.WriteLine("===========================================");
            Console.WriteLine("RESUMEN DE IMPORTACIÓN");
            Console.WriteLine("===========================================");
            Console.WriteLine($"Total importados:        {reader["Total_Importados"]}");
            Console.WriteLine($"  - Propios:             {reader["Total_Propios"]}");
            Console.WriteLine($"  - No propios:          {reader["Total_No_Propios"]}");
            Console.WriteLine($"  - Mexicanos:           {reader["Total_Mexicanos"]}");
            Console.WriteLine($"  - Extranjeros:         {reader["Total_Extranjeros"]}");
            Console.WriteLine($"  - Con Fiscal:          {reader["Con_Fiscal"]}");
            Console.WriteLine($"  - Con USGAAP:          {reader["Con_USGAAP"]}");
            Console.WriteLine($"  - Req. Fiscal Sim:     {reader["Requiere_Fiscal_Simulado"]}");
            Console.WriteLine("===========================================");
        }
    }
}
