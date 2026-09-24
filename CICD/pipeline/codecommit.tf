# -----------------------------------------------------------------------------
# Repositorio CodeCommit (origen de verdad del código)
# -----------------------------------------------------------------------------

resource "aws_codecommit_repository" "main" {
  repository_name = var.project_name
  description     = "Repositorio origen para ${var.project_name}. Mirror automático a ${var.git_remote_host}/${var.git_remote_path} vía CodeBuild."

  tags = var.tags
}

# CodeCommit crea el repo vacío, sin ramas. "develop" y "main" se crean con el primer
# push del propio usuario (ver README, Fase 3) - Terraform no puede crear ramas Git en un
# repo sin commits. El pipeline y sus triggers ya quedan preparados para reaccionar a
# ambas ramas en cuanto existan.
