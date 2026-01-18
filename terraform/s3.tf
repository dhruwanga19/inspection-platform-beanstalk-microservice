# S3 Bucket for images 

# ==================== S3 BUCKET ====================
resource "aws_s3_bucket" "images" {
  bucket = "inspection-images-${data.aws_caller_identity.current.account_id}-${var.environment}"

  tags = {
    Name = "inspection-images-${var.environment}"
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"] # Restrict to your domain in production
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket for deployment artifacts
resource "aws_s3_bucket" "deployments" {
  bucket = "inspection-platform-deployments-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "inspection-platform-deployments"
  }
}

resource "aws_s3_bucket_versioning" "deployments" {
  bucket = aws_s3_bucket.deployments.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ==================== OUTPUTS ====================
output "s3_images_bucket" {
  description = "S3 bucket for images"
  value       = aws_s3_bucket.images.id
}

output "s3_deployments_bucket" {
  description = "S3 bucket for deployments"
  value       = aws_s3_bucket.deployments.id
}
