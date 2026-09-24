# Backend remoto para el estado de este entorno (dev). Distinto "key" que el de main,
# para no compartir state entre entornos aunque usen el mismo bucket.
#
#   terraform init \
#     -backend-config="bucket=mi-proyecto-tfstate" \
#     -backend-config="key=environments/dev/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=mi-proyecto-tfstate-lock"

terraform {
  backend "s3" {
    key     = "environments/dev/terraform.tfstate"
    encrypt = true
  }
}
