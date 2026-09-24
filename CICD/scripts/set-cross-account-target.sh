#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# set-cross-account-target.sh
# -----------------------------------------------------------------------------
# ÚNICO PUNTO desde el que se define/rota qué cuenta AWS y qué rol asume CodeBuild
# para desplegar Terraform en un entorno dado (dev o main).
#
# Este script es la fuente de verdad "externa" a pipeline/*.tf: escribe en SSM
# Parameter Store, en la cuenta donde vive el pipeline (CodeCommit/CodePipeline/
# CodeBuild). pipeline/secrets.tf LEE (data source) el parámetro que este script
# escribe; nunca lo crea ni lo sobreescribe con un valor por defecto.
#
# Cambiar de cuenta destino, rotar el rol, o apuntar temporalmente a otra cuenta
# (ej. para un test) se hace SOLO con este script + un "terraform apply" de
# pipeline/ (para que la policy IAM de CodeBuild se resincronice con el nuevo ARN,
# ver README sección "Cross-account").
#
# Uso:
#   ./set-cross-account-target.sh \
#       --project mi-proyecto \
#       --environment dev \
#       --role-arn arn:aws:iam::111111111111:role/cicd-deploy-role \
#       --profile techsummit2026
#
# El --role-arn normalmente es el output "role_arn" de iam-cross-account/
# (aplicado antes, en la cuenta destino).
#
# Requisitos: AWS CLI configurado con permisos ssm:PutParameter en la cuenta pipeline.

set -euo pipefail

PROJECT_NAME=""
ENVIRONMENT=""
ROLE_ARN=""
AWS_PROFILE_ARG=""
AWS_REGION_ARG="us-east-1"

usage() {
  cat <<EOF
Uso: $0 --project <nombre> --environment <dev|main> --role-arn <arn> [--profile <perfil-aws>] [--region <region>]

Opciones:
  --project      Nombre del proyecto (debe coincidir con project_name en pipeline/terraform.tfvars). Requerido.
  --environment  Entorno: 'dev' o 'main'. Requerido.
  --role-arn     ARN completo del rol cross-account a asumir (ver iam-cross-account/outputs.tf). Requerido.
  --profile      Perfil de AWS CLI a usar (opcional; si se omite, usa las credenciales por defecto del entorno).
  --region       Región AWS donde vive el pipeline (por defecto: ${AWS_REGION_ARG}).
  -h, --help     Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE_ARG="$2"
      shift 2
      ;;
    --region)
      AWS_REGION_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Argumento desconocido: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" || -z "$ENVIRONMENT" || -z "$ROLE_ARN" ]]; then
  echo "ERROR: --project, --environment y --role-arn son requeridos" >&2
  usage
  exit 1
fi

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "main" ]]; then
  echo "ERROR: --environment debe ser 'dev' o 'main'" >&2
  exit 1
fi

if ! [[ "$ROLE_ARN" =~ ^arn:aws:iam::[0-9]{12}:role/.+ ]]; then
  echo "ERROR: --role-arn no tiene forma de ARN de rol IAM válido (arn:aws:iam::<account-id>:role/<nombre>)" >&2
  exit 1
fi

PROFILE_FLAG=()
if [[ -n "$AWS_PROFILE_ARG" ]]; then
  PROFILE_FLAG=(--profile "$AWS_PROFILE_ARG")
fi

PARAM_NAME="/${PROJECT_NAME}/${ENVIRONMENT}/target_role_arn"

echo "Publicando en SSM Parameter Store:"
echo "  Parámetro: ${PARAM_NAME}"
echo "  Valor:     ${ROLE_ARN}"
echo "  Región:    ${AWS_REGION_ARG}"

aws ssm put-parameter \
  "${PROFILE_FLAG[@]}" \
  --region "$AWS_REGION_ARG" \
  --name "$PARAM_NAME" \
  --type "String" \
  --value "$ROLE_ARN" \
  --overwrite \
  --description "ARN del rol cross-account que CodeBuild asume para desplegar en el entorno ${ENVIRONMENT} (gestionado por scripts/set-cross-account-target.sh, NO por Terraform)"

echo ""
echo "Listo. Para que la policy IAM de CodeBuild reconozca este ARN, aplica pipeline/:"
echo "  cd pipeline && terraform apply"
