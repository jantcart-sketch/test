# -----------------------------------------------------------------------------
# CodePipeline: un pipeline por rama/entorno
# -----------------------------------------------------------------------------
# "develop" (auto_apply = true)  -> Source, mirror, plan, apply (sin aprobación)
# "main"    (auto_apply = false) -> Source, mirror, plan, ManualApproval, apply

resource "aws_codepipeline" "this" {
  for_each = var.branches

  name     = "${var.project_name}-${each.value.environment}"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.pipeline_artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.main.repository_name
        BranchName           = each.key
        PollForSourceChanges = "false" # el trigger es el EventBridge rule, no polling
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "MirrorToGitRemote"

    action {
      name             = "MirrorToGitRemote"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["mirror_output"]

      configuration = {
        ProjectName = aws_codebuild_project.mirror_git_remote[each.key].name
      }
    }
  }

  stage {
    name = "TerraformPlan"

    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["plan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_plan[each.key].name
      }
    }
  }

  dynamic "stage" {
    for_each = each.value.auto_apply ? [] : [1]

    content {
      name = "ManualApproval"

      action {
        name     = "ApproveTerraformApply"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          CustomData = "Revisa el plan de Terraform (stage TerraformPlan, artifact plan_output/tfplan.txt) antes de aprobar el apply en el entorno ${each.value.environment}."
        }
      }
    }
  }

  stage {
    name = "TerraformApply"

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_apply[each.key].name
      }
    }
  }

  tags = merge(var.tags, {
    Environment = each.value.environment
    Branch      = each.key
  })
}

# -----------------------------------------------------------------------------
# EventBridge: dispara cada pipeline cuando hay push a su rama correspondiente
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "codecommit_push" {
  for_each = var.branches

  name        = "${var.project_name}-${each.value.environment}-push"
  description = "Dispara el pipeline ${each.value.environment} en cada push a la rama ${each.key}"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [aws_codecommit_repository.main.arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [each.key]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "trigger_pipeline" {
  for_each = var.branches

  rule     = aws_cloudwatch_event_rule.codecommit_push[each.key].name
  arn      = "arn:aws:codepipeline:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_codepipeline.this[each.key].name}"
  role_arn = aws_iam_role.eventbridge_invoke_pipeline.arn
}

data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_invoke_pipeline" {
  name               = "${var.project_name}-eventbridge-invoke-pipeline"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "eventbridge_invoke_pipeline" {
  statement {
    effect  = "Allow"
    actions = ["codepipeline:StartPipelineExecution"]
    resources = [
      for b, cfg in var.branches : "arn:aws:codepipeline:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-${cfg.environment}"
    ]
  }
}

resource "aws_iam_role_policy" "eventbridge_invoke_pipeline" {
  name   = "${var.project_name}-eventbridge-invoke-pipeline"
  role   = aws_iam_role.eventbridge_invoke_pipeline.id
  policy = data.aws_iam_policy_document.eventbridge_invoke_pipeline.json
}
