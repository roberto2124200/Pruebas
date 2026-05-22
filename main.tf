terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Región AWS
provider "aws" {
  region = var.aws_region
}

# Variables principales
variable "aws_region" {
  description = "Region AWS donde se desplegaran los recursos"
  type        = string
  default     = "us-east-2"
}

variable "log_bucket_prefix" {
  description = "Prefijo para el bucket S3 de logs hacia Microsoft Sentinel"
  type        = string
  default     = "sentinel-aws-logs-"
}

variable "sqs_queue_name" {
  description = "Nombre de la cola SQS para notificaciones de S3 hacia Sentinel"
  type        = string
  default     = "sentinel-aws-s3-logs-queue"
}

variable "cloudtrail_name" {
  description = "Nombre del trail de CloudTrail"
  type        = string
  default     = "sentinel-cloudtrail"
}

# Datos de cuenta y region
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Bucket S3 privado para logs
resource "aws_s3_bucket" "sentinel_logs" {
  bucket_prefix = var.log_bucket_prefix
  force_destroy = true

  tags = {
    Name        = "sentinel-aws-logs"
    Purpose     = "Microsoft Sentinel AWS Logs"
    Environment = "Lab"
  }
}

# Bloqueo de acceso publico
resource "aws_s3_bucket_public_access_block" "sentinel_logs" {
  bucket = aws_s3_bucket.sentinel_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Ownership del bucket
resource "aws_s3_bucket_ownership_controls" "sentinel_logs" {
  bucket = aws_s3_bucket.sentinel_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Versionamiento del bucket
resource "aws_s3_bucket_versioning" "sentinel_logs" {
  bucket = aws_s3_bucket.sentinel_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cifrado por defecto SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "sentinel_logs" {
  bucket = aws_s3_bucket.sentinel_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Prefijos logicos para ordenar fuentes de logs
resource "aws_s3_object" "prefix_cloudtrail" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "cloudtrail/"
  content = ""
}

resource "aws_s3_object" "prefix_vpcflow" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "vpcflow/"
  content = ""
}

resource "aws_s3_object" "prefix_guardduty" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "guardduty/"
  content = ""
}

resource "aws_s3_object" "prefix_waf" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "waf/"
  content = ""
}

resource "aws_s3_object" "prefix_cloudwatch" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "cloudwatch/"
  content = ""
}

resource "aws_s3_object" "prefix_eks" {
  bucket  = aws_s3_bucket.sentinel_logs.id
  key     = "eks/"
  content = ""
}

# Cola SQS estandar para notificaciones del bucket S3
resource "aws_sqs_queue" "sentinel_s3_notifications" {
  name                       = var.sqs_queue_name
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 300
  sqs_managed_sse_enabled    = true

  tags = {
    Name        = var.sqs_queue_name
    Purpose     = "Microsoft Sentinel S3 Notifications"
    Environment = "Lab"
  }
}

# Politica de la cola SQS para permitir que S3 publique mensajes
resource "aws_sqs_queue_policy" "allow_s3_send_message" {
  queue_url = aws_sqs_queue.sentinel_s3_notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.sentinel_s3_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.sentinel_logs.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Notificacion S3 hacia SQS cuando lleguen nuevos logs
resource "aws_s3_bucket_notification" "sentinel_logs_to_sqs" {
  bucket = aws_s3_bucket.sentinel_logs.id

  queue {
    queue_arn = aws_sqs_queue.sentinel_s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3_send_message
  ]
}

# Politica del bucket para permitir escritura de CloudTrail
resource "aws_s3_bucket_policy" "allow_cloudtrail_write" {
  bucket = aws_s3_bucket.sentinel_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.sentinel_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.sentinel_logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.sentinel_logs
  ]
}

# CloudTrail escribiendo en S3
resource "aws_cloudtrail" "sentinel_cloudtrail" {
  name                          = var.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.sentinel_logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  depends_on = [
    aws_s3_bucket_policy.allow_cloudtrail_write
  ]

  tags = {
    Name        = var.cloudtrail_name
    Purpose     = "CloudTrail logs for Microsoft Sentinel"
    Environment = "Lab"
  }
}

# Outputs requeridos para configuracion manual en Sentinel
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = data.aws_region.current.name
}

output "s3_log_bucket_name" {
  value = aws_s3_bucket.sentinel_logs.bucket
}

output "s3_log_bucket_arn" {
  value = aws_s3_bucket.sentinel_logs.arn
}

output "sqs_queue_name" {
  value = aws_sqs_queue.sentinel_s3_notifications.name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.sentinel_s3_notifications.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.sentinel_s3_notifications.arn
}

output "cloudtrail_name" {
  value = aws_cloudtrail.sentinel_cloudtrail.name
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.sentinel_cloudtrail.arn
}