# -----------------------------------------------------------------------------
# Variables generales del proyecto / plantilla
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Nombre corto del proyecto. Se usa como prefijo de todos los recursos (repo, pipelines, roles, etc.)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name debe empezar por letra minúscula y contener solo letras minúsculas, números y guiones (máx. 31 caracteres)."
  }
}

variable "aws_region" {
  description = "Región AWS donde se despliega el pipeline (CodeCommit, CodePipeline, CodeBuild)."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Ramas / entornos soportados por la plantilla
# -----------------------------------------------------------------------------

variable "branches" {
  description = <<-EOT
    Mapa de ramas soportadas -> configuración de despliegue de cada una.
    Solo se soportan "develop" y "main" en esta plantilla (ver README).
      - environment: sufijo/prefijo usado en nombres de recursos desplegados (dev, main...)
      - auto_apply: true = plan+apply sin intervención; false = requiere Manual Approval

    NOTA: la cuenta AWS destino y el rol a asumir (cross-account) NO se definen aquí.
    Viven en SSM Parameter Store como fuente de verdad externa a este Terraform
    (ver scripts/set-cross-account-target.sh y README, sección "Cross-account").
    Este módulo los LEE (data source) en tiempo de plan/apply, así que deben existir
    en SSM *antes* de aplicar este Terraform por primera vez.
  EOT
  type = map(object({
    environment = string
    auto_apply  = bool
  }))

  default = {
    develop = {
      environment = "dev"
      auto_apply  = true
    }
    main = {
      environment = "main"
      auto_apply  = false
    }
  }

  validation {
    condition     = length(setsubtract(keys(var.branches), ["develop", "main"])) == 0 && length(setsubtract(["develop", "main"], keys(var.branches))) == 0
    error_message = "Esta plantilla solo soporta las ramas 'develop' y 'main'. Ajusta pipelines.tf si necesitas más."
  }
}

# -----------------------------------------------------------------------------
# Git remoto (mirror) — AGNÓSTICO al proveedor (GitHub, GitLab, Bitbucket, etc.)
# -----------------------------------------------------------------------------
# El repo remoto NO se crea con Terraform ni con el pipeline: la creación de un
# repositorio es una operación de la API propia de cada plataforma (GitHub, GitLab...),
# no del protocolo Git, así que es intencionalmente un script aparte, específico de
# proveedor (ver scripts/create-remote-repo-*.sh y README, sección "Git remoto").
#
# El pipeline (buildspecs/mirror.yml) solo hace `git push --mirror` contra la URL
# resultante de host+path — eso sí es 100% agnóstico, es protocolo Git puro.

variable "git_remote_host" {
  description = "Host del proveedor Git remoto donde se hace mirror (ej. \"github.com\", \"gitlab.com\", o una instancia self-managed)."
  type        = string
}

variable "git_remote_path" {
  description = "Owner/organización + nombre del repo en el remoto (ej. \"mi-usuario/mi-repo\"). Debe coincidir con el repo creado por scripts/create-remote-repo-*.sh."
  type        = string
}

variable "git_remote_token_secret_description" {
  description = "Descripción del secret en Secrets Manager que contendrá el token del remoto Git (el valor se rellena manualmente después del apply, nunca por Terraform)."
  type        = string
  default     = "Token (PAT) del proveedor Git remoto, usado para autenticar el git push --mirror del pipeline CI/CD"
}

# -----------------------------------------------------------------------------
# CodeBuild
# -----------------------------------------------------------------------------

variable "codebuild_image" {
  description = "Imagen de CodeBuild a usar en todos los proyectos (debe incluir git; Terraform se instala en el buildspec)."
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

variable "codebuild_compute_type" {
  description = "Tamaño de cómputo de CodeBuild."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "terraform_version" {
  description = "Versión de Terraform a instalar en los buildspecs de plan/apply."
  type        = string
  default     = "1.9.8"
}

# -----------------------------------------------------------------------------
# Backend remoto de Terraform (para los propios environments/*, no para este pipeline)
# -----------------------------------------------------------------------------

variable "tf_state_bucket" {
  description = "Nombre del bucket S3 usado como backend remoto de Terraform para environments/*. Debe existir previamente (ver README, Fase 0)."
  type        = string
}

variable "tf_state_lock_table" {
  description = "Nombre de la tabla DynamoDB usada para locking del backend remoto de Terraform. Debe existir previamente (ver README, Fase 0)."
  type        = string
}

variable "tags" {
  description = "Tags comunes aplicadas a todos los recursos de la plantilla."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Template  = "cicd-codecommit-git-mirror"
  }
}
