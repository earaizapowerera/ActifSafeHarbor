#!/usr/bin/env dotnet-script
#r "nuget: ClosedXML, 0.105.0"

using ClosedXML.Excel;

var excelPath = "/Users/enrique/ActifRMF/Propuesta reporte Calculo AF.xlsx";
using var workbook = new XLWorkbook(excelPath);

// Analizar hoja "Activos Extranjeros" que es la que nos interesa
var worksheet = workbook.Worksheet("Activos Extranjeros");
var range = worksheet.RangeUsed();

Console.WriteLine("═══════════════════════════════════════════════════════════");
Console.WriteLine("ACTIVOS EXTRANJEROS - ANÁLISIS COMPLETO");
Console.WriteLine("═══════════════════════════════════════════════════════════\n");

// Encontrar fila de encabezados
int headerRow = 5;  // Basado en el análisis anterior

Console.WriteLine($"TODOS LOS ENCABEZADOS (Fila {headerRow}):\n");
var headers = new List<string>();
for (int col = 1; col <= range.ColumnCount(); col++)
{
    var header = worksheet.Cell(headerRow, col).GetString();
    headers.Add(header);
    if (!string.IsNullOrWhiteSpace(header))
    {
        Console.WriteLine($"  Col {col,2} ({GetColumnLetter(col)}): {header}");
    }
}

Console.WriteLine($"\n\nPRIMERAS 5 FILAS DE DATOS CON TODAS LAS COLUMNAS:\n");

for (int row = headerRow + 1; row <= Math.Min(headerRow + 5, range.RowCount()); row++)
{
    Console.WriteLine($"═══ FILA {row} ═══");
    for (int col = 1; col <= range.ColumnCount(); col++)
    {
        var cell = worksheet.Cell(row, col);
        var value = cell.GetString();
        var header = headers[col - 1];

        if (!string.IsNullOrWhiteSpace(value) || cell.HasFormula)
        {
            string formulaInfo = cell.HasFormula ? $" [= {cell.FormulaA1}]" : "";
            Console.WriteLine($"  {GetColumnLetter(col)}{row} {header,-45}: {value}{formulaInfo}");
        }
    }
    Console.WriteLine();
}

Console.WriteLine("\n\n═══════════════════════════════════════════════════════════");
Console.WriteLine("ACTIVOS MEXICANOS - ANÁLISIS COMPLETO");
Console.WriteLine("═══════════════════════════════════════════════════════════\n");

var worksheetMX = workbook.Worksheet("Activos Mexicanos");
var rangeMX = worksheetMX.RangeUsed();

Console.WriteLine($"TODOS LOS ENCABEZADOS (Fila {headerRow}):\n");
var headersMX = new List<string>();
for (int col = 1; col <= rangeMX.ColumnCount(); col++)
{
    var header = worksheetMX.Cell(headerRow, col).GetString();
    headersMX.Add(header);
    if (!string.IsNullOrWhiteSpace(header))
    {
        Console.WriteLine($"  Col {col,2} ({GetColumnLetter(col)}): {header}");
    }
}

Console.WriteLine($"\n\nPRIMERAS 5 FILAS DE DATOS CON TODAS LAS COLUMNAS:\n");

for (int row = headerRow + 1; row <= Math.Min(headerRow + 5, rangeMX.RowCount()); row++)
{
    Console.WriteLine($"═══ FILA {row} ═══");
    for (int col = 1; col <= rangeMX.ColumnCount(); col++)
    {
        var cell = worksheetMX.Cell(row, col);
        var value = cell.GetString();
        var header = headersMX[col - 1];

        if (!string.IsNullOrWhiteSpace(value) || cell.HasFormula)
        {
            string formulaInfo = cell.HasFormula ? $" [= {cell.FormulaA1}]" : "";
            Console.WriteLine($"  {GetColumnLetter(col)}{row} {header,-45}: {value}{formulaInfo}");
        }
    }
    Console.WriteLine();
}

static string GetColumnLetter(int columnNumber)
{
    string columnName = "";

    while (columnNumber > 0)
    {
        int modulo = (columnNumber - 1) % 26;
        columnName = Convert.ToChar('A' + modulo) + columnName;
        columnNumber = (columnNumber - modulo) / 26;
    }

    return columnName;
}
