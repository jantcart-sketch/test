# Backend remoto para el ESTADO DE ESTE MISMO PIPELINE (no confundir con el backend
# de environments/*, que despliega la infraestructura de la aplicación).
#
# Terraform no permite variables aquí, así que estos valores deben coincidir a mano
# con tf_state_bucket / tf_state_lock_table de variables.tf, o pasarse por -backend-config
# en `terraform init`:
#
#   terraform init \
#     -backend-config="bucket=mi-proyecto-tfstate" \
#     -backend-config="key=pipeline/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=mi-proyecto-tfstate-lock"
#
# Se deja sin valores fijos (partial configuration) para que la plantilla sea reutilizable
# entre proyectos sin editar este archivo.

terraform {
  backend "s3" {
    key     = "pipeline/terraform.tfstate"
    encrypt = true
  }
}
