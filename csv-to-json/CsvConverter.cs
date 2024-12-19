/*
 * ----------------------------------------------------------------------------
 * File: CsvConverter.cs
 * Author: Laurin Ebnöther
 * Created: 14.12.2024
 * Description: Konvertiert CSV in JSON datei
 *
 * Version: 1.0
 * ----------------------------------------------------------------------------
 */

using CsvHelper.Configuration;
using CsvHelper;
using System.Globalization;
using System.Text.Json;

namespace CsvToJsonConverter
{
    public class CsvConverter
    {

        // Convertiert CSV to Json mithilfe eines CsvReaders und eine JsonSerializer
        public static string ConvertCsvToJson(Stream csvStream, string delimiter)
        {
            try
            {
                CsvConfiguration Config = new CsvConfiguration(CultureInfo.InvariantCulture)
                {
                    Delimiter = delimiter,
                    HasHeaderRecord = true,
                };

                using StreamReader StreamReader = new StreamReader(csvStream);
                using CsvReader CsvReader = new CsvReader(StreamReader, Config);
                List<dynamic> CsvData = CsvReader.GetRecords<dynamic>().ToList();

                return JsonSerializer.Serialize(CsvData, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
            }
            catch (Exception e)
            {
                throw new Exception($"Fehler beim konvertieren: {e.Message}", e);
            }
        }

    }
}
