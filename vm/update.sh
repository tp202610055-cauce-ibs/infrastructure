#!/usr/bin/env bash
# Lleva la VM a una versión (repos, imagen, migraciones y servicios) sin borrar volúmenes; no corre si existe vm/.freeze.
# Uso: bash vm/update.sh <ref-backend> [ref-infrastructure]      (tag o rama; el segundo, por defecto, igual)
set -euo pipefail

# Todo dentro de main: git puede reescribir este mismo archivo, y bash ya lo habrá leído entero.
main() {
  cd "$(dirname "$0")"
  local backend_ref="${1:?Uso: bash vm/update.sh <ref-backend> [ref-infrastructure]}"
  local infra_ref="${2:-$1}"
  local backend_dir=../../backend
  local infra_dir=..
  local compose=(docker compose -f docker-compose.vm.yml)

  if [ -e .freeze ]; then
    echo "La VM está congelada (existe vm/.freeze): no se actualiza durante la semana de pruebas." >&2
    echo "Para descongelar, fuera de horario de pruebas: rm vm/.freeze" >&2
    exit 1
  fi

  local previous_backend previous_infra
  previous_backend="$(git -C "$backend_dir" describe --tags --exact-match 2>/dev/null || git -C "$backend_dir" rev-parse --short HEAD)"
  previous_infra="$(git -C "$infra_dir" describe --tags --exact-match 2>/dev/null || git -C "$infra_dir" rev-parse --short HEAD)"

  echo "1/5 Actualizando los repos (backend: $backend_ref, infrastructure: $infra_ref)..."
  checkout "$backend_dir" "$backend_ref"
  checkout "$infra_dir" "$infra_ref"

  local tag
  tag="$(echo "$backend_ref" | tr -c 'A-Za-z0-9_.-' '-')"
  sed -i "s/^API_IMAGE_TAG=.*/API_IMAGE_TAG=$tag/" .env

  echo "2/5 Construyendo la imagen cauce-api:$tag..."
  "${compose[@]}" build api

  echo "3/5 Aplicando migraciones..."
  "${compose[@]}" up -d --wait postgres
  "${compose[@]}" run --rm api migrate

  echo "4/5 Sincronizando Keycloak y subiendo los servicios..."
  # Los secretos del realm importado son marcadores públicos: se reemplazan antes de que Caddy publique /realms.
  "${compose[@]}" up -d --wait keycloak
  bash keycloak-sync.sh
  "${compose[@]}" up -d
  "${compose[@]}" ps

  echo "5/5 Limpiando la caché de build..."
  docker builder prune -f >/dev/null

  echo
  echo "Listo. Keycloak tarda unos minutos en quedar healthy: revisa con '${compose[*]} ps'."
  echo "Para volver a la versión anterior: bash vm/update.sh $previous_backend $previous_infra"
}

checkout() {
  local dir="$1" ref="$2"
  git -C "$dir" fetch --tags --quiet origin
  git -C "$dir" checkout --quiet "$ref"
  if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
    git -C "$dir" pull --ff-only --quiet
  fi
}

main "$@"
exit
