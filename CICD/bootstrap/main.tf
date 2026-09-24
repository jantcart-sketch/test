# -----------------------------------------------------------------------------
# Fase 0 del README: backend remoto de Terraform (bucket S3 + tabla DynamoDB).
# -----------------------------------------------------------------------------
# Se aplica UNA VEZ, con state LOCAL (no puede usar el backend que él mismo crea).
# Después de aplicar, pipeline/backend.tf y environments/*/backend.tf apuntan aquí
# vía `-backend-config` (ver README).

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project_name}-tfstate"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST" # sin coste fijo, solo por uso
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}
