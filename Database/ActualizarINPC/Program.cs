using Microsoft.Data.SqlClient;
using System;
using System.Threading.Tasks;

namespace ActifRMF.ActualizarINPC;

class Program
{
    static async Task Main(string[] args)
    {
        Console.WriteLine("===========================================");
        Console.WriteLine("ACTUALIZAR INPC PARA ACTIVOS NACIONALES");
        Console.WriteLine("===========================================");
        Console.WriteLine();

        // Parámetros
        int idCompania = args.Length > 0 ? int.Parse(args[0]) : 188;
        int añoCalculo = args.Length > 1 ? int.Parse(args[1]) : 2024;

        Console.WriteLine($"Compañía: {idCompania}");
        Console.WriteLine($"Año: {añoCalculo}");
        Console.WriteLine();

        var actualizador = new ActualizadorINPC();
        await actualizador.ActualizarINPC(idCompania, añoCalculo);

        Console.WriteLine();
        Console.WriteLine("Proceso completado.");
    }
}

public class ActualizadorINPC
{
    private const string ConnStrOrigen = "Server=dbdev.powerera.com;Database=actif_web_cima_dev;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";
    private const string ConnStrDestino = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

    public async Task ActualizarINPC(int idCompania, int añoCalculo)
    {
        int totalActualizados = 0;

        Console.WriteLine("Obteniendo activos nacionales de Calculo_RMF...");

        await using var connDestino = new SqlConnection(ConnStrDestino);
        await connDestino.OpenAsync();

        // Obtener activos nacionales de Calculo_RMF
        string queryActivos = @"
            SELECT
                ID_Calculo,
                Fecha_Adquisicion,
                Fecha_Baja,
                MOI,
                Saldo_Inicio_Año,
                Dep_Fiscal_Ejercicio,
                Meses_Uso_En_Ejercicio
            FROM Calculo_RMF
            WHERE ID_Compania = @ID_Compania
              AND Año_Calculo = @Año_Calculo
              AND Tipo_Activo = 'Nacional'
              AND INPCCompra IS NULL";

        await using var cmdActivos = new SqlCommand(queryActivos, connDestino);
        cmdActivos.Parameters.AddWithValue("@ID_Compania", idCompania);
        cmdActivos.Parameters.AddWithValue("@Año_Calculo", añoCalculo);

        await using var reader = await cmdActivos.ExecuteReaderAsync();

        var activos = new System.Collections.Generic.List<(
            long idCalculo,
            DateTime fechaCompra,
            DateTime? fechaBaja,
            decimal moi,
            decimal saldoInicio,
            decimal depEjercicio,
            int mesesUso
        )>();

        while (await reader.ReadAsync())
        {
            activos.Add((
                reader.GetInt64(0),
                reader.GetDateTime(1),
                reader.IsDBNull(2) ? null : reader.GetDateTime(2),
                reader.GetDecimal(3),
                reader.GetDecimal(4),
                reader.GetDecimal(5),
                reader.GetInt32(6)
            ));
        }

        await reader.CloseAsync();

        Console.WriteLine($"Activos a procesar: {activos.Count}");
        Console.WriteLine();

        if (activos.Count == 0)
        {
            Console.WriteLine("No hay activos para procesar (ya tienen INPC o no hay activos nacionales)");
            return;
        }

        // Abrir conexión a base de datos origen para obtener INPC
        await using var connOrigen = new SqlConnection(ConnStrOrigen);
        await connOrigen.OpenAsync();

        // Cargar tablas auxiliares
        var inpcBajas = await CargarINPCBajas(connDestino);
        var inpcSegunMes = await CargarINPCSegunMes(connDestino);

        Console.WriteLine("Procesando activos...");

        foreach (var activo in activos)
        {
            // 1. Obtener INPC de Compra
            decimal? inpcCompra = await ObtenerINPC(connOrigen, activo.fechaCompra.Year, activo.fechaCompra.Month);

            if (inpcCompra == null)
            {
                Console.WriteLine($"  ⚠️ Activo ID={activo.idCalculo}: INPC Compra no encontrado para {activo.fechaCompra:yyyy-MM}");
                continue;
            }

            // 2. Determinar mes INPC a utilizar según lógica SAT
            int? mesUtilizado = DeterminarMesINPC(activo, añoCalculo, inpcBajas, inpcSegunMes);

            if (mesUtilizado == null)
            {
                Console.WriteLine($"  ⚠️ Activo ID={activo.idCalculo}: No se pudo determinar mes INPC utilizado");
                continue;
            }

            // 3. Obtener INPC Utilizado
            decimal? inpcUtilizado = await ObtenerINPC(connOrigen, añoCalculo, mesUtilizado.Value);

            if (inpcUtilizado == null)
            {
                Console.WriteLine($"  ⚠️ Activo ID={activo.idCalculo}: INPC Utilizado no encontrado para {añoCalculo}-{mesUtilizado.Value:D2}");
                continue;
            }

            // 4. Calcular factores de actualización
            decimal factorSaldo = inpcUtilizado.Value / inpcCompra.Value;
            decimal factorDep = inpcUtilizado.Value / inpcCompra.Value;

            // 5. Calcular valores actualizados
            decimal saldoActualizado = activo.saldoInicio * factorSaldo;
            decimal depActualizada = activo.depEjercicio * factorDep;
            decimal valorPromedio = saldoActualizado - (depActualizada * 0.5m);
            decimal proporcion = valorPromedio * (activo.mesesUso / 12.0m);
            decimal prueba10Pct = activo.moi * 0.10m;
            decimal valorReportable = Math.Max(proporcion, prueba10Pct);
            bool aplica10Pct = proporcion <= prueba10Pct;

            // 6. Actualizar en Calculo_RMF
            string queryUpdate = @"
                UPDATE Calculo_RMF
                SET
                    INPCCompra = @INPCCompra,
                    INPCUtilizado = @INPCUtilizado,
                    Factor_Actualizacion_Saldo = @FactorSaldo,
                    Factor_Actualizacion_Dep = @FactorDep,
                    Saldo_Actualizado = @SaldoActualizado,
                    Dep_Actualizada = @DepActualizada,
                    Valor_Promedio = @ValorPromedio,
                    Proporcion = @Proporcion,
                    Valor_Reportable_MXN = @ValorReportable,
                    Aplica_10_Pct = @Aplica10Pct
                WHERE ID_Calculo = @ID_Calculo";

            await using var cmdUpdate = new SqlCommand(queryUpdate, connDestino);
            cmdUpdate.Parameters.AddWithValue("@INPCCompra", inpcCompra.Value);
            cmdUpdate.Parameters.AddWithValue("@INPCUtilizado", inpcUtilizado.Value);
            cmdUpdate.Parameters.AddWithValue("@FactorSaldo", factorSaldo);
            cmdUpdate.Parameters.AddWithValue("@FactorDep", factorDep);
            cmdUpdate.Parameters.AddWithValue("@SaldoActualizado", saldoActualizado);
            cmdUpdate.Parameters.AddWithValue("@DepActualizada", depActualizada);
            cmdUpdate.Parameters.AddWithValue("@ValorPromedio", valorPromedio);
            cmdUpdate.Parameters.AddWithValue("@Proporcion", proporcion);
            cmdUpdate.Parameters.AddWithValue("@ValorReportable", valorReportable);
            cmdUpdate.Parameters.AddWithValue("@Aplica10Pct", aplica10Pct);
            cmdUpdate.Parameters.AddWithValue("@ID_Calculo", activo.idCalculo);

            await cmdUpdate.ExecuteNonQueryAsync();
            totalActualizados++;

            if (totalActualizados % 10 == 0)
            {
                Console.WriteLine($"  Procesados: {totalActualizados}/{activos.Count}");
            }
        }

        Console.WriteLine();
        Console.WriteLine($"✅ TOTAL ACTUALIZADOS: {totalActualizados}");
    }

