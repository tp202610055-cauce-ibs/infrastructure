#!/usr/bin/env bash
# Crea vm/.env con secretos aleatorios para la VM. Se niega a sobrescribir uno existente.
# Uso: bash vm/generate-env.sh [--qa] <dominio> <correo-para-lets-encrypt>      (--qa: nace con el modo QA encendido)
set -euo pipefail

cd "$(dirname "$0")"

QA_MODE=false
ARGS=()
for arg in "$@"; do
  if [ "$arg" = --qa ]; then
    QA_MODE=true
  else
    ARGS+=("$arg")
  fi
done
set -- "${ARGS[@]}"

DOMAIN="${1:?Uso: bash vm/generate-env.sh [--qa] <dominio> <correo-para-lets-encrypt>}"
ACME_EMAIL="${2:?Uso: bash vm/generate-env.sh [--qa] <dominio> <correo-para-lets-encrypt>}"
ENV_FILE=.env
CADDY_IMAGE=caddy:2.11.7

if [ -e "$ENV_FILE" ]; then
  echo "Ya existe vm/$ENV_FILE. No lo sobrescribo: si de verdad quieres otro, muévelo antes." >&2
  exit 1
fi

for tool in openssl docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Falta $tool. Corre antes: bash vm/setup-vm.sh" >&2
    exit 1
  fi
done

# Solo letras y números: los secretos viajan en cadenas de conexión, URL JDBC y SQL.
random_secret() {
  openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | cut -c1-"${1:-32}"
}

MAIL_USER=revisor
MAIL_PASSWORD="$(random_secret 20)"
MAIL_PASSWORD_HASH="$(docker run --rm "$CADDY_IMAGE" caddy hash-password --plaintext "$MAIL_PASSWORD")"

umask 077
cat > "$ENV_FILE" <<EOF
# Generado por generate-env.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ). Contiene secretos: no se copia ni se versiona.

DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
ACME_CA=

API_IMAGE_TAG=local
PORTAL_WEB_TAG=local

POSTGRES_DB=cauce
POSTGRES_USER=cauce
POSTGRES_PASSWORD=$(random_secret)
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=$(random_secret)

KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(random_secret)
KEYCLOAK_BACKEND_CLIENT_SECRET=$(random_secret)
KEYCLOAK_PORTAL_CLIENT_SECRET=$(random_secret)

KEYDB_PASSWORD=$(random_secret)

MINIO_ROOT_USER=minioadmin$(random_secret 8)
MINIO_ROOT_PASSWORD=$(random_secret)
MINIO_API_ACCESS_KEY=cauceapi$(random_secret 12)
MINIO_API_SECRET_KEY=$(random_secret 40)

ADMIN_API_KEY=$(random_secret 48)
FCM_USE_FAKE=true
RECOMMENDATIONS_EXPIRATION_WINDOW_HOURS=72
WORKERS_OUTBOX_DISPATCHER_ENABLED=true
WORKERS_NOTIFICATION_DISPATCHER_ENABLED=true
WORKERS_RECOMMENDATION_EXPIRATION_ENABLED=true
WORKERS_RECOMMENDATION_ARCHIVAL_ENABLED=true
WORKERS_OUTBOX_RETENTION_ENABLED=true
WORKERS_WEEKLY_REMINDER_ENABLED=true
WORKERS_IBS_SSS_REMINDER_ENABLED=true
RATE_LIMITING_ENABLED=true

MAIL_USER=$MAIL_USER
MAIL_PASSWORD_HASH='$MAIL_PASSWORD_HASH'
EOF
chmod 600 "$ENV_FILE"

if [ "$QA_MODE" = true ]; then
  . ./qa-switches.sh
  qa_switch_set_all "$ENV_FILE" false
fi

# Carpeta del archivo de cuenta de servicio de Firebase (ignorada por git).
mkdir -p secrets
chmod 755 secrets

echo "Listo: vm/$ENV_FILE creado con permiso 600."
echo
echo "Credencial del buzón de prueba (https://portal.$DOMAIN/mail/), para entregar a los revisores:"
echo "  usuario:    $MAIL_USER"
echo "  contraseña: $MAIL_PASSWORD"
echo
echo "Guárdala ahora: no queda escrita en ningún archivo, solo su hash."
if [ "$QA_MODE" = true ]; then
  echo
  echo "MODO QA ENCENDIDO: recordatorios, archivado, expiración y límite de peticiones apagados."
  echo "Para revisarlo o apagarlo: bash vm/qa-mode.sh status   (o off)"
fi
