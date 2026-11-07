import boto3
import uuid
from datetime import datetime, timezone
from decimal import Decimal

# Initialize AWS service clients
translate = boto3.client("translate")
comprehend = boto3.client("comprehend")

# Initialize DynamoDB
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("TranslationLogs")


def lambda_handler(event, context):

    intent = event["sessionState"]["intent"]

    source_text = intent["slots"]["SourceText"]["value"]["interpretedValue"]
    target_language = intent["slots"]["TargetLanguage"]["value"]["interpretedValue"]

    language_codes = {
        "hindi": "hi",
        "french": "fr",
        "spanish": "es"
    }

    target_code = language_codes.get(target_language.lower())

    # Detect source language
    detection = comprehend.detect_dominant_language(
        Text=source_text
    )

    detected_language = detection["Languages"][0]["LanguageCode"]
    confidence = detection["Languages"][0]["Score"]

    print("Detected language:", detected_language)
    print("Confidence score:", confidence)

    # Check detection confidence
    if confidence < 0.7:

        intent["state"] = "Fulfilled"

        return {
            "sessionState": {
                "dialogAction": {"type": "Close"},
                "intent": intent
            },
            "messages": [{
                "contentType": "PlainText",
                "content": "I'm not confident enough to identify the language. Please provide a longer or clearer sentence."
            }]
        }

    # Translate text
    response = translate.translate_text(
        Text=source_text,
        SourceLanguageCode="auto",
        TargetLanguageCode=target_code
    )

    translated_text = response["TranslatedText"]

    # Generate request ID and timestamp
    request_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    # Save translation in DynamoDB
    table.put_item(
        Item={
            "request_id": request_id,
            "source_text": source_text,
            "detected_language": detected_language,
            "confidence": Decimal(str(confidence)),
            "target_language": target_language,
            "translated_text": translated_text,
            "timestamp": timestamp
        }
    )

    print("Translation successfully logged in DynamoDB:", request_id)

    intent["state"] = "Fulfilled"

    return {
        "sessionState": {
            "dialogAction": {"type": "Close"},
            "intent": intent
        },
        "messages": [{
            "contentType": "PlainText",
            "content": translated_text
        }]
    }