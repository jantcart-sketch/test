variable "project_name" {
  description = "Nombre del proyecto. Debe coincidir con project_name en pipeline/terraform.tfvars."
  type        = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tags" {
  type = map(string)
  default = {
    ManagedBy = "terraform"
    Purpose   = "terraform-backend-bootstrap"
  }
}
