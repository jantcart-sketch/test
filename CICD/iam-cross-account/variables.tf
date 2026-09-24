variable "project_name" {
  description = "Nombre del proyecto (debe coincidir con el usado en pipeline/variables.tf) para nombrar el rol de forma consistente."
  type        = string
}

variable "role_name" {
  description = "Nombre del rol a crear en esta cuenta. El ARN resultante se publica en SSM con scripts/set-cross-account-target.sh (no hay que hacerlo coincidir con nada en pipeline/, ya que ese Terraform lee el ARN completo desde SSM)."
  type        = string
  default     = "cicd-deploy-role"
}

variable "pipeline_account_id" {
  description = "Account ID de la cuenta donde vive el pipeline (CodeCommit/CodePipeline/CodeBuild). Es la cuenta que va a asumir este rol."
  type        = string
}

variable "environment" {
  description = "Entorno al que pertenece esta cuenta (dev, main). Solo para tagging/documentación."
  type        = string
}

variable "permissions_boundary_arn" {
  description = <<-EOT
    ARN de un permissions boundary opcional a aplicar sobre el rol de despliegue.
    Fuertemente recomendado en cuentas de producción para acotar el alcance real de
    lo que Terraform puede crear, incluso si la policy adjunta es amplia.
  EOT
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = <<-EOT
    Lista de policies administradas de AWS a adjuntar al rol de despliegue.
    Por defecto viene vacía a propósito: en el ejemplo dummy (bucket S3) basta con
    la policy inline definida en main.tf. Amplía esta lista según lo que tu
    módulo app-infra necesite desplegar realmente.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags comunes para los recursos IAM creados en esta cuenta destino."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Template  = "cicd-codecommit-gitlab-mirror"
  }
}
