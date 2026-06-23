# Cauce — Infrastructure

Stack local de Docker para el desarrollo de Cauce. Incluye Postgres, Adminer, Keycloak, KeyDB, MinIO y Ollama.

## Setup inicial (solo la primera vez)

1. Copiar el archivo de variables de entorno:
   ```bash
   cp .env.example .env
   ```

2. Editar `.env` y cambiar todos los valores marcados con `CAMBIA_ESTO`.

3. Verificar que Docker Desktop esté corriendo en Windows.

## Comandos diarios

### Levantar servicios

```bash
# Solo Postgres + Adminer (uso mínimo, ~300 MB RAM)
docker compose up -d

# + Keycloak (para trabajo de auth, ~1.5 GB RAM total)
docker compose --profile auth up -d

# + Keycloak + KeyDB + MinIO (para trabajo de features completas, ~2 GB RAM)
docker compose --profile auth --profile infra up -d

# Todo, incluyendo Ollama (~7-8 GB RAM cuando hace inferencia)
docker compose --profile all up -d
```

### Verificar estado

```bash
docker compose ps                  # qué contenedores están corriendo
docker compose logs -f postgres    # ver logs en vivo de un servicio
docker compose logs -f keycloak    # útil cuando Keycloak está booteando
```

### Parar servicios

```bash
docker compose stop                # apagar contenedores (datos persisten)
docker compose down                # apagar y borrar contenedores (datos persisten)
docker compose down -v             # apagar y BORRAR DATOS (cuidado)
```

### Apagar solo Ollama (libera 5-6 GB de RAM)

```bash
docker compose stop ollama
```

## URLs de acceso

| Servicio | URL | Notas |
| --- | --- | --- |
| Adminer | http://localhost:8080 | Sistema: PostgreSQL, Servidor: postgres |
| Keycloak | http://localhost:8081 | Admin Console: /admin |
| MinIO Console | http://localhost:9001 | UI web de MinIO |
| MinIO API | http://localhost:9000 | endpoint S3-compatible |
| Ollama API | http://localhost:11434 | endpoint LLM |
| Postgres | localhost:5432 | conexión directa con cliente SQL |
| KeyDB | localhost:6379 | conexión directa con redis-cli |

## Primera carga del modelo Llama 3.1 8B

Después de levantar Ollama por primera vez, hay que descargar el modelo. Esto es **~4.7 GB de descarga** y conviene hacerlo temprano:

```bash
docker compose --profile ai up -d ollama
docker exec -it cauce-ollama ollama pull llama3.1:8b
```

El modelo queda persistido en el volumen `cauce-ollama-data`. No se vuelve a descargar mientras no borres el volumen.

Para probar que funciona:
```bash
docker exec -it cauce-ollama ollama run llama3.1:8b "Hola, ¿qué es FODMAP?"
```

## Si ya tenías Postgres corriendo con datos previos

El script `postgres/init/01-create-keycloak-db.sh` solo se ejecuta cuando el volumen `cauce-postgres-data` está vacío. Si ya tienes datos previos del MVP, ejecuta manualmente:

```bash
docker exec -it cauce-postgres psql -U cauce -d cauce_dev
```

Y dentro de psql:
```sql
CREATE USER keycloak WITH PASSWORD 'tu_password_de_env';
CREATE DATABASE keycloak OWNER keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
\q
```

(Usa la misma contraseña que pusiste en `KEYCLOAK_DB_PASSWORD` del `.env`.)

## Troubleshooting

**Keycloak tarda mucho en arrancar.** Normal en el primer arranque (~45-60s). Mira los logs con `docker compose logs -f keycloak` hasta ver el mensaje `Keycloak X.Y started in N ms`.

**Puerto ocupado.** Cambia el puerto correspondiente en `.env` (ej. `KEYCLOAK_PORT=8082`) y reinicia con `docker compose up -d`.

**La laptop se pone lenta.** Apaga Ollama si no lo estás usando: `docker compose stop ollama`.

**Borrar todo y empezar de cero.**
```bash
docker compose down -v
docker volume prune -f
docker compose up -d
```

## Verificación de salud

Healthchecks definidos en cada servicio. Para ver el estado:
```bash
docker compose ps
```

La columna `STATUS` debe mostrar `Up X seconds (healthy)`. Si dice `(unhealthy)` o `(starting)` por más de 1-2 minutos, mira los logs del servicio.
