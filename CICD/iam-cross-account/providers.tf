terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Este Terraform se aplica CON CREDENCIALES DE LA CUENTA DESTINO (dev o main/prod),
# no con las credenciales de la cuenta del pipeline. Configura el profile/región
# correspondiente al invocar `terraform apply` (ver README, Fase 1).
provider "aws" {
  default_tags {
    tags = var.tags
  }
}
