variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo de todos los recursos."
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue (dev, main). Se usa como sufijo de nombres de recursos."
  type        = string

  validation {
    condition     = contains(["dev", "main"], var.environment)
    error_message = "environment debe ser 'dev' o 'main' en esta plantilla."
  }
}

variable "tags" {
  description = "Tags comunes para los recursos de este módulo."
  type        = map(string)
  default     = {}
}
