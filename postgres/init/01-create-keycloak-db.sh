#!/bin/bash
# =============================================================================
# Init script: crea la BD secundaria para Keycloak
# =============================================================================
# Se ejecuta automáticamente al PRIMER arranque del contenedor de Postgres,
# cuando el volumen postgres-data está vacío.
# Si ya hay datos en el volumen, este script NO se ejecuta.
# =============================================================================

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER ${KEYCLOAK_DB_USER} WITH PASSWORD '${KEYCLOAK_DB_PASSWORD}';
    CREATE DATABASE ${KEYCLOAK_DB_NAME} OWNER ${KEYCLOAK_DB_USER};
    GRANT ALL PRIVILEGES ON DATABASE ${KEYCLOAK_DB_NAME} TO ${KEYCLOAK_DB_USER};
EOSQL

echo ">>> Base de datos '${KEYCLOAK_DB_NAME}' creada para Keycloak con usuario '${KEYCLOAK_DB_USER}'"
