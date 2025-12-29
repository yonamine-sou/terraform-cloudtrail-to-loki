# ==============================================================================
# Outputs
# ==============================================================================

# ------------------------------------------------------------------------------
# Lambda関数
# ------------------------------------------------------------------------------

output "lambda_function_arn" {
  description = "Lambda関数のARN"
  value       = aws_lambda_function.promtail.arn
}

output "lambda_function_name" {
  description = "Lambda関数名"
  value       = aws_lambda_function.promtail.function_name
}

# ------------------------------------------------------------------------------
# SQSキュー
# ------------------------------------------------------------------------------

output "sqs_queue_url" {
  description = "メインSQSキューのURL"
  value       = aws_sqs_queue.main.url
}

output "sqs_queue_arn" {
  description = "メインSQSキューのARN"
  value       = aws_sqs_queue.main.arn
}

output "sqs_dlq_url" {
  description = "DLQ（Dead Letter Queue）のURL"
  value       = aws_sqs_queue.dlq.url
}

output "sqs_dlq_arn" {
  description = "DLQ（Dead Letter Queue）のARN"
  value       = aws_sqs_queue.dlq.arn
}

# ------------------------------------------------------------------------------
# S3バケット
# ------------------------------------------------------------------------------

output "lambda_bucket_name" {
  description = "Lambda zipを格納しているS3バケット名"
  value       = aws_s3_bucket.lambda_bucket.id
}
