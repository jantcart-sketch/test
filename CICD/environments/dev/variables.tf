variable "project_name" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "target_role_arn" {
  description = "ARN del rol cross-account a asumir en la cuenta dev. Vacío = usa las credenciales activas tal cual (útil en ejecución local con un profile ya en la cuenta destino)."
  type        = string
  default     = ""
}

variable "tags" {
  type = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}
