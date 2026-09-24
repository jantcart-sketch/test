output "role_arn" {
  description = <<-EOT
    ARN del rol de despliegue creado en esta cuenta. NO lo pegues en pipeline/terraform.tfvars:
    publícalo en SSM Parameter Store con scripts/set-cross-account-target.sh, ej.:
      ./scripts/set-cross-account-target.sh --project mi-proyecto --environment dev --role-arn <este-output>
  EOT
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  value = aws_iam_role.deploy.name
}
