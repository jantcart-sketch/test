terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Deliberadamente SIN backend remoto: este es el módulo que CREA el backend
  # remoto para el resto de la plantilla. Su propio state se queda en local
  # (terraform.tfstate en esta misma carpeta) - es un módulo de un solo uso por
  # proyecto, se aplica una vez y rara vez vuelve a tocarse.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
