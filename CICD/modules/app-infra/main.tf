# -----------------------------------------------------------------------------
# Módulo de ejemplo (dummy) para validar el flujo end-to-end del pipeline.
# -----------------------------------------------------------------------------
# Sustituye el contenido de este módulo por la infraestructura real de tu proyecto.
# La convención de nombres (prefijo del proyecto + sufijo de entorno) es lo que debe
# conservarse al ampliar este módulo, para que dev/main puedan convivir sin colisionar
# aunque compartan cuenta, y para poder identificar a qué entorno pertenece cada recurso
# con solo mirar su nombre.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "example" {
  # Los nombres de bucket S3 son globales, por eso se añade el account_id para evitar
  # colisiones si esta plantilla se reutiliza en varios proyectos con el mismo nombre.
  bucket = "${local.name_prefix}-example-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket                  = aws_s3_bucket.example.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
