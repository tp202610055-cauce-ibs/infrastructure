# Cauce en la VM de QA

Guía para instalar y operar Cauce en una VM Ubuntu 24.04 (2 vCPU, 4 GiB, 64 GB) con Docker Compose y Caddy.
`<DOMINIO>` es el dominio real y `<IP>` la IP pública de la VM. Los archivos de esta guía están en `vm/`.

| Nombre | Qué sirve |
| --- | --- |
| `portal.<DOMINIO>` | Portal web (`/`), API (`/api`), Keycloak (`/realms/cauce`, `/resources`) y buzón de prueba (`/mail`) |
| `archivos.<DOMINIO>` | API de MinIO, para descargar reportes y exportaciones con URL firmada |

## 0. Antes de empezar

- En el portal de Azure, el grupo de seguridad de red de la VM permite la entrada por 22, 80 y 443.
- En el DNS del dominio, dos registros A hacia `<IP>`: `portal` y `archivos`.
- Comprueba que ya resuelven (puede tardar unos minutos):

```bash
getent hosts portal.<DOMINIO> archivos.<DOMINIO>
```

## 1. Instalación

Entra a la VM con `ssh azureuser@<IP>` y clona los dos repos uno al lado del otro. Si son privados, git pide
usuario y un token de GitHub de solo lectura.

```bash
mkdir -p ~/cauce && cd ~/cauce
git clone https://github.com/tp202610055-cauce-ibs/backend.git
git clone https://github.com/tp202610055-cauce-ibs/infrastructure.git
```

Prepara el sistema: Docker, swap de 2 GB y configuración del demonio. Luego sal y vuelve a entrar, para usar
`docker` sin `sudo`.

```bash
bash ~/cauce/infrastructure/vm/setup-vm.sh
exit
```

Genera el archivo de secretos. Muestra **una sola vez** la credencial del buzón: guárdala para los revisores.

```bash
cd ~/cauce/infrastructure
bash vm/generate-env.sh <DOMINIO> <correo-para-lets-encrypt>
```

Construye la imagen, migra, sincroniza los secretos de Keycloak y levanta todo con las versiones etiquetadas.
Los secretos de `realm.json` son marcadores públicos: `update.sh` los reemplaza antes de levantar Caddy.

```bash
bash vm/update.sh v0.18.0-deploy-vm v0.3.0-deploy-vm
```

A partir de aquí, todos los comandos van desde `~/cauce/infrastructure/vm` y con este atajo:

```bash
cd ~/cauce/infrastructure/vm
alias dc='docker compose -f docker-compose.vm.yml'
```

Espera a que todo quede `healthy` (Keycloak tarda de 2 a 4 minutos en su primer arranque):

```bash
dc ps
```

Crea el usuario de la API en MinIO y carga los catálogos:

```bash
dc run --rm minio-init
dc run --rm api seed-catalogs
```

Si alguna vez necesitas volver a aplicar la configuración de los clientes de Keycloak, `bash keycloak-sync.sh`
es idempotente.

`seed-catalogs` carga roles, alergias, alimentos, glosario, consentimiento, versión de modelo y buckets. No crea
cuentas: las cuentas de QA llegan en el bloque D-2.

### Si `minio-init` falla

Respaldo temporal: la API usa las credenciales root de MinIO. Anótalo en la bitácora y vuelve al usuario propio
apenas se pueda.

```bash
sed -i "s/^MINIO_API_ACCESS_KEY=.*/MINIO_API_ACCESS_KEY=$(grep '^MINIO_ROOT_USER=' .env | cut -d= -f2-)/" .env
sed -i "s/^MINIO_API_SECRET_KEY=.*/MINIO_API_SECRET_KEY=$(grep '^MINIO_ROOT_PASSWORD=' .env | cut -d= -f2-)/" .env
dc up -d api
```

## 2. Pruebas de humo

| Prueba | Comando | Resultado esperado |
| --- | --- | --- |
| Certificado de producción | `echo \| openssl s_client -connect portal.<DOMINIO>:443 -servername portal.<DOMINIO> 2>/dev/null \| openssl x509 -noout -issuer -dates` | Emisor de Let's Encrypt **sin** la palabra `STAGING`; vence en unos 90 días |
| API y base | `curl -s https://portal.<DOMINIO>/api/v1/health/ready` | `Healthy` |
| Keycloak | `curl -s https://portal.<DOMINIO>/realms/cauce \| head -c 120` | JSON con `"realm":"cauce"` |
| Emisor de los tokens | `curl -s https://portal.<DOMINIO>/realms/cauce/.well-known/openid-configuration \| grep -o '"issuer":"[^"]*"'` | `https://portal.<DOMINIO>/realms/cauce` |
| Emisor por la red interna | `dc exec api curl -s http://keycloak:8080/realms/cauce/.well-known/openid-configuration \| grep -o '"issuer":"[^"]*"'` | El **mismo** emisor público |
| Consola cerrada | `curl -s -o /dev/null -w '%{http_code}\n' https://portal.<DOMINIO>/admin/` | `404` (igual para `/realms/master`) |
| API de administración cerrada | `curl -s -o /dev/null -w '%{http_code}\n' https://portal.<DOMINIO>/api/v1/admin/nutritionists` | `404`; se usa desde la VM con `dc exec api curl http://localhost:8080/api/v1/admin/...` |
| Buzón protegido | `curl -s -o /dev/null -w '%{http_code}\n' https://portal.<DOMINIO>/mail/` | `401` |
| Salida a Firebase | `dc exec api curl -sS -o /dev/null -w '%{http_code}\n' https://fcm.googleapis.com/` | Cualquier código HTTP; un error de conexión no vale |
| Salida a Google OAuth | `dc exec api curl -sS -o /dev/null -w '%{http_code}\n' https://oauth2.googleapis.com/` | Cualquier código HTTP |
| Inicio de sesión | Pendiente | Se prueba en D-2, con las cuentas de QA |

