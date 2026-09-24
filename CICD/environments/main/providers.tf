terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# El backend S3 (state) vive en la cuenta del pipeline; los RECURSOS desplegados viven
# en la cuenta destino (main). Por eso el provider asume el rol cross-account
# explícitamente vía `assume_role`, en vez de depender de variables de entorno
# AWS_ACCESS_KEY_ID globales (que romperían el acceso al backend S3 de la otra cuenta).
#
# target_role_arn se pasa por -var desde buildspecs/plan.yml y apply.yml. En ejecución
# local, pásalo a mano o usa un profile con permisos ya asumidos en la cuenta main y deja
# target_role_arn vacío (ver variable más abajo).
provider "aws" {
  region = var.aws_region

  dynamic "assume_role" {
    for_each = var.target_role_arn != "" ? [1] : []
    content {
      role_arn     = var.target_role_arn
      session_name = "terraform-main"
      external_id  = var.project_name
    }
  }

  default_tags {
    tags = var.tags
  }
}
