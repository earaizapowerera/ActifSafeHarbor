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
    // Connection strings
    private const string ConnStrOrigen = "Server=dbdev.powerera.com;Database=actif_learensayo10;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
    private const string ConnStrDestino = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

    public async Task EjecutarETL(int idCompania, int añoCalculo, int? limiteRegistros = null, Guid? loteParam = null)
    {
        Guid loteImportacion = loteParam ?? Guid.NewGuid();
        DateTime fechaInicio = DateTime.Now;
        int registrosProcesados = 0;

        try
        {
            // 0. Verificar y eliminar constraint de unicidad (si existe)
            await EliminarConstraintUnicidad();

            // 0.5 Limpiar datos previos de staging para esta compañía/año
            await LimpiarStagingPrevio(idCompania, añoCalculo);

            // 1. Obtener tipo de cambio del 30 de junio
            decimal tipoCambio30Junio = await ObtenerTipoCambio30Junio(añoCalculo);
            Console.WriteLine($"Tipo de cambio 30-Jun-{añoCalculo}: {tipoCambio30Junio:N6}");
            Console.WriteLine();

            // 2. Registrar inicio en log
            long idLog = await RegistrarInicioLog(idCompania, añoCalculo, loteImportacion);
            Console.WriteLine($"Log ID: {idLog}");
            Console.WriteLine($"Lote: {loteImportacion}");
            Console.WriteLine();

            // 3. Extraer datos de origen
            Console.WriteLine("Extrayendo datos de origen...");
            DataTable dtActivos = await ExtraerActivosOrigen(idCompania, añoCalculo, limiteRegistros);
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

    private async Task<string> ObtenerQueryETL(int idCompania)
    {
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        var cmd = new SqlCommand(@"
            SELECT Query_ETL
            FROM ConfiguracionCompania
            WHERE ID_Compania = @ID_Compania
              AND Activo = 1", conn);

        cmd.Parameters.AddWithValue("@ID_Compania", idCompania);

        var result = await cmd.ExecuteScalarAsync();
        if (result == null || result == DBNull.Value || string.IsNullOrWhiteSpace(result.ToString()))
        {
            throw new Exception($"No se encontró Query_ETL configurado para compañía {idCompania}");
        }

        return result.ToString()!;
    }

    private async Task<DataTable> ExtraerActivosOrigen(int idCompania, int añoCalculo, int? limiteRegistros = null)
    {
        int añoAnterior = añoCalculo - 1;

        // Obtener query configurado para esta compañía
        string queryBase = await ObtenerQueryETL(idCompania);

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

        using var conn = new SqlConnection(ConnStrOrigen);
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
        using var conn = new SqlConnection(ConnStrDestino);
        await conn.OpenAsync();

        int registrosCargados = 0;
        int batchSize = 100;
        int totalRows = dtActivos.Rows.Count;
        int ultimoRegistroActualizado = 0;
        DateTime ultimaActualizacionTiempo = DateTime.Now;
        TimeSpan intervaloTiempo = TimeSpan.FromSeconds(10); // Actualizar cada 10 segundos

        for (int i = 0; i < totalRows; i += batchSize)
        {
            int rowsToProcess = Math.Min(batchSize, totalRows - i);

            using var transaction = conn.BeginTransaction();
            try
            {
                for (int j = 0; j < rowsToProcess; j++)
                {
                    DataRow row = dtActivos.Rows[i + j];
                    await InsertarActivoStaging(conn, transaction, row, idCompania, añoCalculo, loteImportacion, tipoCambio30Junio);
                    registrosCargados++;
                }

                await transaction.CommitAsync();
                Console.WriteLine($"  Procesados: {Math.Min(i + batchSize, totalRows)} / {totalRows}");

                // Actualizar progreso en BD si:
                // 1. El número de registros cambió desde la última actualización, O
                // 2. Han pasado 10 segundos desde la última actualización
                TimeSpan tiempoTranscurrido = DateTime.Now - ultimaActualizacionTiempo;
                bool cambioRegistros = registrosCargados != ultimoRegistroActualizado;
                bool pasaron10Segundos = tiempoTranscurrido >= intervaloTiempo;

                if (cambioRegistros || pasaron10Segundos)
                {
                    await ActualizarProgresoEnBD(idLog, registrosCargados, totalRows);
                    ultimoRegistroActualizado = registrosCargados;
                    ultimaActualizacionTiempo = DateTime.Now;
                }
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }

        // Actualización final para asegurar que el último estado se guarde
        if (registrosCargados != ultimoRegistroActualizado)
        {
            await ActualizarProgresoEnBD(idLog, registrosCargados, totalRows);
        }

        return registrosCargados;
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

    private async Task InsertarActivoStaging(
        SqlConnection conn, SqlTransaction transaction, DataRow row,
        int idCompania, int añoCalculo, Guid loteImportacion, decimal tipoCambio30Junio)
    {
        // Determinar CostoUSD y CostoMXN según reglas:
        // - Si ManejaUSGAAP='S': CostoUSD = COSTO_REEXPRESADO, CostoMXN = COSTO_REEXPRESADO * TC
        // - Si ManejaFiscal='S': CostoMXN = COSTO_REVALUADO (directo), CostoUSD = NULL
        // - Si no tiene ninguno: usar COSTO_ADQUISICION

        string manejaFiscal = row["ManejaFiscal"].ToString() ?? "N";
        string manejaUSGAAP = row["ManejaUSGAAP"].ToString() ?? "N";

        // ERROR DE DEDO: Si ambos están activos, es un error - NO procesar
        if (manejaFiscal == "S" && manejaUSGAAP == "S")
        {
            Console.WriteLine($"⚠️  ADVERTENCIA: Activo {row["ID_NUM_ACTIVO"]} tiene ambos flags activos (Fiscal Y USGAAP) - OMITIDO por error de dedo");
            return;  // NO insertar este activo
        }

        decimal? costoUSD = null;
        decimal? costoMXN = null;

        if (manejaUSGAAP == "S")
        {
            // USGAAP: Costo en USD, convertir a MXN
            decimal costoReexpresado = row["COSTO_REEXPRESADO"] != DBNull.Value
                ? Convert.ToDecimal(row["COSTO_REEXPRESADO"])
                : 0;

            // Si COSTO_REEXPRESADO es 0, usar COSTO_ADQUISICION como fallback
            if (costoReexpresado > 0)
            {
                costoUSD = costoReexpresado;
            }
            else if (row["COSTO_ADQUISICION"] != DBNull.Value)
            {
                decimal costoAdquisicion = Convert.ToDecimal(row["COSTO_ADQUISICION"]);
                if (costoAdquisicion > 0)
                {
                    costoUSD = costoAdquisicion;
                }
            }

            if (costoUSD.HasValue)
            {
                costoMXN = costoUSD * tipoCambio30Junio;
            }
        }
        else if (manejaFiscal == "S")
        {
            // Fiscal: Costo ya en MXN
            decimal costoRevaluado = row["COSTO_REVALUADO"] != DBNull.Value
                ? Convert.ToDecimal(row["COSTO_REVALUADO"])
                : 0;

            // Si COSTO_REVALUADO es 0, usar COSTO_ADQUISICION como fallback
            if (costoRevaluado > 0)
            {
                costoMXN = costoRevaluado;
            }
            else if (row["COSTO_ADQUISICION"] != DBNull.Value)
            {
                decimal costoAdquisicion = Convert.ToDecimal(row["COSTO_ADQUISICION"]);
                if (costoAdquisicion > 0)
                {
                    costoMXN = costoAdquisicion;
                }
            }
        }
        else
        {
            // Sin USGAAP ni Fiscal: usar costo adquisición
            if (row["COSTO_ADQUISICION"] != DBNull.Value)
            {
                costoMXN = Convert.ToDecimal(row["COSTO_ADQUISICION"]);
            }
        }

        var cmd = new SqlCommand(@"
            INSERT INTO Staging_Activo
                (ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
                 Nombre_TipoActivo, DESCRIPCION, ID_MONEDA, Nombre_Moneda,
                 ID_PAIS, Nombre_Pais, FECHA_COMPRA, FECHA_BAJA, FECHA_INICIO_DEP, STATUS,
                 FLG_PROPIO, Tasa_Anual, Tasa_Mensual, Dep_Acum_Inicio_Año,
                 INPC_Adquisicion, INPC_Mitad_Ejercicio,
                 ManejaFiscal, ManejaUSGAAP, FECHA_INIC_DEPREC_3,
                 CostoUSD, CostoMXN,
                 Año_Calculo, Lote_Importacion)
            VALUES
                (@ID_Compania, @ID_NUM_ACTIVO, @ID_ACTIVO, @ID_TIPO_ACTIVO, @ID_SUBTIPO_ACTIVO,
                 @Nombre_TipoActivo, @DESCRIPCION, @ID_MONEDA, @Nombre_Moneda,
                 @ID_PAIS, @Nombre_Pais, @FECHA_COMPRA, @FECHA_BAJA, @FECHA_INICIO_DEP, @STATUS,
                 @FLG_PROPIO, @Tasa_Anual, @Tasa_Mensual, @Dep_Acum_Inicio_Año,
                 @INPC_Adquisicion, @INPC_Mitad_Ejercicio,
                 @ManejaFiscal, @ManejaUSGAAP, @FECHA_INIC_DEPREC_3,
                 @CostoUSD, @CostoMXN,
                 @Año_Calculo, @Lote_Importacion)", conn, transaction);

        cmd.Parameters.AddWithValue("@ID_Compania", row["ID_COMPANIA"]);
        cmd.Parameters.AddWithValue("@ID_NUM_ACTIVO", row["ID_NUM_ACTIVO"]);
        cmd.Parameters.AddWithValue("@ID_ACTIVO", row["ID_ACTIVO"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ID_TIPO_ACTIVO", row["ID_TIPO_ACTIVO"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ID_SUBTIPO_ACTIVO", row["ID_SUBTIPO_ACTIVO"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Nombre_TipoActivo", row["Nombre_TipoActivo"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@DESCRIPCION", row["DESCRIPCION"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ID_MONEDA", row["ID_MONEDA"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Nombre_Moneda", row["Nombre_Moneda"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ID_PAIS", row["ID_PAIS"]);
        cmd.Parameters.AddWithValue("@Nombre_Pais", row["Nombre_Pais"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@FECHA_COMPRA", row["FECHA_COMPRA"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@FECHA_BAJA", row["FECHA_BAJA"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@FECHA_INICIO_DEP", row["FECHA_INIC_DEPREC"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@STATUS", row["STATUS"] ?? DBNull.Value);

        // Convertir FLG_PROPIO de char a int
        int flgPropio = row["FLG_PROPIO"].ToString() == "S" ? 1 : 0;
        cmd.Parameters.AddWithValue("@FLG_PROPIO", flgPropio);

        cmd.Parameters.AddWithValue("@Tasa_Anual", row["Tasa_Anual"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Tasa_Mensual",
            row["Tasa_Anual"] != DBNull.Value ? Convert.ToDecimal(row["Tasa_Anual"]) / 100.0m / 12.0m : DBNull.Value);
        cmd.Parameters.AddWithValue("@Dep_Acum_Inicio_Año", row["Dep_Acum_Inicio_Año"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@INPC_Adquisicion", row["INPC_Adquisicion"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@INPC_Mitad_Ejercicio", row["INPC_Mitad_Ejercicio"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ManejaFiscal", manejaFiscal);
        cmd.Parameters.AddWithValue("@ManejaUSGAAP", manejaUSGAAP);
        cmd.Parameters.AddWithValue("@FECHA_INIC_DEPREC_3", row["FECHA_INIC_DEPREC3"] ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@CostoUSD", (object?)costoUSD ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@CostoMXN", (object?)costoMXN ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        cmd.Parameters.AddWithValue("@Lote_Importacion", loteImportacion);

        await cmd.ExecuteNonQueryAsync();
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
