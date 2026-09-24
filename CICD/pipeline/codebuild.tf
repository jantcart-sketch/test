# -----------------------------------------------------------------------------
# Proyectos CodeBuild
# -----------------------------------------------------------------------------
# Se crea UN set de 3 proyectos (mirror, plan, apply) POR RAMA/ENTORNO, para que cada
# pipeline (develop / main) tenga sus propios logs y variables de entorno (ENVIRONMENT)
# sin compartir estado entre ejecuciones concurrentes de distintos entornos.

resource "aws_cloudwatch_log_group" "codebuild" {
  for_each = var.branches

  name              = "/aws/codebuild/${var.project_name}-${each.value.environment}"
  retention_in_days = 30
  tags              = var.tags
}

# --- Stage: mirror hacia el remoto Git (agnóstico al proveedor) ----------------

resource "aws_codebuild_project" "mirror_git_remote" {
  for_each = var.branches

  name          = "${var.project_name}-${each.value.environment}-mirror-git-remote"
  description   = "Espeja el repo CodeCommit hacia ${var.git_remote_host}/${var.git_remote_path}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = var.codebuild_compute_type
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = each.value.environment
    }
    environment_variable {
      name  = "GIT_REMOTE_TOKEN_SECRET_ARN"
      value = aws_secretsmanager_secret.git_remote_token.arn
    }
    environment_variable {
      name  = "CODECOMMIT_REPO_NAME"
      value = aws_codecommit_repository.main.repository_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/mirror.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }

  tags = var.tags
}

# --- Stage: terraform plan ------------------------------------------------------

resource "aws_codebuild_project" "terraform_plan" {
  for_each = var.branches

  name          = "${var.project_name}-${each.value.environment}-terraform-plan"
  description   = "terraform init + plan para el entorno ${each.value.environment}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = var.codebuild_compute_type
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = each.value.environment
    }
    environment_variable {
      name  = "TERRAFORM_VERSION"
      value = var.terraform_version
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/plan.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }

  tags = var.tags
}

# --- Stage: terraform apply -----------------------------------------------------

resource "aws_codebuild_project" "terraform_apply" {
  for_each = var.branches

  name          = "${var.project_name}-${each.value.environment}-terraform-apply"
  description   = "terraform apply para el entorno ${each.value.environment}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = var.codebuild_compute_type
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = each.value.environment
    }
    environment_variable {
      name  = "TERRAFORM_VERSION"
      value = var.terraform_version
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/../buildspecs/apply.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }

  tags = var.tags
}