    private int? DeterminarMesINPC(
        (long idCalculo, DateTime fechaCompra, DateTime? fechaBaja, decimal moi, decimal saldoInicio, decimal depEjercicio, int mesesUso) activo,
        int añoCalculo,
        System.Collections.Generic.Dictionary<int, int> inpcBajas,
        System.Collections.Generic.Dictionary<int, int> inpcSegunMes)
    {
        // CASO 1: Dado de baja en el año
        if (activo.fechaBaja.HasValue && activo.fechaBaja.Value.Year == añoCalculo)
        {
            int mesAnteriorBaja = activo.fechaBaja.Value.AddMonths(-1).Month;
            if (inpcBajas.TryGetValue(mesAnteriorBaja, out int mesINPC))
            {
                return mesINPC;
            }
        }

        // CASO 2: Adquirido en el año
        if (activo.fechaCompra.Year == añoCalculo)
        {
            // Fórmula SAT: mes_medio = ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)
            int mesCompra = activo.fechaCompra.Month;
            int mesMedio = (int)Math.Round((12.0 - (mesCompra - 1)) / 2.0, 0, MidpointRounding.AwayFromZero) + (mesCompra - 1);
            return mesMedio;
        }

        // CASO 3: Activo de años anteriores (Safe Harbor anual = diciembre → junio)
        if (activo.fechaCompra.Year < añoCalculo)
        {
            if (inpcSegunMes.TryGetValue(12, out int mesINPC))  // Mes 12 (diciembre)
            {
                return mesINPC;
            }
        }

        return null;
    }

    private async Task<System.Collections.Generic.Dictionary<int, int>> CargarINPCBajas(SqlConnection conn)
    {
        var dict = new System.Collections.Generic.Dictionary<int, int>();

        string query = "SELECT Id_Mes, Id_MesINPC FROM dbo.INPCbajas";
        await using var cmd = new SqlCommand(query, conn);
        await using var reader = await cmd.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            dict[reader.GetInt32(0)] = reader.GetInt32(1);
        }

        return dict;
    }

    private async Task<System.Collections.Generic.Dictionary<int, int>> CargarINPCSegunMes(SqlConnection conn)
    {
        var dict = new System.Collections.Generic.Dictionary<int, int>();

        string query = "SELECT MesCalculo, MesINPC FROM dbo.INPCSegunMes";
        await using var cmd = new SqlCommand(query, conn);
        await using var reader = await cmd.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            dict[reader.GetInt32(0)] = reader.GetInt32(1);
        }

        return dict;
    }

    private async Task<decimal?> ObtenerINPC(SqlConnection conn, int año, int mes)
    {
        string query = @"
            SELECT TOP 1 Indice
            FROM dbo.inpc2
            WHERE Anio = @Anio
              AND Mes = @Mes
              AND Id_Pais = 1
              AND (Id_Grupo_Simulacion = 1 OR Id_Grupo_Simulacion IS NULL)";

        await using var cmd = new SqlCommand(query, conn);
        cmd.Parameters.AddWithValue("@Anio", año);
        cmd.Parameters.AddWithValue("@Mes", mes);

        object result = await cmd.ExecuteScalarAsync();
        return result != null ? Convert.ToDecimal(result) : null;
    }
}
