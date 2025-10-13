using ClosedXML.Excel;

namespace ActifRMF.Services;

public class ExcelAnalyzer
{
    public void AnalyzeExcelFile(string filePath)
    {
        using var workbook = new XLWorkbook(filePath);

        Console.WriteLine("========================================");
        Console.WriteLine("ANÁLISIS DEL ARCHIVO EXCEL");
        Console.WriteLine($"Archivo: {Path.GetFileName(filePath)}");
        Console.WriteLine("========================================\n");

        Console.WriteLine($"Total de hojas: {workbook.Worksheets.Count}\n");

        foreach (var worksheet in workbook.Worksheets)
        {
            Console.WriteLine($"╔════════════════════════════════════════╗");
            Console.WriteLine($"║  HOJA: {worksheet.Name,-33}║");
            Console.WriteLine($"╚════════════════════════════════════════╝\n");

            var range = worksheet.RangeUsed();

            if (range != null)
            {
                Console.WriteLine($"Dimensiones: {range.RowCount()} filas x {range.ColumnCount()} columnas\n");

                // Encontrar fila de encabezados (buscar la primera fila con "Tipo" o similar)
                int headerRow = 1;
                for (int row = 1; row <= Math.Min(10, range.RowCount()); row++)
                {
                    var firstCell = worksheet.Cell(row, 1).GetString().ToLower();
                    if (firstCell.Contains("tipo") || firstCell == "af" ||
                        worksheet.Cell(row, 2).GetString().ToLower().Contains("fecha"))
                    {
                        headerRow = row;
                        break;
                    }
                }

                Console.WriteLine($"Fila de encabezados detectada: {headerRow}\n");

                // Mostrar TODOS los encabezados
                Console.WriteLine("ENCABEZADOS:");
                Console.WriteLine(new string('-', 100));
                var headers = new List<string>();
                for (int col = 1; col <= range.ColumnCount(); col++)
                {
                    var cell = worksheet.Cell(headerRow, col);
                    var cellValue = cell.GetString();
                    var columnLetter = cell.Address.ColumnLetter;

                    headers.Add(cellValue);

                    if (!string.IsNullOrWhiteSpace(cellValue))
                    {
                        Console.WriteLine($"  {columnLetter} (Col {col,2}): {cellValue}");
                    }
                }

                // Mostrar primeras filas de datos con TODAS las columnas
                Console.WriteLine($"\nPRIMERAS FILAS DE DATOS (desde fila {headerRow + 1}):");
                Console.WriteLine(new string('=', 100));

                int dataStartRow = headerRow + 1;
                int maxRowsToShow = Math.Min(dataStartRow + 4, range.RowCount());

                for (int row = dataStartRow; row <= maxRowsToShow; row++)
                {
                    Console.WriteLine($"\n▶ FILA {row}:");
                    Console.WriteLine(new string('-', 100));

                    for (int col = 1; col <= range.ColumnCount(); col++)
                    {
                        var cell = worksheet.Cell(row, col);
                        var cellValue = cell.GetString();
                        var header = headers[col - 1];
                        var columnLetter = cell.Address.ColumnLetter;

                        // Detectar si es fórmula
                        var hasFormula = cell.HasFormula;
                        var formulaDisplay = hasFormula ? $" [FÓRMULA: {cell.FormulaA1}]" : "";

                        if (!string.IsNullOrWhiteSpace(cellValue) || hasFormula)
                        {
                            Console.WriteLine($"  {columnLetter} {header,-40}: {cellValue}{formulaDisplay}");
                        }
                    }
                }

                // Sección especial: ANÁLISIS DE FÓRMULAS
                Console.WriteLine($"\n\n╔════════════════════════════════════════╗");
                Console.WriteLine($"║  ANÁLISIS DE FÓRMULAS                  ║");
                Console.WriteLine($"╚════════════════════════════════════════╝\n");

                Console.WriteLine("Buscando fórmulas en las primeras 10 filas...\n");

                for (int row = headerRow + 1; row <= Math.Min(headerRow + 10, range.RowCount()); row++)
                {
                    bool hasAnyFormula = false;
                    var formulasInRow = new List<string>();

                    for (int col = 1; col <= range.ColumnCount(); col++)
                    {
                        var cell = worksheet.Cell(row, col);
                        if (cell.HasFormula)
                        {
                            hasAnyFormula = true;
                            var header = headers[col - 1];
                            var columnLetter = cell.Address.ColumnLetter;
                            formulasInRow.Add($"    {columnLetter} ({header}): {cell.FormulaA1} = {cell.GetString()}");
                        }
                    }

                    if (hasAnyFormula)
                    {
                        Console.WriteLine($"  Fila {row}:");
                        foreach (var formula in formulasInRow)
                        {
                            Console.WriteLine(formula);
                        }
                        Console.WriteLine();
                    }
                }
            }
            else
            {
                Console.WriteLine("Hoja vacía");
            }

            Console.WriteLine($"\n{new string('═', 100)}\n");
        }
    }
}
