/*
 * ----------------------------------------------------------------------------
 * File: Function.cs
 * Author: Laurin Ebnöther
 * Created: 14.12.2024
 * Description: Schnittstelle zwischen Code und AWS Cloud
 *
 * Version: 1.0.1
 * ----------------------------------------------------------------------------
 */

using Amazon.Lambda.Core;
using Amazon.Lambda.S3Events;
using Amazon.S3;
using Amazon.S3.Model;
using Amazon.Lambda.Serialization.SystemTextJson; 

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))]

namespace CsvToJsonConverter
{
    public class Function
    {
        private readonly IAmazonS3 S3Client;
        public string DestinationBucketName { get; set; }
        public string CsvDelimiter { get; set; }

        // Konstruktor wird von AWS Lambda benötigt!
        // Konstruktor erstellt S3Client instanz und holt von der Umgebung den Output-Bucket-Name und das Trennzeichen.
        public Function()
        {
            S3Client = new AmazonS3Client();
            DestinationBucketName = Environment.GetEnvironmentVariable("DESTINATION_BUCKET") 
                ?? throw new InvalidOperationException("Umgebungsvariable fehlt: DESTINATION_BUCKET");
            CsvDelimiter = Environment.GetEnvironmentVariable("CSV_DELIMITER") ?? ",";

        }

        public async Task FunctionHandler(S3Event evnt, ILambdaContext context)
        {
            foreach (var record in evnt.Records)
            {
                try
                {
                    string bucketName = record.S3.Bucket.Name;
                    string fileName = record.S3.Object.Key;

                    //csv Datei von Bucket holen
                    GetObjectRequest csvFile = new GetObjectRequest
                    {
                        BucketName = bucketName,
                        Key = fileName
                    };

                    var response = await S3Client.GetObjectAsync(csvFile);
                    string jsonContent = CsvConverter.ConvertCsvToJson(response.ResponseStream, CsvDelimiter);
                    string outputKey = Path.ChangeExtension(fileName, ".json");

                    // Json File in Output Bucket laden
                    var putRequest = new PutObjectRequest
                    {
                        BucketName = DestinationBucketName,
                        Key = outputKey,
                        ContentType = "application/json",
                        ContentBody = jsonContent
                    };
                    await S3Client.PutObjectAsync(putRequest);
                }
                catch (Exception e)
                {
                    throw new FileNotFoundException($"File wurde nicht gefunden! {e.Message}");
                }
            }
        }

    }
}
