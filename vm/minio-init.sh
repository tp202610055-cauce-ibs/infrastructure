#!/bin/sh
# Crea (o actualiza) el usuario de la API en MinIO con la política readwrite. Es idempotente
# y no imprime credenciales. Corre dentro del contenedor minio-init.
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc admin user add local "$MINIO_API_ACCESS_KEY" "$MINIO_API_SECRET_KEY" >/dev/null

if ! mc admin user info local "$MINIO_API_ACCESS_KEY" 2>/dev/null | grep -q "readwrite"; then
  mc admin policy attach local readwrite --user "$MINIO_API_ACCESS_KEY" >/dev/null
fi

echo "Usuario de la API listo en MinIO, con la política readwrite."
