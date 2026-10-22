#!/usr/bin/env bash
# Aplica keycloak/apply-portal-client.sh al Keycloak de la VM con la URL del portal y los secretos de vm/.env.
# Los secretos viajan como variables de entorno por nombre: no aparecen en la línea de comandos ni en pantalla.
set -euo pipefail

cd "$(dirname "$0")"

set -a
. ./.env
set +a

export PORTAL_URL="https://portal.${DOMAIN}"
export BACKEND_CLIENT_SECRET="$KEYCLOAK_BACKEND_CLIENT_SECRET"
export PORTAL_CLIENT_SECRET="$KEYCLOAK_PORTAL_CLIENT_SECRET"

tr -d '\r' < ../keycloak/apply-portal-client.sh \
  | docker compose -f docker-compose.vm.yml exec -T \
      -e PORTAL_URL -e BACKEND_CLIENT_SECRET -e PORTAL_CLIENT_SECRET \
      keycloak bash -s
