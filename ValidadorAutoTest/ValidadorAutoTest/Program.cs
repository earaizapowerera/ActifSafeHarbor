using Microsoft.Data.SqlClient;

var connectionString = "Server=dbdev.powerera.com;Database=Actif_RMF;User Id=earaiza;Password=VgfN-n4ju?H1Z4#JFRE;TrustServerCertificate=True;";

Console.WriteLine("===================================================================================");
Console.WriteLine("VALIDADOR AUTOTEST - ActifRMF v2.4.0");
Console.WriteLine("Compara valores calculados vs valores esperados");
Console.WriteLine("===================================================================================\n");

int totalCasos = 0;
int casosOK = 0;
int casosError = 0;
var errores = new List<string>();

using (var connection = new SqlConnection(connectionString))
{
    await connection.OpenAsync();
    Console.WriteLine("✅ Conectado a base de datos\n");

    // Obtener todos los casos activos
    var query = @"
        SELECT
            at.Numero_Caso, at.Nombre_Caso, at.ID_NUM_ACTIVO, at.Año_Calculo, at.Tolerancia_Decimal,
            -- Esperados
            at.MOI_Esperado, at.Dep_Acum_Inicio_Esperada, at.Saldo_Inicio_Año_Esperado, at.Dep_Fiscal_Ejercicio_Esperada,
            at.Factor_Actualizacion_Saldo_Esperado, at.Factor_Actualizacion_Dep_Esperado,
            at.Saldo_Actualizado_Esperado, at.Dep_Actualizada_Esperada, at.Valor_Promedio_Esperado, at.Valor_Reportable_MXN_Esperado,
            at.Factor_SH_Esperado, at.Valor_SH_Reportable_Esperado,
            -- Calculados
            c.MOI, c.Dep_Acum_Inicio, c.Saldo_Inicio_Año, c.Dep_Fiscal_Ejercicio,
            c.Factor_Actualizacion_Saldo, c.Factor_Actualizacion_Dep,
            c.Saldo_Actualizado, c.Dep_Actualizada, c.Valor_Promedio, c.Valor_Reportable_MXN,
            c.Factor_SH, c.Valor_SH_Reportable
        FROM AutoTest at
        LEFT JOIN Calculo_RMF c ON c.ID_NUM_ACTIVO = at.ID_NUM_ACTIVO AND c.Año_Calculo = at.Año_Calculo
        WHERE at.Activo = 1
        ORDER BY at.Numero_Caso";

    using (var cmd = new SqlCommand(query, connection))
    using (var reader = await cmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            totalCasos++;
            var numeroCaso = reader.GetInt32(0);
            var nombreCaso = reader.GetString(1);
            var folio = reader.GetInt32(2);
            var año = reader.GetInt32(3);
            var tolerancia = reader.GetDecimal(4);

            Console.WriteLine($"-----------------------------------------------------------------------------------");
            Console.WriteLine($"CASO {numeroCaso}: {nombreCaso}");
            Console.WriteLine($"Folio: {folio} | Año: {año}");
            Console.WriteLine($"-----------------------------------------------------------------------------------");

            bool casoOk = true;
            var erroresCaso = new List<string>();

            if (reader.IsDBNull(17))
            {
                Console.WriteLine($"❌ ERROR: No existe cálculo para folio {folio} año {año}");
                casosError++;
                errores.Add($"Caso {numeroCaso} (Folio {folio}): No existe cálculo en Calculo_RMF");
                continue;
            }

            // Comparar campos
            CompararCampo("MOI", reader, 5, 17, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Dep_Acum_Inicio", reader, 6, 18, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Saldo_Inicio_Año", reader, 7, 19, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Dep_Fiscal_Ejercicio", reader, 8, 20, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Factor_Actualizacion_Saldo", reader, 9, 21, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Factor_Actualizacion_Dep", reader, 10, 22, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Saldo_Actualizado", reader, 11, 23, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Dep_Actualizada", reader, 12, 24, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Valor_Promedio", reader, 13, 25, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Valor_Reportable_MXN", reader, 14, 26, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Factor_SH", reader, 15, 27, tolerancia, erroresCaso, ref casoOk);
            CompararCampo("Valor_SH_Reportable", reader, 16, 28, tolerancia, erroresCaso, ref casoOk);

            if (casoOk)
            {
                Console.WriteLine("✅ CASO OK - Todos los campos coinciden\n");
                casosOK++;
            }
            else
            {
                Console.WriteLine($"❌ CASO ERROR - {erroresCaso.Count} diferencias encontradas:");
                foreach (var error in erroresCaso)
                {
                    Console.WriteLine($"   {error}");
                    errores.Add($"Caso {numeroCaso} (Folio {folio}): {error}");
                }
                Console.WriteLine();
                casosError++;
            }
        }
    }
}

Console.WriteLine("===================================================================================");
Console.WriteLine("RESUMEN DE VALIDACIÓN");
Console.WriteLine("===================================================================================");
Console.WriteLine($"Total casos:        {totalCasos}");
Console.WriteLine($"Casos OK:           {casosOK} ✅");
Console.WriteLine($"Casos con ERROR:    {casosError} ❌");
Console.WriteLine($"Porcentaje éxito:   {(totalCasos > 0 ? (casosOK * 100.0 / totalCasos) : 0):F2}%");
Console.WriteLine("===================================================================================\n");

if (errores.Count > 0)
{
    Console.WriteLine("DETALLE DE ERRORES:");
    Console.WriteLine("-----------------------------------------------------------------------------------");
    foreach (var error in errores)
        Console.WriteLine($"• {error}");
    Console.WriteLine();
}

Environment.ExitCode = casosError > 0 ? 1 : 0;

void CompararCampo(string nombreCampo, SqlDataReader reader, int idxEsperado, int idxCalculado,
                   decimal tolerancia, List<string> errores, ref bool casoOk)
{
    if (reader.IsDBNull(idxEsperado) || reader.IsDBNull(idxCalculado))
    {
        if (reader.IsDBNull(idxEsperado) && reader.IsDBNull(idxCalculado))
        {
            Console.WriteLine($"   {nombreCampo,-30} ✅ NULL = NULL");
            return;
        }
        var esperado = reader.IsDBNull(idxEsperado) ? "NULL" : reader.GetDecimal(idxEsperado).ToString("N2");
        var calculado = reader.IsDBNull(idxCalculado) ? "NULL" : reader.GetDecimal(idxCalculado).ToString("N2");
        Console.WriteLine($"   {nombreCampo,-30} ❌ Esperado: {esperado} | Calculado: {calculado}");
        errores.Add($"{nombreCampo}: Esperado {esperado}, Calculado {calculado}");
        casoOk = false;
        return;
    }

    var valorEsperado = reader.GetDecimal(idxEsperado);
    var valorCalculado = reader.GetDecimal(idxCalculado);
    var diferencia = Math.Abs(valorEsperado - valorCalculado);

    if (diferencia <= tolerancia)
        Console.WriteLine($"   {nombreCampo,-30} ✅ {valorCalculado:N4}");
    else
    {
        Console.WriteLine($"   {nombreCampo,-30} ❌ Esperado: {valorEsperado:N4} | Calc: {valorCalculado:N4} | Diff: {diferencia:N4}");
        errores.Add($"{nombreCampo}: Diferencia {diferencia:N4} (tolerancia: {tolerancia:N2})");
        casoOk = false;
    }
}
