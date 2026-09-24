# -----------------------------------------------------------------------------
# Secrets Manager: token del remoto Git (valor NO gestionado por Terraform)
# -----------------------------------------------------------------------------
# Terraform crea el "contenedor" del secret pero nunca escribe el valor del token:
# eso se rellena manualmente después del apply (aws secretsmanager put-secret-value),
# para que el token nunca pase por el state de Terraform ni por el repo.

resource "aws_secretsmanager_secret" "git_remote_token" {
  name        = "${var.project_name}/git-remote-token"
  description = var.git_remote_token_secret_description

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # El valor se gestiona fuera de Terraform; evita que un `apply` accidental lo resetee.
    ]
  }
}

# -----------------------------------------------------------------------------
# Cross-account: FUENTE DE VERDAD EXTERNA (fuera de este Terraform)
# -----------------------------------------------------------------------------
# target_account_id / target_role_arn se rellenan con scripts/set-cross-account-target.sh
# (o `aws ssm put-parameter` directo), NUNCA por este Terraform. Esto permite rotar
# cuenta destino, añadir entornos o cambiar el rol asumido sin volver a aplicar el
# pipeline completo. Este módulo solo LEE esos parámetros (deben existir de antemano,
# ver README "Fase 1").

data "aws_ssm_parameter" "target_role_arn" {
  for_each = var.branches

  name = "/${var.project_name}/${each.value.environment}/target_role_arn"
}

# -----------------------------------------------------------------------------
# SSM Parameter Store: configuración no sensible propia del pipeline (SÍ gestionada
# por este Terraform, a diferencia del bloque cross-account de arriba)
# -----------------------------------------------------------------------------
# Jerarquía: /{project_name}/{environment}/{parametro}
# Los buildspecs leen estos parámetros en runtime según la rama que dispara el pipeline.

resource "aws_ssm_parameter" "environment_prefix" {
  for_each = var.branches

  name        = "/${var.project_name}/${each.value.environment}/environment_prefix"
  description = "Prefijo/sufijo de entorno usado para nombrar recursos desplegados por Terraform"
  type        = "String"
  value       = each.value.environment

  tags = var.tags
}

resource "aws_ssm_parameter" "auto_apply" {
  for_each = var.branches

  name        = "/${var.project_name}/${each.value.environment}/auto_apply"
  description = "Si es 'true', el pipeline aplica Terraform sin aprobación manual"
  type        = "String"
  value       = tostring(each.value.auto_apply)

  tags = var.tags
}

resource "aws_ssm_parameter" "git_remote_path" {
  name        = "/${var.project_name}/git_remote_path"
  description = "Owner/repo del remoto Git destino del mirror (agnóstico al proveedor)"
  type        = "String"
  value       = var.git_remote_path

  tags = var.tags
}

resource "aws_ssm_parameter" "git_remote_host" {
  name        = "/${var.project_name}/git_remote_host"
  description = "Host del proveedor Git remoto (ej. github.com, gitlab.com, o self-managed)"
  type        = "String"
  value       = var.git_remote_host

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Backend remoto de Terraform para environments/* — leído por buildspecs/plan.yml
# y apply.yml al hacer `terraform init -backend-config=...` (backend parcial).
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "tf_state_bucket" {
  name        = "/${var.project_name}/tf_state_bucket"
  description = "Bucket S3 del backend remoto de Terraform para environments/*"
  type        = "String"
  value       = var.tf_state_bucket

  tags = var.tags
}

resource "aws_ssm_parameter" "tf_state_lock_table" {
  name        = "/${var.project_name}/tf_state_lock_table"
  description = "Tabla DynamoDB de locking del backend remoto de Terraform para environments/*"
  type        = "String"
  value       = var.tf_state_lock_table

  tags = var.tags
}
