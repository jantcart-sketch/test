module "app_infra" {
  source = "../../modules/app-infra"

  project_name = var.project_name
  environment  = "main"
  tags         = var.tags
}
