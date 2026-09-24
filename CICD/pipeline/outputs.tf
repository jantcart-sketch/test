output "codecommit_clone_url_http" {
  description = "URL HTTPS para hacer git clone / git push al repositorio origen"
  value       = aws_codecommit_repository.main.clone_url_http
}

output "codecommit_clone_url_ssh" {
  value = aws_codecommit_repository.main.clone_url_ssh
}

output "git_remote_token_secret_arn" {
  description = "ARN del secret donde debes rellenar el token del remoto Git con: aws secretsmanager put-secret-value --secret-id <arn> --secret-string '<token>'"
  value       = aws_secretsmanager_secret.git_remote_token.arn
}

output "pipeline_names" {
  description = "Nombres de los CodePipeline creados, uno por rama/entorno"
  value       = { for k, v in aws_codepipeline.this : k => v.name }
}

output "cross_account_ssm_parameters_expected" {
  description = <<-EOT
    Parámetros SSM que DEBEN existir (rellenados por scripts/set-cross-account-target.sh,
    ver README) antes de que el pipeline pueda desplegar en cada entorno. Este Terraform
    los LEE en tiempo de plan/apply pero no los crea ni los modifica.
  EOT
  value = {
    for branch, cfg in var.branches : branch => "/${var.project_name}/${cfg.environment}/target_role_arn"
  }
}

output "git_remote_setup_script" {
  description = "El repo remoto NO se crea con Terraform. Ejecuta el script correspondiente a tu proveedor tras el apply (ver README, sección 'Git remoto')."
  value       = "./scripts/create-remote-repo-<proveedor>.sh"
}
