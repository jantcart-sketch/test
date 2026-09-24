terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# En ejecución local, usa un profile con permisos en la cuenta main/prod.
# En CodeBuild (buildspecs/plan.yml y apply.yml), las credenciales ya vienen del
# sts assume-role hacia la cuenta main, así que no hace falta "profile" aquí.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
