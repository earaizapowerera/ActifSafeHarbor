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

        var cmdSimulado = new SqlCommand(@"
            DELETE FROM Calculo_Fiscal_Simulado
            WHERE ID_Compania = @ID_Compania
              AND Año_Calculo = @Año_Calculo", conn);
        cmdSimulado.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmdSimulado.Parameters.AddWithValue("@Año_Calculo", añoCalculo);
        int simuladosDeleted = await cmdSimulado.ExecuteNonQueryAsync();

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

    private async Task<DataTable> ExtraerActivosOrigen(int idCompania, int añoCalculo, int? limiteRegistros = null)
    {
        int añoAnterior = añoCalculo - 1;
        string topClause = limiteRegistros.HasValue ? $"TOP {limiteRegistros.Value}" : "";

        using var conn = new SqlConnection(ConnStrOrigen);
        await conn.OpenAsync();

        var cmd = new SqlCommand($@"
            SELECT {topClause}
                -- Identificación
                a.ID_COMPANIA,
                a.ID_NUM_ACTIVO,
                a.ID_ACTIVO,
                a.ID_TIPO_ACTIVO,
                a.ID_SUBTIPO_ACTIVO,
                ta.DESCRIPCION AS Nombre_TipoActivo,
                a.DESCRIPCION,

                -- Datos financieros base
                a.COSTO_ADQUISICION,
                a.COSTO_REVALUADO,
                a.COSTO_REEXPRESADO,
                a.ID_MONEDA,
                m.NOMBRE AS Nombre_Moneda,

                -- País
                a.ID_PAIS,
                p.NOMBRE AS Nombre_Pais,

                -- Fechas
                a.FECHA_COMPRA,
                a.FECHA_BAJA,
                a.FECHA_INIC_DEPREC,
                a.FECHA_INIC_DEPREC3,
                a.STATUS,

                -- Ownership
                a.FLG_PROPIO,

                -- Flags de tipo de depreciación
                a.FLG_NOCAPITALIZABLE_2 AS ManejaFiscal,
                a.FLG_NOCAPITALIZABLE_3 AS ManejaUSGAAP,

                -- Tasa de depreciación FISCAL - Subquery para evitar duplicados
                ISNULL((
                    SELECT TOP 1 pd.PORC_SEGUNDO_ANO
                    FROM porcentaje_depreciacion pd
                    WHERE pd.ID_TIPO_ACTIVO = a.ID_TIPO_ACTIVO
                      AND pd.ID_SUBTIPO_ACTIVO = a.ID_SUBTIPO_ACTIVO
                      AND pd.ID_TIPO_DEP = 2
                    ORDER BY pd.PORC_SEGUNDO_ANO DESC
                ), 0) AS Tasa_Anual,

                -- Depreciación acumulada FISCAL del año ANTERIOR (Diciembre) - Subquery para evitar duplicados
                ISNULL((
                    SELECT TOP 1 c.ACUMULADO_HISTORICA
                    FROM calculo c
                    WHERE c.ID_NUM_ACTIVO = a.ID_NUM_ACTIVO
                      AND c.ID_COMPANIA = a.ID_COMPANIA
                      AND c.ID_ANO = @Año_Anterior
                      AND c.ID_MES = 12
                      AND c.ID_TIPO_DEP = 2
                    ORDER BY c.ACUMULADO_HISTORICA DESC
                ), 0) AS Dep_Acum_Inicio_Año,

                -- INPC de adquisición (solo para mexicanos)
                inpc_adq.Indice AS INPC_Adquisicion,

                -- INPC de mitad del ejercicio (junio del año de cálculo)
                inpc_mitad.Indice AS INPC_Mitad_Ejercicio

            FROM activo a

            -- Join con tipo_activo
            INNER JOIN tipo_activo ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

            -- Join con país
            INNER JOIN pais p ON a.ID_PAIS = p.ID_PAIS

            -- Join con moneda
            LEFT JOIN moneda m ON a.ID_MONEDA = m.ID_MONEDA

            -- INPC de adquisición (solo para mexicanos, ID_PAIS = 1)
            -- Filtrado por grupo simulación 8
            LEFT JOIN INPC2 inpc_adq
                ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
                AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
                AND inpc_adq.Id_Pais = 1
                AND inpc_adq.Id_Grupo_Simulacion = 8

            -- INPC de mitad del ejercicio (junio del año actual)
            -- Filtrado por grupo simulación 8
            LEFT JOIN INPC2 inpc_mitad
                ON inpc_mitad.Anio = @Año_Calculo
                AND inpc_mitad.Mes = 6
                AND inpc_mitad.Id_Pais = 1
                AND inpc_mitad.Id_Grupo_Simulacion = 8

            WHERE a.ID_COMPANIA = @ID_Compania  -- Filtrar solo por compañía solicitada
              AND (a.STATUS = 'A' OR (a.STATUS = 'B' AND YEAR(a.FECHA_BAJA) = @Año_Calculo))  -- Activos activos O dados de baja en el año
              AND a.ID_NUM_ACTIVO IN (
                  -- ========================================
                  -- Compañía 188 - EXTRANJEROS ACTIVOS (10)
                  -- ========================================
                  44073, 44117, 44128, 44130, 44156,
                  44159, 44161, 44169, 44172, 44402,

                  -- ========================================
                  -- Compañía 188 - EXTRANJEROS BAJA 2024 (2)
                  -- ========================================
                  160761,  -- Baja ene-2024
                  204091,  -- Baja jul-2024

                  -- ========================================
                  -- Compañía 188 - NACIONALES ACTIVOS (10)
                  -- ========================================
                  50847, 50855, 50893, 50894, 50899,
                  50909, 50912, 50927, 50967, 50974,

                  -- ========================================
                  -- Compañía 188 - NACIONALES BAJA 2024 (2)
                  -- ========================================
                  192430,  -- Baja feb-2024
                  201213,  -- Baja jul-2024

                  -- ========================================
                  -- Compañía 122 - EXTRANJEROS ACTIVOS (10)
                  -- ========================================
                  107002, 107009, 107012, 107014, 107028,
                  107036, 107045, 107055, 107057, 107069,

                  -- ========================================
                  -- Compañía 122 - EXTRANJEROS BAJA 2024 (2)
                  -- ========================================
                  122234,  -- Baja ene-2024
                  122331,  -- Baja jul-2024

                  -- ========================================
                  -- Compañía 123 - NACIONALES ACTIVOS (10)
                  -- ========================================
                  110380, 110387, 110390, 110392, 110406,
                  110414, 110423, 110433, 110435, 110447,

                  -- ========================================
                  -- Compañía 123 - NACIONALES BAJA 2024 (2)
                  -- ========================================
                  158224,  -- Baja ene-2024
                  158456,  -- Baja ago-2024

                  -- ========================================
                  -- Compañía 12 - EXTRANJEROS ACTIVOS (5)
                  -- ========================================
                  70590, 70600, 70616, 70620, 70640,

                  -- ========================================
                  -- Compañía 12 - EXTRANJEROS BAJA 2024 (2)
                  -- ========================================
                  93551,  -- Baja abr-2024
                  83687,  -- Baja jul-2024

                  -- ========================================
                  -- Compañía 12 - NACIONALES ACTIVOS (5)
                  -- ========================================
                  70001, 70002, 70003, 70004, 70005,

                  -- ========================================
                  -- Compañía 12 - NACIONALES BAJA 2024 (2)
                  -- ========================================
                  70157,   -- Baja mar-2024
                  128908   -- Baja jul-2024

                  -- TOTAL: 62 activos
                  -- Desglose: 50 activos + 12 bajas en 2024
                  -- Todos válidos: sin ERROR DE DEDO
              )
              AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST('{añoCalculo}-12-31' AS DATE))
              AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST('{añoCalculo}-01-01' AS DATE))
            ORDER BY a.ID_COMPANIA, a.ID_NUM_ACTIVO", conn);

        // Pasar parámetro de compañía para filtrar solo activos de esa compañía
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
