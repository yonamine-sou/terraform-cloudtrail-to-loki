# ------------------------------------------------------------------------------
# 基本設定
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "prefix" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "lambda-promtail"
}

# ------------------------------------------------------------------------------
# Loki設定
# ------------------------------------------------------------------------------
variable "write_address" {
  description = "Loki push endpoint"
  type        = string
}

variable "username" {
  description = "Loki Basic認証ユーザー名"
  type        = string
  default     = ""
}

variable "password" {
  description = "Loki Basic認証パスワード"
  type        = string
  sensitive   = true
  default     = ""
}

# ------------------------------------------------------------------------------
# CloudTrail S3バケット設定
# ------------------------------------------------------------------------------
variable "cloudtrail_bucket_name" {
  description = "CloudTrailログが保存されているS3バケット名"
  type        = string
}

variable "s3_filter_prefix" {
  description = "処理対象のS3オブジェクトプレフィックス（例: AWSLogs/123456789012/CloudTrail/ap-northeast-1/）"
  type        = string
  default     = ""
}
