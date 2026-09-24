# -----------------------------------------------------------------------------
# Rol de CodePipeline
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.project_name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codepipeline_permissions" {
  statement {
    sid    = "CodeCommitAccess"
    effect = "Allow"
    actions = [
      "codecommit:GetBranch",
      "codecommit:GetCommit",
      "codecommit:GetRepository",
      "codecommit:GetUploadArchiveStatus",
      "codecommit:UploadArchive",
      "codecommit:CancelUploadArchive",
    ]
    resources = [aws_codecommit_repository.main.arn]
  }

  statement {
    sid    = "CodeBuildAccess"
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]
    resources = concat(
      [for p in aws_codebuild_project.mirror_git_remote : p.arn],
      [for p in aws_codebuild_project.terraform_plan : p.arn],
      [for p in aws_codebuild_project.terraform_apply : p.arn],
    )
  }

  statement {
    sid    = "ArtifactBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.pipeline_artifacts.arn,
      "${aws_s3_bucket.pipeline_artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${var.project_name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_permissions.json
}

# -----------------------------------------------------------------------------
# Bucket de artefactos de CodePipeline
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${var.project_name}-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Rol de CodeBuild (compartido por los 3 proyectos: mirror, plan, apply)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}-*"]
  }

  statement {
    sid    = "ArtifactBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.pipeline_artifacts.arn,
      "${aws_s3_bucket.pipeline_artifacts.arn}/*",
    ]
  }

  statement {
    sid    = "CodeCommitFullClone"
    effect = "Allow"
    actions = [
      "codecommit:GitPull",
      "codecommit:GetRepository",
    ]
    resources = [aws_codecommit_repository.main.arn]
  }

  statement {
    sid    = "SecretsAndParams"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_secretsmanager_secret.git_remote_token.arn]
  }

  statement {
    sid    = "SSMParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"]
  }

  statement {
    sid    = "AssumeCrossAccountDeployRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    # Los ARNs se leen de SSM (fuente de verdad externa, ver secrets.tf y
    # scripts/set-cross-account-target.sh), no de var.branches. Si rotas la cuenta
    # destino en SSM, hay que reaplicar este Terraform para que la policy IAM se
    # resincronice con el nuevo ARN (defensa en profundidad: la policy nunca es más
    # amplia que "los ARNs conocidos en el último apply").
    resources = [for p in data.aws_ssm_parameter.target_role_arn : p.value]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${var.project_name}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}
