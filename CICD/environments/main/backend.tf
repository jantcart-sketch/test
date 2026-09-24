# Backend remoto para el estado de este entorno (main/prod). Distinto "key" que el de
# dev, para no compartir state entre entornos aunque usen el mismo bucket.
#
#   terraform init \
#     -backend-config="bucket=mi-proyecto-tfstate" \
#     -backend-config="key=environments/main/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=mi-proyecto-tfstate-lock"

terraform {
  backend "s3" {
    key     = "environments/main/terraform.tfstate"
    encrypt = true
  }
}
