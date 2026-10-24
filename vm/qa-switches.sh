# Interruptores del modo QA en vm/.env. Lo cargan qa-mode.sh y generate-env.sh con source; no se ejecuta solo.
# OutboxDispatcher y NotificationDispatcher no están en la lista: siguen encendidos durante QA.

QA_SWITCH_KEYS=(
  WORKERS_IBS_SSS_REMINDER_ENABLED
  WORKERS_WEEKLY_REMINDER_ENABLED
  WORKERS_RECOMMENDATION_ARCHIVAL_ENABLED
  WORKERS_RECOMMENDATION_EXPIRATION_ENABLED
  RATE_LIMITING_ENABLED
)

# Valor de una clave en el archivo, o vacío si no está. Solo se usa con las claves de la lista.
qa_switch_get() {
  local file="$1" key="$2"
  awk -v k="$key" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$file"
}

# Deja las cinco claves con el mismo valor (true o false) y agrega las que falten; no toca ninguna otra línea.
# Reescribe el archivo en su lugar, así conserva su dueño y su permiso.
qa_switch_set_all() {
  local file="$1" value="$2" tmp
  tmp="$(mktemp "$file.XXXXXX")"
  if ! awk -v keys="${QA_SWITCH_KEYS[*]}" -v val="$value" '
    BEGIN { n = split(keys, list, " "); for (i = 1; i <= n; i++) wanted[list[i]] = 1 }
    {
      key = substr($0, 1, index($0, "=") - 1)
      if (key in wanted) {
        if (!(key in done)) { print key "=" val; done[key] = 1 }
        next
      }
      print
    }
    END { for (i = 1; i <= n; i++) if (!(list[i] in done)) print list[i] "=" val }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# on si las cinco están en false, off si todas valen true (una clave ausente vale true), mixed en otro caso.
qa_switch_mode() {
  local file="$1" key value on=0 off=0
  for key in "${QA_SWITCH_KEYS[@]}"; do
    value="$(qa_switch_get "$file" "$key")"
    case "${value:-true}" in
      false) on=$((on + 1)) ;;
      true) off=$((off + 1)) ;;
    esac
  done
  if [ "$on" -eq "${#QA_SWITCH_KEYS[@]}" ]; then
    echo on
  elif [ "$off" -eq "${#QA_SWITCH_KEYS[@]}" ]; then
    echo off
  else
    echo mixed
  fi
}
