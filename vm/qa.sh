#!/usr/bin/env bash
# Corre los comandos de QA de la API en un contenedor aparte (docker compose run), de a uno por vez.
# Uso: bash vm/qa.sh init | show <patient|nutritionist|smoke> | [--yes] <comando> [argumentos...]
set -euo pipefail

# Lista cerrada. Un comando nuevo de la API se agrega aquí y, si borra o recrea datos, también en DESTRUCTIVE.
QA_COMMANDS=(
  seed-qa reset-qa verify-qa process-ibs-sss
  audit-log inspect-qa archive-recommendations expire-recommendations
)
DESTRUCTIVE_COMMANDS=(seed-qa reset-qa)
PASSWORD_KEYS=(QA_PATIENT_PASSWORD QA_NUTRITIONIST_PASSWORD QA_SMOKE_PASSWORD)
QA_ENV_FILE=.env.qa
LOCK_FILE=.qa.lock
USAGE="Uso: bash vm/qa.sh init | show <patient|nutritionist|smoke> | [--yes] <comando> [argumentos...]
Comandos: ${QA_COMMANDS[*]}"

contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# 16 letras y dígitos, con al menos un dígito, una mayúscula y una minúscula (política del realm: 8, 1, 1 y 1).
random_password() {
  local value
  while :; do
    value="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-16)"
    if [ "${#value}" -eq 16 ] && [[ $value =~ [[:digit:]] && $value =~ [[:upper:]] && $value =~ [[:lower:]] ]]; then
      echo "$value"
      return
    fi
  done
}

init() {
  if [ -e "$QA_ENV_FILE" ]; then
    echo "Ya existe vm/$QA_ENV_FILE. No lo sobrescribo; para ver una contraseña: bash vm/qa.sh show <rol>" >&2
    exit 1
  fi
  command -v openssl >/dev/null 2>&1 || { echo "Falta openssl. Corre antes: bash vm/setup-vm.sh" >&2; exit 1; }

  local patient nutritionist smoke
  patient="$(random_password)"
  nutritionist="$(random_password)"
  smoke="$(random_password)"
  (
    umask 077
    set -o noclobber
    {
      echo "# Generado por qa.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ). Contraseñas de las cuentas de QA: no se copia ni se versiona."
      echo "QA_PATIENT_PASSWORD=$patient"
      echo "QA_NUTRITIONIST_PASSWORD=$nutritionist"
      echo "QA_SMOKE_PASSWORD=$smoke"
    } > "$QA_ENV_FILE"
  )
  chmod 600 "$QA_ENV_FILE"

  echo "Listo: vm/$QA_ENV_FILE creado con permiso 600."
  echo
  echo "Contraseñas para el documento de entrega (las usan todas las cuentas de QA de cada rol):"
  echo "  pacientes:      $patient"
  echo "  nutricionistas: $nutritionist"
  echo
  echo "Quedan guardadas en vm/$QA_ENV_FILE de esta VM. La de humo no se imprime: bash vm/qa.sh show smoke"
}

show() {
  local key
  case "${1:-}" in
    patient) key=QA_PATIENT_PASSWORD ;;
    nutritionist) key=QA_NUTRITIONIST_PASSWORD ;;
    smoke) key=QA_SMOKE_PASSWORD ;;
    *)
      echo "Uso: bash vm/qa.sh show <patient|nutritionist|smoke>" >&2
      exit 2
      ;;
  esac
  require_qa_env
  echo "Contraseña de QA ($1), de vm/$QA_ENV_FILE. No la pegues en chats, tickets ni conversaciones." >&2
  sed -n "s/^$key=//p" "$QA_ENV_FILE"
}

require_qa_env() {
  if [ ! -f "$QA_ENV_FILE" ]; then
    echo "Falta vm/$QA_ENV_FILE. Créalo una vez con: bash vm/qa.sh init" >&2
    exit 1
  fi
}

# Pide escribir el nombre del comando. Sin terminal (por ejemplo, cron) hace falta --yes.
confirm() {
  local name="$1" answer
  if [ ! -t 0 ]; then
    echo "$name borra o recrea datos de QA y no hay terminal para confirmar: agrega --yes." >&2
    exit 2
  fi
  read -r -p "$name borra o recrea datos de QA. Escribe $name para continuar: " answer
  if [ "$answer" != "$name" ]; then
    echo "Cancelado." >&2
    exit 1
  fi
}

run_command() {
  local name="$1"
  shift
  require_qa_env
  command -v flock >/dev/null 2>&1 || { echo "Falta flock (paquete util-linux)." >&2; exit 1; }

  local destructive=false
  contains "$name" "${DESTRUCTIVE_COMMANDS[@]}" && destructive=true
  if [ "$destructive" = true ] && [ "$ASSUME_YES" != true ]; then
    confirm "$name"
  fi

  # El candado se suelta solo cuando termina este proceso, también si lo matan.
  exec 9<>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "Ya corre otro comando de QA: $(head -n 1 "$LOCK_FILE"). Espera a que termine." >&2
    exit 1
  fi
  echo "$name (pid $$, desde $(date -u +%H:%M:%SZ))" > "$LOCK_FILE"

  set -a
  . "./$QA_ENV_FILE"
  set +a

  # Las contraseñas pasan por nombre: su valor no queda en la línea de comandos ni en el historial.
  local options=(--rm --no-deps -e QA_MODE=1)
  [ -t 0 ] && [ -t 1 ] || options+=(-T)
  [ "$destructive" = true ] && options+=(-e QA_ALLOW_DESTRUCTIVE=1)
  local key
  for key in "${PASSWORD_KEYS[@]}"; do
    options+=(-e "$key")
  done

  echo "Corriendo $name $* en un contenedor aparte (QA_MODE=1$([ "$destructive" = true ] && echo ', QA_ALLOW_DESTRUCTIVE=1'))..."
  local status=0
  docker compose -f docker-compose.vm.yml run "${options[@]}" api "$name" "$@" || status=$?

  case "$status" in
    0) echo "$name terminó bien." ;;
    1) echo "$name terminó con fallas (código 1): revisa las líneas de arriba." >&2 ;;
    2) echo "$name fue rechazado (código 2): falta una variable, un argumento no vale o esta versión de la API no tiene el comando." >&2 ;;
    *) echo "$name terminó con el código $status." >&2 ;;
  esac
  exit "$status"
}

main() {
  cd "$(dirname "$0")"

  ASSUME_YES=false
  local args=() arg
  for arg in "$@"; do
    if [ "$arg" = --yes ]; then
      ASSUME_YES=true
    else
      args+=("$arg")
    fi
  done
  set -- "${args[@]}"

  case "${1:-}" in
    init) init ;;
    show) show "${2:-}" ;;
    "")
      echo "$USAGE" >&2
      exit 2
      ;;
    *)
      if ! contains "$1" "${QA_COMMANDS[@]}"; then
        echo "Comando no permitido: $1" >&2
        echo "$USAGE" >&2
        exit 2
      fi
      run_command "$@"
      ;;
  esac
}

main "$@"
