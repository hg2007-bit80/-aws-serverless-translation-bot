
terraform {
  backend "s3" {
    bucket       = "translationbot-terraform-state-597619903134-ap-southeast-1"
    key          = "translationbot/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Mumbai provider
provider "aws" {
  region = "ap-south-1"
}

# Singapore provider
provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"
}

# ==========================================
# IAM ROLE
# ==========================================

resource "aws_iam_role" "lambda_translation_role" {
  name        = "LambdaTranslationRole"
  description = "Allows Lambda functions to call AWS services on your behalf."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ==========================================
# IAM PERMISSIONS
# ==========================================

resource "aws_iam_role_policy" "lambda_translation_permissions" {
  name = "LambdaTranslationPermissions"
  role = aws_iam_role.lambda_translation_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "translate:TranslateText",
          "comprehend:DetectDominantLanguage",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]

        Resource = "*"
      },

      {
        Effect = "Allow"

        Action = [
          "dynamodb:PutItem"
        ]

        Resource = aws_dynamodb_table.translation_logs.arn
      }
    ]
  })
}

# ==========================================
# LAMBDA FUNCTION
# ==========================================

resource "aws_lambda_function" "translation_lambda" {
  provider = aws.singapore

  function_name = "TranslationLambda"
  role          = aws_iam_role.lambda_translation_role.arn

  runtime = "python3.14"
  handler = "lambda_function.lambda_handler"

  memory_size = 128
  timeout     = 3

  architectures = ["x86_64"]

  filename         = "${path.module}/lambda_function.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_function.zip")

  # Enable AWS X-Ray active tracing
  tracing_config {
    mode = "Active"
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ==========================================
# AMAZON LEX BOT
# ==========================================

resource "aws_lexv2models_bot" "translation_bot" {
  provider = aws.singapore

  name = "TranslationBot"

  idle_session_ttl_in_seconds = 300

  role_arn = "arn:aws:iam::597619903134:role/service-role/AmazonLexServiceRole-WFEEZG7N2ZO"

  data_privacy {
    child_directed = false
  }
}

# ==========================================
# DYNAMODB TABLE
# ==========================================

resource "aws_dynamodb_table" "translation_logs" {
  provider = aws.singapore

  name         = "TranslationLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }

  tags = {
    Name        = "TranslationLogs"
    Environment = "Learning"
    Project     = "TranslationBot"
  }
}

# ==========================================
# CLOUDWATCH DASHBOARD
# ==========================================

resource "aws_cloudwatch_dashboard" "translation_dashboard" {
  provider = aws.singapore

  dashboard_name = "TranslationBot-Monitoring"

  dashboard_body = jsonencode({
    widgets = [

      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "Lambda Invocations, Errors and Throttles"
          region = "ap-southeast-1"
          period = 300
          stat   = "Sum"

          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "TranslationLambda"],
            ["AWS/Lambda", "Errors", "FunctionName", "TranslationLambda"],
            ["AWS/Lambda", "Throttles", "FunctionName", "TranslationLambda"]
          ]
        }
      },

      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "Lambda Execution Duration"
          region = "ap-southeast-1"
          period = 300
          stat   = "Average"

          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "TranslationLambda"]
          ]
        }
      },

      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "DynamoDB Write Capacity"
          region = "ap-southeast-1"
          period = 300
          stat   = "Sum"

          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "TranslationLogs"]
          ]
        }
      }
    ]
  })
}

# ==========================================
# CLOUDWATCH ALARM - LAMBDA ERRORS
# ==========================================

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  provider = aws.singapore

  alarm_name        = "TranslationLambda-ErrorAlarm"
  alarm_description = "Triggers when TranslationLambda encounters an error."

  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  dimensions = {
    FunctionName = "TranslationLambda"
  }

  treat_missing_data = "notBreaching"
}
