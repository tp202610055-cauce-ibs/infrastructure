#!/usr/bin/env bash
# Aplica keycloak/apply-portal-client.sh al Keycloak de la VM con la URL del portal y los secretos de vm/.env,
# y deja verifyEmail=false en el realm cauce. Es idempotente.
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

# verifyEmail=false (opción B del correo): el paciente entra sin verificar y el backend le manda el enlace
# con send-verify-email. realm.json ya lo trae, pero el import no llega a un realm existente.
docker compose -f docker-compose.vm.yml exec -T keycloak bash -s <<'EOF'
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
CONFIG=/tmp/kcadm-cauce-realm.config
REALM=cauce
trap 'rm -f "$CONFIG"' EXIT

"$KCADM" config credentials --config "$CONFIG" --server http://localhost:8080 \
  --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

BEFORE=$("$KCADM" get "realms/$REALM" --fields verifyEmail --format csv --noquotes --config "$CONFIG")
"$KCADM" update "realms/$REALM" -s verifyEmail=false --config "$CONFIG"
AFTER=$("$KCADM" get "realms/$REALM" --fields verifyEmail --format csv --noquotes --config "$CONFIG")

if [ "$AFTER" != "false" ]; then
  echo "ERROR: el realm $REALM quedó con verifyEmail=$AFTER (se esperaba false)." >&2
  exit 1
fi
echo "Realm $REALM: verifyEmail $BEFORE -> $AFTER."
EOF
