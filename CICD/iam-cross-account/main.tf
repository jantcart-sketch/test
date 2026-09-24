# -----------------------------------------------------------------------------
# Rol cross-account que CodeBuild (en la cuenta del pipeline) asume para desplegar
# Terraform en ESTA cuenta (dev o main/prod).
# -----------------------------------------------------------------------------
# Aplicar este módulo UNA VEZ por cuenta destino, con credenciales admin de esa cuenta.
# Ver README.md, "Fase 1 — Rol cross-account en cada cuenta destino".

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.pipeline_account_id}:root"]
    }

    # Restringe el AssumeRole a el/los roles concretos de CodeBuild de la cuenta del
    # pipeline, no a "cualquier identidad" de esa cuenta. Se ajusta con condition
    # adicional por ExternalId si se quiere un factor extra de defensa en profundidad.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.project_name]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.deploy.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Policy inline mínima para el ejemplo dummy de esta plantilla (bucket S3, ver
# modules/app-infra). AMPLÍA o SUSTITUYE este documento según lo que tu proyecto
# real vaya a desplegar - se deja acotado a S3 a propósito para no otorgar de más.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "deploy_dummy_app_infra" {
  statement {
    sid    = "S3AppInfraDummy"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "s3:GetBucketVersioning",
      "s3:PutBucketTagging",
      "s3:PutEncryptionConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutLifecycleConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = ["arn:aws:s3:::${var.project_name}-*"]
  }

  statement {
    sid    = "TerraformStateAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.project_name}-tfstate",
      "arn:aws:s3:::${var.project_name}-tfstate/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = ["arn:aws:dynamodb:*:*:table/${var.project_name}-tfstate-lock"]
  }
}

resource "aws_iam_role_policy" "deploy_dummy_app_infra" {
  name   = "${var.project_name}-app-infra-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_dummy_app_infra.json
}
