#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Aplica al Keycloak que YA ESTÁ CORRIENDO los cambios del cliente cauce-web-portal
# que trae realm.json desde el acta A68 (portal autenticado por el backend).
#
# Por qué existe: el contenedor arranca con --import-realm, que solo importa el
# realm si no existe. Un realm.json nuevo no llega a un Keycloak ya importado, y
# borrar el realm para reimportarlo haría perder los usuarios. Este script cambia
# solo el cliente del portal y no toca usuarios.
#
# Es idempotente: correrlo dos veces deja el mismo resultado. Si el secret del
# cliente sigue siendo el marcador del import (REGENERAR_DESPUES_DEL_IMPORT), lo
# regenera; si ya es uno real, lo conserva. Al final imprime el secret vigente,
# que va en el user-secret Keycloak:WebPortalClientSecret del backend.
#
# Se ejecuta DENTRO del contenedor, que ya tiene kcadm y las credenciales de
# admin en su entorno. Desde PowerShell o Git Bash, parado en infrastructure/:
#
#   docker cp keycloak/apply-portal-client.sh cauce-keycloak:/tmp/apply-portal-client.sh
#   docker exec cauce-keycloak bash -c "tr -d '\r' < /tmp/apply-portal-client.sh | bash"
#
# El `tr` quita los CR que Git agrega en Windows (core.autocrlf=true).
# La URL del portal se puede cambiar con PORTAL_URL (por defecto http://localhost:5173).
# -----------------------------------------------------------------------------
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
CONFIG=/tmp/kcadm-cauce.config
REALM=cauce
CLIENT_ID=cauce-web-portal
PORTAL_URL="${PORTAL_URL:-http://localhost:5173}"
PLACEHOLDER=REGENERAR_DESPUES_DEL_IMPORT

"$KCADM" config credentials --config "$CONFIG" --server http://localhost:8080 \
  --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

INTERNAL_ID=$("$KCADM" get clients -r "$REALM" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes --config "$CONFIG")
if [ -z "$INTERNAL_ID" ]; then
  echo "ERROR: no existe el cliente $CLIENT_ID en el realm $REALM." >&2
  exit 1
fi

"$KCADM" update "clients/$INTERNAL_ID" -r "$REALM" --config "$CONFIG" \
  -s directAccessGrantsEnabled=true \
  -s standardFlowEnabled=false \
  -s "redirectUris=[\"$PORTAL_URL/*\"]" \
  -s "webOrigins=[\"$PORTAL_URL\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=$PORTAL_URL/*" \
  -s 'attributes."pkce.code.challenge.method"=' \
  -s 'attributes."access.token.lifespan"=900' \
  -s 'attributes."client.session.idle.timeout"=900' \
  -s 'attributes."client.session.max.lifespan"=28800'

# En la VM, vm/keycloak-sync.sh pasa los dos secretos de vm/.env: se fijan tal cual y no se imprimen.
if [ -n "${PORTAL_CLIENT_SECRET:-}${BACKEND_CLIENT_SECRET:-}" ]; then
  if [ -z "${PORTAL_CLIENT_SECRET:-}" ] || [ -z "${BACKEND_CLIENT_SECRET:-}" ]; then
    rm -f "$CONFIG"
    echo "ERROR: hacen falta PORTAL_CLIENT_SECRET y BACKEND_CLIENT_SECRET a la vez." >&2
    exit 1
  fi

  BACKEND_INTERNAL_ID=$("$KCADM" get clients -r "$REALM" -q clientId=cauce-backend --fields id --format csv --noquotes --config "$CONFIG")
  if [ -z "$BACKEND_INTERNAL_ID" ]; then
    rm -f "$CONFIG"
    echo "ERROR: no existe el cliente cauce-backend en el realm $REALM." >&2
    exit 1
  fi

  # Por stdin y no con -s: un argumento de kcadm se vería con ps desde el host.
  printf '{"secret":"%s"}' "$PORTAL_CLIENT_SECRET" | "$KCADM" update "clients/$INTERNAL_ID" -r "$REALM" --config "$CONFIG" -f -
  printf '{"secret":"%s"}' "$BACKEND_CLIENT_SECRET" | "$KCADM" update "clients/$BACKEND_INTERNAL_ID" -r "$REALM" --config "$CONFIG" -f -
  rm -f "$CONFIG"
  echo "Cliente $CLIENT_ID actualizado: Direct Access Grants ON, Standard Flow OFF, redirect $PORTAL_URL/*."
  echo "Secretos de $CLIENT_ID y cauce-backend sincronizados con los recibidos (no se muestran)."
  exit 0
fi

SECRET=$("$KCADM" get "clients/$INTERNAL_ID/client-secret" -r "$REALM" --fields value --format csv --noquotes --config "$CONFIG")
if [ "$SECRET" = "$PLACEHOLDER" ] || [ -z "$SECRET" ]; then
  "$KCADM" create "clients/$INTERNAL_ID/client-secret" -r "$REALM" --config "$CONFIG" >/dev/null
  SECRET=$("$KCADM" get "clients/$INTERNAL_ID/client-secret" -r "$REALM" --fields value --format csv --noquotes --config "$CONFIG")
  echo "Secret regenerado (el anterior era el marcador del import)."
fi

rm -f "$CONFIG"

echo "Cliente $CLIENT_ID actualizado: Direct Access Grants ON, Standard Flow OFF, redirect $PORTAL_URL/*."
echo "Secret vigente de $CLIENT_ID (va en el user-secret Keycloak:WebPortalClientSecret):"
echo "$SECRET"