URL firmada por `archivos.<DOMINIO>`: sube un archivo de prueba, firma su URL y descárgala.

```bash
DOMINIO="$(grep '^DOMAIN=' .env | cut -d= -f2-)"
dc run --rm -e DOMAIN="$DOMINIO" --entrypoint sh minio-init -c '
  mc alias set pub https://archivos.$DOMAIN "$MINIO_API_ACCESS_KEY" "$MINIO_API_SECRET_KEY" >/dev/null
  echo humo > /tmp/humo.txt && mc cp -q /tmp/humo.txt pub/clinical-reports/humo.txt >/dev/null
  mc share download --expire 10m pub/clinical-reports/humo.txt | grep -o "https://[^ ]*"'
```

Copia la URL que imprime y comprueba que devuelve `humo`. Después borra el archivo de prueba:

```bash
curl -s "<URL>"
dc run --rm -e DOMAIN="$DOMINIO" --entrypoint sh minio-init -c '
  mc alias set pub https://archivos.$DOMAIN "$MINIO_API_ACCESS_KEY" "$MINIO_API_SECRET_KEY" >/dev/null
  mc rm pub/clinical-reports/humo.txt'
```

## 3. Activar el push (Firebase)

Desde Windows, sube el archivo de cuenta de servicio (PowerShell):

```powershell
scp C:\ruta\firebase-sa.json azureuser@<IP>:~/cauce/infrastructure/vm/secrets/firebase-sa.json
```

En la VM, deja el archivo legible solo para el usuario del contenedor (`app`, UID 1654). Si el contenedor no
puede leerlo, la API no arranca y el log nombra la ruta.

```bash
sudo chown 1654:1654 secrets/firebase-sa.json
sudo chmod 400 secrets/firebase-sa.json
sed -i 's/^FCM_USE_FAKE=.*/FCM_USE_FAKE=false/' .env
dc up -d api
dc exec api test -r /run/secrets/cauce/firebase-sa.json && echo "legible"
dc ps api
```

Cómo saber que el push funciona:

- El worker de notificaciones revisa la cola cada 10 segundos. Un envío exitoso **no deja línea en el log**.
  Un fallo deja `FCM push notification <id> failed.`, y un token inválido, `FCM token invalidated for user <id>`.
- `dc logs --since 10m api | grep -i fcm` muestra solo los fallos. Si el worker estuviera apagado, al arrancar
  aparece `NotificationDispatcherWorker is disabled by configuration.`
- Los envíos se ven en la base, sin datos personales:

```bash
dc exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT channel, status, retry_count, scheduled_for, sent_at FROM notifications ORDER BY scheduled_for DESC LIMIT 10;"'
```

`status = sent` con `sent_at` lleno es un push entregado a Firebase.

## 4. Prueba de reinicio (solo durante la instalación)

Nunca en la semana de pruebas. Comprueba que todo vuelve solo:

```bash
sudo reboot
# vuelve a entrar por SSH después de 1 o 2 minutos
cd ~/cauce/infrastructure/vm && docker compose -f docker-compose.vm.yml ps
```

Todos los servicios deben volver a `healthy` sin hacer nada.

## 5. Semana de pruebas: congelar y vigilar

Congelar (bloquea `update.sh`) y descongelar:

```bash
touch ~/cauce/infrastructure/vm/.freeze
rm ~/cauce/infrastructure/vm/.freeze
```

Vigilar sin tocar nada:

```bash
df -h /
docker system df
docker stats --no-stream
dc ps
```

Los logs de Docker rotan solos (3 archivos de 10 MB por contenedor). Caddy renueva el certificado solo, unos
30 días antes de que venza.

## 6. Interruptores sin tocar código

En `.env`: `RECOMMENDATIONS_EXPIRATION_WINDOW_HOURS` y los siete `WORKERS_*_ENABLED`. Cambiar uno exige recrear
solo la API, **fuera del horario de pruebas**:

```bash
nano .env
dc up -d api
```

## 7. Actualizar y volver atrás

Solo fuera de la semana de pruebas y sin `vm/.freeze`:

```bash
bash ~/cauce/infrastructure/vm/update.sh <tag-backend> <tag-infrastructure>
```

Al terminar imprime el comando exacto para volver a la versión anterior. No borra volúmenes.

## 8. Consolas por túnel SSH

Keycloak (8081) y la consola de MinIO (9001) no se publican. Desde Windows:

```powershell
ssh -L 8081:localhost:8081 -L 9001:localhost:9001 azureuser@<IP>
```

Con el túnel abierto: <http://localhost:8081/admin> (usuario `admin`, contraseña `KEYCLOAK_ADMIN_PASSWORD`
del `.env`) y <http://localhost:9001> (`MINIO_ROOT_USER` y `MINIO_ROOT_PASSWORD`).

## 9. Comandos útiles

| Para | Comando |
| --- | --- |
| Estado | `dc ps` |
| Logs de un servicio | `dc logs --tail 100 api` |
| Memoria | `docker stats --no-stream` |
| Recrear solo la API | `dc up -d api` |
