#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-remote-repo-github.sh
# -----------------------------------------------------------------------------
# Crea el repositorio destino del mirror en GitHub, SI NO EXISTE YA.
#
# Este script es ESPECÍFICO DE GITHUB (habla la API REST de GitHub) porque crear un
# repositorio no es parte del protocolo Git — es una operación propia de cada
# plataforma. El resto del pipeline (buildspecs/mirror.yml) es agnóstico y no sabe
# nada de GitHub en concreto; solo hace `git push --mirror` (ver README, sección
# "Git remoto"). Si cambias de proveedor, sustituye este script por el equivalente
# (ej. create-remote-repo-gitlab.sh) sin tocar nada más de la plantilla.
#
# Ejecútalo UNA VEZ por proyecto, antes del primer push a CodeCommit (o en cualquier
# momento después, si necesitas recrear/verificar el repo en GitHub).
#
# Uso:
#   export GITHUB_TOKEN="tu-personal-access-token"   # scope: repo
#   ./create-remote-repo-github.sh --repo-path mi-usuario/mi-repo --visibility private
#
# Si el owner de --repo-path es una organización, el script crea el repo dentro de
# esa organización (endpoint /orgs/{org}/repos); si es tu usuario, lo crea en tu
# cuenta personal (endpoint /user/repos).
#
# Requisitos: curl, jq

set -euo pipefail

GITHUB_API_URL="https://api.github.com"
GITHUB_REPO_PATH=""
GITHUB_VISIBILITY="private"

usage() {
  cat <<EOF
Uso: $0 --repo-path <owner/repo> [--visibility <private|public>] [--api-url <url>]

Variables de entorno requeridas:
  GITHUB_TOKEN   Personal Access Token de GitHub con scope 'repo'.

Opciones:
  --repo-path    Owner (usuario u organización) + nombre del repo (ej. mi-usuario/mi-repo). Requerido.
  --visibility   Visibilidad del repo si se crea: private o public (por defecto: ${GITHUB_VISIBILITY}).
  --api-url      URL base de la API de GitHub (por defecto: ${GITHUB_API_URL}; usa la de tu GitHub Enterprise Server si aplica).
  -h, --help     Muestra esta ayuda.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-path)
      GITHUB_REPO_PATH="$2"
      shift 2
      ;;
    --visibility)
      GITHUB_VISIBILITY="$2"
      shift 2
      ;;
    --api-url)
      GITHUB_API_URL="$2"
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

if [[ -z "$GITHUB_REPO_PATH" ]]; then
  echo "ERROR: --repo-path es requerido" >&2
  usage
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: la variable de entorno GITHUB_TOKEN no está definida" >&2
  echo "  export GITHUB_TOKEN=\"<tu PAT de GitHub>\"" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl no está instalado" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq no está instalado" >&2; exit 1; }

OWNER=$(dirname "$GITHUB_REPO_PATH")
REPO_NAME=$(basename "$GITHUB_REPO_PATH")

echo "Comprobando si el repo '${GITHUB_REPO_PATH}' ya existe en ${GITHUB_API_URL}..."
HTTP_STATUS=$(curl -s -o /tmp/github_repo_check.json -w "%{http_code}" \
  --header "Authorization: Bearer ${GITHUB_TOKEN}" \
  --header "Accept: application/vnd.github+json" \
  "${GITHUB_API_URL}/repos/${OWNER}/${REPO_NAME}")

if [[ "$HTTP_STATUS" == "200" ]]; then
  HTML_URL=$(jq -r '.html_url' /tmp/github_repo_check.json)
  echo "El repo ya existe: ${HTML_URL}"
  echo "No se realiza ninguna acción."
  exit 0
fi

if [[ "$HTTP_STATUS" != "404" ]]; then
  echo "ERROR: respuesta inesperada de la API de GitHub (HTTP ${HTTP_STATUS})" >&2
  cat /tmp/github_repo_check.json >&2
  exit 1
fi

echo "El repo no existe. Creándolo..."

# Determinar si OWNER es una organización o el usuario autenticado, para usar el
# endpoint correcto (/orgs/{org}/repos vs /user/repos).
AUTH_USER=$(curl -s --header "Authorization: Bearer ${GITHUB_TOKEN}" \
  --header "Accept: application/vnd.github+json" \
  "${GITHUB_API_URL}/user" | jq -r '.login // empty')

if [[ -n "$AUTH_USER" && "$AUTH_USER" == "$OWNER" ]]; then
  CREATE_URL="${GITHUB_API_URL}/user/repos"
else
  CREATE_URL="${GITHUB_API_URL}/orgs/${OWNER}/repos"
fi

PRIVATE_FLAG="true"
if [[ "$GITHUB_VISIBILITY" == "public" ]]; then
  PRIVATE_FLAG="false"
fi

CREATE_RESPONSE=$(curl -s --request POST \
  --header "Authorization: Bearer ${GITHUB_TOKEN}" \
  --header "Accept: application/vnd.github+json" \
  --data "{\"name\": \"${REPO_NAME}\", \"private\": ${PRIVATE_FLAG}}" \
  "${CREATE_URL}")

HTML_URL=$(echo "$CREATE_RESPONSE" | jq -r '.html_url // empty')

if [[ -z "$HTML_URL" ]]; then
  echo "ERROR: no se pudo crear el repo. Respuesta de la API:" >&2
  echo "$CREATE_RESPONSE" >&2
  exit 1
fi

echo "Repo creado correctamente: ${HTML_URL}"
