#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Re-exporta el realm `cauce` desde el contenedor de Keycloak en ejecución.
#
# Uso:  ./export-realm.sh <ruta-de-salida.json>
#
# NO se ejecuta como parte de ningún fix: es documentación operativa. Correrlo
# sobrescribe el archivo de salida, así que nunca apuntarlo directamente a
# keycloak/import/realm.json sin revisar el resultado antes.
# -----------------------------------------------------------------------------
set -euo pipefail

OUT="${1:?Uso: ./export-realm.sh <ruta-de-salida.json>}"
CONTAINER="${KC_CONTAINER:-cauce-keycloak}"

echo "Exportando el realm 'cauce' desde el contenedor ${CONTAINER}..."
docker exec "${CONTAINER}" /opt/keycloak/bin/kc.sh export \
  --realm cauce \
  --users skip \
  --file /tmp/realm-export.json

docker cp "${CONTAINER}:/tmp/realm-export.json" "${OUT}"
echo "Export escrito en ${OUT}"

cat <<'CHECKLIST'

VALIDAR A MANO ANTES DE COMMITEAR
---------------------------------
1. Quitar los `id` UUID de todo objeto exportado. Si se dejan, el archivo queda
   atado a esta instancia concreta de Keycloak.

2. Decidir qué hacer con la clave `clientScopes` de nivel raíz. ATENCIÓN:
   declararla NO fusiona con los client scopes built-in, los REEMPLAZA. Un
   realm.json que declare `clientScopes` con solo algunos scopes importa sin un
   solo error en los logs y deja el realm roto (sin `basic`, sin `profile`, sin
   `email`...), lo que produce 401 por audiencia y 403 por falta del claim `sub`.
   Verificado empíricamente el 23/08/2026.
   O se exportan los 12 completos, o se omite la clave por entero.

3. Confirmar que `cauce-mobile` y `cauce-web-portal` conservan:
     - "basic" en defaultClientScopes  (claim `sub`, acta A36)
     - el protocolMapper oidc-audience-mapper con
       "included.client.audience": "cauce-backend"  (acta A35)

4. Confirmar que `cauce-backend` NO recibe esos scopes: es el cliente de service
   account y quedó fuera de A35/A36 a propósito.

5. Validar el archivo en un Keycloak efímero AISLADO antes de commitear:

     docker run -d --name kc-validate -p 8099:8080 \
       -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin \
       -v "<ruta-absoluta>:/opt/keycloak/data/import/realm.json:ro" \
       quay.io/keycloak/keycloak:25.0 start-dev --import-realm

   Sin `--network cauce-network` y sin montar ningún volumen del stack. Nunca
   validar contra `cauce-postgres-data`: ahí viven los datos reales.

   Que el import no reporte errores NO basta. Comprobar en la instancia efímera:
     - GET /admin/realms/cauce/client-scopes  devuelve los 11 built-in
     - los default-client-scopes de ambos clientes incluyen "basic"
     - un token por grant_type=password trae `aud` con "cauce-backend" y `sub`

CHECKLIST
