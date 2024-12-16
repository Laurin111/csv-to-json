#!/bin/bash

# Autor: Ebnöther Laurin
# Datum: 13.12.2024
# Konfigurations-Skript für CSV-zu-JSON-Service mit IAM-Rollen

# Sicherstellen, dass AWS CLI installiert ist
if ! command -v aws &> /dev/null
then
    echo "AWS CLI ist nicht installiert. Bitte installieren und konfigurieren Sie es."
    exit 1
fi

# Bucket-Namen dynamisch generieren (global eindeutige Namen)
export INPUT_BUCKET_NAME="csv2json-input-bucket-$(uuidgen | cut -d'-' -f1)"
export OUTPUT_BUCKET_NAME="csv2json-output-bucket-$(uuidgen | cut -d'-' -f1)"

# CSV Trennzeichen
export CSV_DELIMITER="," # Standardtrennzeichen

# Konfigurationen müssen mit "aws-lambda-tools-default.json" übereinstimmen
export LAMBDA_FUNCTION_NAME="csv-to-json-converter"
export LAMBDA_ROLE_NAME="LabRole"  
export LAMBDA_HANDLER="CsvToJsonConverter::CsvToJsonConverter.Function::FunctionHandler"
export LAMBDA_RUNTIME="dotnet8"
export LAMBDA_TIMEOUT=30
export LAMBDA_MEMORY=512
export AWS_REGION="us-east-1"

# S3 Bucket erstellen Funktion
erstelle_bucket() {
    local BUCKET_NAME=$1
    echo "Prüfe, ob der Bucket '$BUCKET_NAME' existiert..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "Bucket '$BUCKET_NAME' existiert bereits. Überspringe Erstellung."
    else
        echo "Bucket '$BUCKET_NAME' existiert nicht. Erstelle den Bucket..."
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" 
#            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        if [ $? -eq 0 ]; then
            echo "Bucket '$BUCKET_NAME' erfolgreich erstellt."
        else
            echo "Fehler beim Erstellen des Buckets '$BUCKET_NAME'. Prüfe den Namen und die Region."
            exit 1
        fi
    fi
}

# S3 Buckets erstellen
erstelle_bucket "$INPUT_BUCKET_NAME"
erstelle_bucket "$OUTPUT_BUCKET_NAME"

# Erstellen der C# Lambda-Funktion
echo
echo "Lambda Funktion wird erstellt..."

# Wechsel in das Projektverzeichnis
cd /home/vmadmin/Downloads/ || { echo "Projektverzeichnis nicht gefunden!"; exit 1; }

# Kompilieren und Verpacken der Lambda-Funktion
if ! dotnet lambda package \
    --configuration Release \
    --framework net8.0 \
    --output-package /home/vmadmin/Downloads/csv-to-json-master.zip \
    --verbosity minimal; then
    echo "Fehler beim Verpacken der Lambda-Funktion."
    exit 1
fi

# Zurück ins Hauptverzeichnis
cd /home/vmadmin/ || { echo "Hauptverzeichnis nicht gefunden!"; exit 1; }

# Bereitstellung der Lambda-Funktion
echo
echo "Bereitstellung der Lambda-Funktion '$LAMBDA_FUNCTION_NAME'..."

# ARN der IAM-Rolle abrufen
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name $LAMBDA_ROLE_NAME --query Role.Arn --output text 2>/dev/null)
if [ -z "$LAMBDA_ROLE_ARN" ]; then
    echo "Fehler: IAM-Rolle '$LAMBDA_ROLE_NAME' nicht gefunden."
    exit 1
fi

# Konfiguration der Umgebungsvariablen als JSON
LAMBDA_ENVIRONMENT="{
    \"Variables\": {
        \"DESTINATION_BUCKET\": \"$OUTPUT_BUCKET_NAME\",
        \"CSV_DELIMITER\": \"$CSV_DELIMITER\"
    }
}"

# Lambda-Funktion erstellen
if ! aws lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime "$LAMBDA_RUNTIME" \
    --handler "$LAMBDA_HANDLER" \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file fileb:///home/vmadmin/Downloads/csv-to-json-master.zip \
    --timeout "$LAMBDA_TIMEOUT" \
    --memory-size "$LAMBDA_MEMORY" \
    --environment "$LAMBDA_ENVIRONMENT" \
    --region "$AWS_REGION"; then
    echo "Fehler bei der Bereitstellung der Lambda-Funktion."
    exit 1
fi

# S3 Event Trigger einrichten
echo
echo "Erstelle S3 Event Trigger..."

# Berechtigung für Lambda hinzufügen, um S3-Ereignisse auszulösen
if ! aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id S3Trigger \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$INPUT_BUCKET_NAME" \
    --region "$AWS_REGION"; then
    echo "Fehler beim Hinzufügen der Lambda-Berechtigung."
    exit 1
fi

# Amazon Resource Name (ARN) der Lambda-Funktion abrufen
ROLE_AMAZON_RESOURCE_NAME=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.FunctionArn' --output text)
if [ -z "$ROLE_AMAZON_RESOURCE_NAME" ]; then
    echo "Fehler: ARN der Lambda-Funktion konnte nicht abgerufen werden."
    exit 1
fi

# S3 Trigger konfigurieren
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