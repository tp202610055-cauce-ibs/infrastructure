#!/usr/bin/env bash
# Enciende, apaga o muestra el modo QA en vm/.env: cuatro workers programados y el límite de peticiones.
# Uso: bash vm/qa-mode.sh on|off|status      (no recrea la API: imprime el comando para hacerlo)
set -euo pipefail

cd "$(dirname "$0")"
. ./qa-switches.sh

ENV_FILE=.env
USAGE="Uso: bash vm/qa-mode.sh on|off|status"

# Variable de entorno del contenedor de la API que corresponde a cada clave de .env.
container_name_of() {
  case "$1" in
    WORKERS_IBS_SSS_REMINDER_ENABLED) echo Workers__IbsSssReminder__Enabled ;;
    WORKERS_WEEKLY_REMINDER_ENABLED) echo Workers__WeeklyReminder__Enabled ;;
    WORKERS_RECOMMENDATION_ARCHIVAL_ENABLED) echo Workers__RecommendationArchival__Enabled ;;
    WORKERS_RECOMMENDATION_EXPIRATION_ENABLED) echo Workers__RecommendationExpiration__Enabled ;;
    RATE_LIMITING_ENABLED) echo RateLimiting__Enabled ;;
  esac
}

# Valores que usa la API en marcha, solo de las cinco claves. Vacío si Docker o el contenedor no están.
running_values() {
  local id
  id="$(docker compose -f docker-compose.vm.yml ps -q api 2>/dev/null || true)"
  [ -n "$id" ] || return 0
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" 2>/dev/null \
    | grep -E '^(Workers__(IbsSssReminder|WeeklyReminder|RecommendationArchival|RecommendationExpiration)__Enabled|RateLimiting__Enabled)=' \
    || true
}

print_switches() {
  local key value running live
  running="$(running_values)"
  printf '  %-44s %-8s %s\n' "Clave en vm/.env" "Valor" "API en marcha"
  for key in "${QA_SWITCH_KEYS[@]}"; do
    value="$(qa_switch_get "$ENV_FILE" "$key")"
    live="$(printf '%s\n' "$running" | sed -n "s/^$(container_name_of "$key")=//p")"
    printf '  %-44s %-8s %s\n' "$key" "${value:-(true)}" "${live:-?}"
  done
  echo "  (true) = la clave no está y vale true. ? = la API no está en marcha o Docker no responde."
}

print_banner() {
  case "$(qa_switch_mode "$ENV_FILE")" in
    on)
      echo "=================================================================================="
      echo "  MODO QA ENCENDIDO: recordatorios, archivado, expiración y límite de peticiones"
      echo "  apagados. Los disparos van a demanda: bash vm/qa.sh <comando>"
      echo "=================================================================================="
      ;;
    off)
      echo "Modo QA apagado: los workers programados y el límite de peticiones están encendidos."
      ;;
    *)
      echo "=================================================================================="
      echo "  MODO QA A MEDIAS: las cinco claves no coinciden."
      echo "  Déjalas parejas con: bash vm/qa-mode.sh on   (o off)"
      echo "=================================================================================="
      ;;
  esac
}

main() {
  local action="${1:-}"
  case "$action" in
    on | off | status) ;;
    *)
      echo "$USAGE" >&2
      exit 2
      ;;
  esac

  if [ ! -f "$ENV_FILE" ]; then
    echo "No existe vm/$ENV_FILE. Créalo antes con: bash vm/generate-env.sh <dominio> <correo>" >&2
    exit 1
  fi

  local mode
  mode="$(stat -c %a "$ENV_FILE")"
  if [ "$mode" != 600 ]; then
    echo "Aviso: vm/$ENV_FILE tenía permiso $mode; lo dejo en 600." >&2
    chmod 600 "$ENV_FILE"
  fi

  if [ "$action" = status ]; then
    print_switches
    echo
    print_banner
    return
  fi

  echo "Antes:"
  print_switches
  local value=true
  [ "$action" = on ] && value=false
  qa_switch_set_all "$ENV_FILE" "$value"
  echo
  echo "Después:"
  print_switches
  echo
  print_banner
  echo
  echo "La API en marcha no cambia hasta recrearla. Hazlo FUERA DEL HORARIO DE PRUEBAS (corta la API de 30 a 60 s):"
  echo "  docker compose -f docker-compose.vm.yml up -d api      (con el atajo: dc up -d api)"
}

main "$@"
