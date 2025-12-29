# ==============================================================================
# lambda-promtail for CloudTrail
# ==============================================================================
# S3 → SQS → Lambda → Loki の構成でCloudTrailログをLokiに転送
# ==============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
}

# ==============================================================================
# Lambda用S3バケット（プリビルドzipを格納）
# ==============================================================================
resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = "${var.prefix}-"

  tags = {
    Name = "${var.prefix}-lambda-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# lambda-promtail.zipをローカルからS3に自動アップロード
# ダウンロード元: https://grafanalabs-cf-templates.s3.amazonaws.com/lambda-promtail/lambda-promtail.zip
# terraform applyで自動的にS3にアップロードされます
resource "aws_s3_object" "lambda_promtail_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "lambda-promtail.zip"
  source = "${path.module}/lambda-promtail.zip"
  etag   = filemd5("${path.module}/lambda-promtail.zip")

  tags = {
    Name = "lambda-promtail-deployment-package"
  }
}

# ==============================================================================
# IAM Role for Lambda
# ==============================================================================
resource "aws_iam_role" "lambda_role" {
  name = "${var.prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.prefix}-role"
  }
}

# CloudWatch Logs書き込み権限
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudTrailバケット読み取り権限
resource "aws_iam_role_policy" "s3_read" {
  name = "s3-read-cloudtrail"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
      Resource = "arn:aws:s3:::${var.cloudtrail_bucket_name}/*"
    }]
  })
}

# SQS操作権限
resource "aws_iam_role_policy" "sqs" {
  name = "sqs-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

# ==============================================================================
# Lambda Function
# ==============================================================================
resource "aws_lambda_function" "promtail" {
  function_name = var.prefix
  role          = aws_iam_role.lambda_role.arn

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_promtail_zip.key

  depends_on = [
    aws_s3_object.lambda_promtail_zip,
    aws_cloudwatch_log_group.lambda
  ]

  handler     = "main"
  runtime     = "provided.al2023"
  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      WRITE_ADDRESS = var.write_address
      USERNAME      = var.username
      PASSWORD      = var.password
      BATCH_SIZE    = "131072"
      KEEP_STREAM   = "false"
    }
  }

  tags = {
    Name = var.prefix
  }
}

# Lambda用CloudWatch Logsロググループ
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.prefix}"
  retention_in_days = 14

  tags = {
    Name = "${var.prefix}-logs"
  }
}

# ==============================================================================
# SQS Queue（メイン）
# ==============================================================================
resource "aws_sqs_queue" "main" {
  name = "${var.prefix}-queue"

  message_retention_seconds  = 86400 # 1日
  visibility_timeout_seconds = 300

  # DLQの設定
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # 3回失敗したらDLQへ
  })

  tags = {
    Name = "${var.prefix}-queue"
  }
}

# SQS Queue Policy（S3からの送信を許可）
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.main.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3:::${var.cloudtrail_bucket_name}"
        }
      }
    }]
  })
}

# ==============================================================================
# SQS Dead Letter Queue（失敗時のリカバリ用）
# ==============================================================================
resource "aws_sqs_queue" "dlq" {
  name = "${var.prefix}-dlq"

  message_retention_seconds = 1209600 # 14日間保持

  tags = {
    Name = "${var.prefix}-dlq"
  }
}

# ==============================================================================
# Lambda Event Source Mapping（SQS → Lambda）
# ==============================================================================
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.promtail.arn

  batch_size                         = 20
  maximum_batching_window_in_seconds = 60

  # 処理失敗時はメッセージをキューに戻す
  function_response_types = ["ReportBatchItemFailures"]
}

# ==============================================================================
# S3 Bucket Notification（S3 → SQS）
# ==============================================================================
resource "aws_s3_bucket_notification" "cloudtrail" {
  bucket = var.cloudtrail_bucket_name

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.s3_filter_prefix
    filter_suffix = ".json.gz"
  }

  depends_on = [aws_sqs_queue_policy.main]
}