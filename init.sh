#!/bin/bash
# Autor: Ebnöther Laurin
# Datum: 13.12.2024
# Konfigurations-Skript für CSV-zu-JSON-Service mit IAM-Rollen
# Sicherstellen, dass AWS CLI und dotnet CLI installiert sind
# Quelle:
# AWS CLI Dokumentation
# Dotnet CLI Dokumentation
# AWS Lambda Dokumentation
# CsvHelper Dokumentation

if ! command -v aws &> /dev/null; then
    echo "AWS CLI ist nicht installiert. Bitte installieren und konfigurieren Sie es."
    exit 1
fi
if ! command -v dotnet &> /dev/null; then
    echo "Dotnet CLI ist nicht installiert. Bitte installieren Sie es."
    exit 1
fi
# Globale Konfigurationen
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export INPUT_BUCKET_NAME="csv2json-input-bucket-$(uuidgen | cut -d'-' -f1)"
export OUTPUT_BUCKET_NAME="csv2json-output-bucket-$(uuidgen | cut -d'-' -f1)"
export LAMBDA_FUNCTION_NAME="csv-to-json-converter"
export LAMBDA_ROLE_NAME="LabRole"
export LAMBDA_ROLE_ARN="arn:aws:iam::$ACCOUNTID:role/$LAMBDA_ROLE_NAME"
export PROJECT_PATH="/home/vmadmin/Downloads/csv-to-json-master/csv-to-json"
export AWS_REGION="us-east-1"
export CSV_FILE="sample.csv"
export DOWNLOADED_JSON_FILE="output.json"

# CSV Trennzeichen
export CSV_DELIMITER=","
# Funktion zur Erstellung eines S3-Buckets
erstelle_bucket() {
    local BUCKET_NAME=$1
    echo "Prüfe, ob der Bucket '$BUCKET_NAME' existiert..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "Bucket '$BUCKET_NAME' existiert bereits. Überspringe Erstellung."
    else
        echo "Erstelle den Bucket '$BUCKET_NAME'..."
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
        if [ $? -eq 0 ]; then
            echo "Bucket '$BUCKET_NAME' erfolgreich erstellt."
        else
            echo "Fehler beim Erstellen des Buckets '$BUCKET_NAME'."
            exit 1
        fi
    fi
}
# S3 Buckets erstellen
erstelle_bucket "$INPUT_BUCKET_NAME"
erstelle_bucket "$OUTPUT_BUCKET_NAME"
# Lambda-Funktion bereitstellen
deploy_lambda_function() {
    echo "Bereitstellung der Lambda-Funktion '$LAMBDA_FUNCTION_NAME'..."
    if ! dotnet lambda deploy-function \
        --project-location "$PROJECT_PATH" \
        --function-role "$LAMBDA_ROLE_ARN" \
        --region "$AWS_REGION" \
		--environment-variables "DESTINATION_BUCKET=$OUTPUT_BUCKET_NAME,CSV_DELIMITER=$CSV_DELIMITER" \
        "$LAMBDA_FUNCTION_NAME"; then
        echo "Fehler beim Bereitstellen der Lambda-Funktion."
        exit 1
    fi
    echo "Lambda-Funktion '$LAMBDA_FUNCTION_NAME' erfolgreich bereitgestellt."
}
# Lambda-Funktion bereitstellen
deploy_lambda_function
# Lambda-Funktion ARN abrufen
ROLE_AMAZON_RESOURCE_NAME=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.FunctionArn' --output text)
if [ -z "$ROLE_AMAZON_RESOURCE_NAME" ]; then
    echo "Fehler: ARN der Lambda-Funktion konnte nicht abgerufen werden."
    exit 1
fi
# Berechtigung für Lambda hinzufügen, um S3-Ereignisse auszulösen
echo "Füge Berechtigungen für S3-Trigger hinzu..."
if ! aws lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_NAME} \
	--principal s3.amazonaws.com \
    --statement-id s3invoke \
    --action "lambda:InvokeFunction" \
    --source-arn arn:aws:s3:::${INPUT_BUCKET_NAME} \
	--source-account ${ACCOUNTID} \
    --region "$AWS_REGION"; then
    echo "Fehler beim Hinzufügen der Lambda-Berechtigung."
    exit 1
fi


# S3 Trigger konfigurieren
echo "Konfiguriere S3 Event Trigger..."
if ! aws s3api put-bucket-notification-configuration \
    --bucket "$INPUT_BUCKET_NAME" \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "LambdaFunctionArn": "'"$ROLE_AMAZON_RESOURCE_NAME"'",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".csv"
                        }
                    ]
                }
            }
        }]
    }'; then
    echo "Fehler beim Konfigurieren des S3 Event Triggers."
    exit 1
fi
echo "Skript erfolgreich abgeschlossen."

echo "Lambda-Trigger hinzugefügt: Uploads in ${INPUT_BUCKET_NAME} werden automatisch verarbeitet."

echo "Beispiel-CSV-Datei erstellt: ${CSV_FILE}"

# CSV-Datei in den Input Bucket hochladen
echo "Lade CSV-Datei '${CSV_FILE}' in den Bucket '${INPUT_BUCKET_NAME}' hoch..."
aws s3 cp ${CSV_FILE} s3://${INPUT_BUCKET_NAME}/
echo "CSV-Datei erfolgreich hochgeladen."

# Warte auf die Lambda Funktion
echo "Warte auf die Verarbeitung..."
sleep 10 

# JSON-Datei aus dem Output-Bucket herunterladen
echo "Lade JSON-Datei aus dem Output-Bucket herunter..."

# Überprüfen, ob der Output-Bucket Dateien enthält
OUTPUT_KEY=$(aws s3api list-objects --bucket ${OUTPUT_BUCKET_NAME} --query "Contents[0].Key" --output text)

if [ "$OUTPUT_KEY" == "None" ] || [ -z "$OUTPUT_KEY" ]; then
  echo "Keine JSON-Datei im Output-Bucket gefunden!"
  exit 1
fi

# Datei herunterladen
aws s3 cp s3://${OUTPUT_BUCKET_NAME}/${OUTPUT_KEY} ${DOWNLOADED_JSON_FILE}

if [ $? -eq 0 ]; then
  echo "JSON-Datei erfolgreich heruntergeladen: ${DOWNLOADED_JSON_FILE}"
else
  echo "Fehler beim Herunterladen der JSON-Datei!"
  exit 1
fi

# JSON-Datei anzeigen
echo "Inhalt der JSON-Datei:"
cat ${DOWNLOADED_JSON_FILE}

echo "Setup abgeschlossen!"
