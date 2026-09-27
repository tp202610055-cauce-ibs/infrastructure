#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SOLO DESARROLLO. Paso único para las bases sembradas antes del acta A68.
#
# El nutricionista demo (nutricionista.demo@cauce.local) nacía con una contraseña
# temporal. El portal inicia sesión a través del backend y nunca muestra una
# pantalla de Keycloak donde cambiarla, así que con la temporal no puede entrar.
# El seeder ya la crea permanente en las instalaciones nuevas, pero no toca una
# cuenta que ya existe: este script la deja permanente en el Keycloak actual.
#
# Es idempotente: fija la misma contraseña y limpia las acciones pendientes.
#
# Se ejecuta DENTRO del contenedor. Desde PowerShell o Git Bash, en infrastructure/:
#
#   docker cp keycloak/dev-demo-nutritionist-password.sh cauce-keycloak:/tmp/dev-demo.sh
#   docker exec cauce-keycloak bash -c "tr -d '\r' < /tmp/dev-demo.sh | bash"
#
# La contraseña es la de desarrollo de los casos de prueba (CP016, CP045, CP072).
# -----------------------------------------------------------------------------
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
CONFIG=/tmp/kcadm-cauce-dev.config
REALM=cauce
USERNAME=nutricionista.demo@cauce.local
PASSWORD='Portal#2026'

"$KCADM" config credentials --config "$CONFIG" --server http://localhost:8080 \
  --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

USER_ID=$("$KCADM" get users -r "$REALM" -q username="$USERNAME" -q exact=true --fields id --format csv --noquotes --config "$CONFIG")
if [ -z "$USER_ID" ]; then
  rm -f "$CONFIG"
  echo "No existe $USERNAME en Keycloak: arrancá el backend en Development y el seeder la crea ya permanente."
  exit 0
fi

"$KCADM" set-password -r "$REALM" --userid "$USER_ID" --new-password "$PASSWORD" --config "$CONFIG"
"$KCADM" update "users/$USER_ID" -r "$REALM" -s 'requiredActions=[]' --config "$CONFIG"

rm -f "$CONFIG"
echo "Listo: $USERNAME tiene contraseña permanente y ninguna acción pendiente."
