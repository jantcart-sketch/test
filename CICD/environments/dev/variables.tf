variable "project_name" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tags" {
  type = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}
