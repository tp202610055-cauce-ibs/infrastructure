#!/usr/bin/env bash
# Lleva la VM a una versión (repos, imágenes, migraciones y servicios) sin borrar volúmenes; no corre si existe vm/.freeze.
# Uso: bash vm/update.sh <ref-backend> <ref-infrastructure> <ref-web-portal>      (cada uno, tag o rama)
set -euo pipefail

WEB_PORTAL_REPO=https://github.com/tp202610055-cauce-ibs/web-portal.git

# Todo dentro de main: git puede reescribir este mismo archivo, y bash ya lo habrá leído entero.
main() {
  cd "$(dirname "$0")"
  local usage="Uso: bash vm/update.sh <ref-backend> <ref-infrastructure> <ref-web-portal>"
  local backend_ref="${1:?$usage}"
  local infra_ref="${2:?$usage}"
  local web_ref="${3:?$usage}"
  local backend_dir=../../backend
  local infra_dir=..
  local web_dir=../../web-portal
  local compose=(docker compose -f docker-compose.vm.yml)

  if [ -e .freeze ]; then
    echo "La VM está congelada (existe vm/.freeze): no se actualiza durante la semana de pruebas." >&2
    echo "Para descongelar, fuera de horario de pruebas: rm vm/.freeze" >&2
    exit 1
  fi

  local previous_web="$web_ref"
  if [ -d "$web_dir/.git" ]; then
    previous_web="$(current_ref "$web_dir")"
  fi
  local rollback
  rollback="bash vm/update.sh $(current_ref "$backend_dir") $(current_ref "$infra_dir") $previous_web"

  echo "1/6 Actualizando los repos (backend: $backend_ref, infrastructure: $infra_ref, web-portal: $web_ref)..."
  if [ ! -d "$web_dir/.git" ]; then
    git clone --quiet "$WEB_PORTAL_REPO" "$web_dir"
  fi
  checkout "$backend_dir" "$backend_ref"
  checkout "$infra_dir" "$infra_ref"
  checkout "$web_dir" "$web_ref"

  local api_tag web_tag
  api_tag="$(echo "$backend_ref" | tr -c 'A-Za-z0-9_.-' '-')"
  web_tag="$(echo "$web_ref" | tr -c 'A-Za-z0-9_.-' '-')"

  # Las dos imágenes se construyen antes de levantar o tocar servicios, y .env se escribe solo si ambas salen bien.
  echo "2/6 Construyendo la imagen cauce-api:$api_tag..."
  if ! API_IMAGE_TAG="$api_tag" "${compose[@]}" build api; then
    build_failed "$rollback"
  fi

  echo "3/6 Construyendo la imagen cauce/portal-web:$web_tag..."
  if ! (cd "$web_dir" && docker build -f deploy/portal-web/Dockerfile -t "cauce/portal-web:$web_tag" .); then
    build_failed "$rollback"
  fi
  set_env API_IMAGE_TAG "$api_tag"
  set_env PORTAL_WEB_TAG "$web_tag"

  echo "4/6 Aplicando migraciones..."
  "${compose[@]}" up -d --wait postgres
  "${compose[@]}" run --rm api migrate

  echo "5/6 Sincronizando Keycloak y subiendo los servicios..."
  # Los secretos del realm importado son marcadores públicos: se reemplazan antes de que Caddy publique /realms.
  "${compose[@]}" up -d --wait keycloak
  bash keycloak-sync.sh
  "${compose[@]}" up -d
  "${compose[@]}" ps

  echo "6/6 Limpiando la caché de build..."
  docker builder prune -f >/dev/null

  echo
  echo "Listo. Keycloak tarda unos minutos en quedar healthy: revisa con '${compose[*]} ps'."
  echo "Para volver a la versión anterior: $rollback"
}

current_ref() {
  git -C "$1" describe --tags --exact-match 2>/dev/null || git -C "$1" rev-parse --short HEAD
}

checkout() {
  local dir="$1" ref="$2"
  git -C "$dir" fetch --tags --quiet origin
  git -C "$dir" checkout --quiet "$ref"
  if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
    git -C "$dir" pull --ff-only --quiet
  fi
}

# Reemplaza la variable en .env, o la agrega si el .env viene de una versión que no la tenía.
set_env() {
  local name="$1" value="$2"
  if grep -q "^$name=" .env; then
    sed -i "s/^$name=.*/$name=$value/" .env
  else
    echo "$name=$value" >> .env
  fi
}

build_failed() {
  echo "Falló el build: los servicios y .env siguen como estaban; solo los repos quedaron en las referencias nuevas." >&2
  echo "Para dejar los repos como estaban: $1" >&2
  exit 1
}

main "$@"
exit
