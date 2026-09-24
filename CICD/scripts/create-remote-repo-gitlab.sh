#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-remote-repo-gitlab.sh
# -----------------------------------------------------------------------------
# Crea el proyecto destino del mirror en GitLab, SI NO EXISTE YA.
#
# Este script es ESPECÍFICO DE GITLAB (habla la API REST de GitLab) porque crear un
# repositorio no es parte del protocolo Git — es una operación propia de cada
# plataforma. El resto del pipeline (buildspecs/mirror.yml) es agnóstico y no sabe
# nada de GitLab en concreto; solo hace `git push --mirror` (ver README, sección
# "Git remoto"). Si cambias de proveedor, sustituye este script por el equivalente
# (ej. create-remote-repo-github.sh) sin tocar nada más de la plantilla.
#
# Ejecútalo UNA VEZ por proyecto, antes del primer push a CodeCommit (o en cualquier
# momento después, si necesitas recrear/verificar el proyecto en GitLab).
#
# Uso:
#   export GITLAB_TOKEN="tu-personal-access-token"   # scope: api (o write_repository)
#   ./create-remote-repo-gitlab.sh --project-path mi-grupo/mi-proyecto \
#                                    --base-url https://gitlab.com/api/v4 \
#                                    --visibility private
#
# Requisitos: curl, jq, python3

set -euo pipefail

GITLAB_BASE_URL="https://gitlab.com/api/v4"
GITLAB_PROJECT_PATH=""
GITLAB_VISIBILITY="private"

usage() {
  cat <<EOF
Uso: $0 --project-path <namespace/proyecto> [--base-url <url>] [--visibility <private|internal|public>]

Variables de entorno requeridas:
  GITLAB_TOKEN   Personal Access Token de GitLab con scope 'api' o 'write_repository'.

Opciones:
  --project-path   Namespace/grupo + nombre del proyecto (ej. mi-grupo/mi-proyecto). Requerido.
  --base-url       URL base de la API de GitLab (por defecto: ${GITLAB_BASE_URL}).
  --visibility     Visibilidad del proyecto si se crea (por defecto: ${GITLAB_VISIBILITY}).
  -h, --help       Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path)
      GITLAB_PROJECT_PATH="$2"
      shift 2
      ;;
    --base-url)
      GITLAB_BASE_URL="$2"
      shift 2
      ;;
    --visibility)
      GITLAB_VISIBILITY="$2"
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

if [[ -z "$GITLAB_PROJECT_PATH" ]]; then
  echo "ERROR: --project-path es requerido" >&2
  usage
  exit 1
fi

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  echo "ERROR: la variable de entorno GITLAB_TOKEN no está definida" >&2
  echo "  export GITLAB_TOKEN=\"<tu PAT de GitLab>\"" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl no está instalado" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq no está instalado" >&2; exit 1; }

PROJECT_PATH_ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$GITLAB_PROJECT_PATH")

echo "Comprobando si el proyecto '${GITLAB_PROJECT_PATH}' ya existe en ${GITLAB_BASE_URL}..."
HTTP_STATUS=$(curl -s -o /tmp/gitlab_project_check.json -w "%{http_code}" \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_BASE_URL}/projects/${PROJECT_PATH_ENCODED}")

if [[ "$HTTP_STATUS" == "200" ]]; then
  WEB_URL=$(jq -r '.web_url' /tmp/gitlab_project_check.json)
  echo "El proyecto ya existe: ${WEB_URL}"
  echo "No se realiza ninguna acción."
  exit 0
fi

if [[ "$HTTP_STATUS" != "404" ]]; then
  echo "ERROR: respuesta inesperada de la API de GitLab (HTTP ${HTTP_STATUS})" >&2
  cat /tmp/gitlab_project_check.json >&2
  exit 1
fi

echo "El proyecto no existe. Creándolo..."

NAMESPACE_PATH=$(dirname "$GITLAB_PROJECT_PATH")
PROJECT_SLUG=$(basename "$GITLAB_PROJECT_PATH")

NAMESPACE_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_BASE_URL}/namespaces?search=${NAMESPACE_PATH}" | jq -r --arg path "$NAMESPACE_PATH" '.[] | select(.full_path == $path) | .id' | head -n1)

if [[ -z "$NAMESPACE_ID" || "$NAMESPACE_ID" == "null" ]]; then
  echo "ERROR: no se encontró el namespace/grupo '${NAMESPACE_PATH}' en GitLab." >&2
  echo "Crea el grupo manualmente en GitLab antes de ejecutar este script, o revisa el valor de --project-path." >&2
  exit 1
fi

CREATE_RESPONSE=$(curl -s --request POST \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "{\"name\": \"${PROJECT_SLUG}\", \"namespace_id\": ${NAMESPACE_ID}, \"visibility\": \"${GITLAB_VISIBILITY}\"}" \
  "${GITLAB_BASE_URL}/projects")

WEB_URL=$(echo "$CREATE_RESPONSE" | jq -r '.web_url // empty')

if [[ -z "$WEB_URL" ]]; then
  echo "ERROR: no se pudo crear el proyecto. Respuesta de la API:" >&2
  echo "$CREATE_RESPONSE" >&2
  exit 1
fi

echo "Proyecto creado correctamente: ${WEB_URL}"
