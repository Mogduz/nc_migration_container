#!/usr/bin/env bash
set -euo pipefail

start_single_compose_container() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"

  ERROR_FUNCTION="start_single_compose_container"
  ERROR_MESSAGE=""

  if docker compose --env-file "$env_file" -f "$compose_file" up -d --no-deps "$service_name"; then
    ERROR_MESSAGE=""
    return 0
  fi
  ERROR_MESSAGE="Container '$service_name' konnte mit Compose-Datei '$compose_file' und Env-Datei '$env_file' nicht gestartet werden."
  return 1
}

start_compose() {
  local env_file="$1"
  local compose_file="$2"

  ERROR_FUNCTION="start_compose"
  ERROR_MESSAGE=""

  if docker compose --env-file "$env_file" -f "$compose_file" up -d; then
    ERROR_MESSAGE=""
    return 0
  fi
  ERROR_MESSAGE="Compose mit Datei '$compose_file' und Env-Datei '$env_file' konnte nicht gestartet werden."
  return 1
}

stop_compose() {
  local env_file="$1"
  local compose_file="$2"

  ERROR_FUNCTION="stop_compose"
  ERROR_MESSAGE=""

  if docker compose --env-file "$env_file" -f "$compose_file" down; then
    ERROR_MESSAGE=""
    return 0
  fi
  ERROR_MESSAGE="Compose mit Datei '$compose_file' und Env-Datei '$env_file' konnte nicht gestoppt werden."
  return 1
}

create_docker_network() {
  local network_name="$1"

  ERROR_FUNCTION="create_docker_network"
  ERROR_MESSAGE=""

  if docker network inspect "$network_name" >/dev/null 2>&1; then
    ERROR_MESSAGE=""
    return 0
  fi

  if docker network create "$network_name" >/dev/null 2>&1; then
    ERROR_MESSAGE=""
    return 0
  fi

  if docker network inspect "$network_name" >/dev/null 2>&1; then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="Docker-Netzwerk '$network_name' konnte nicht erstellt werden."
  return 1
}

copy_file_to_container() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local source_file="$4"
  local target_file="$5"
  local target_user="$6"
  local target_group="$7"

  ERROR_FUNCTION="copy_file_to_container"
  ERROR_MESSAGE=""

  if [ ! -f "$source_file" ]; then
    ERROR_MESSAGE="Quelldatei '$source_file' wurde auf dem Host nicht gefunden."
    return 1
  fi

  if ! docker compose --env-file "$env_file" -f "$compose_file" exec -T "$service_name" sh -lc 'mkdir -p "$(dirname "$1")"' -- "$target_file"; then
    ERROR_MESSAGE="Zielverzeichnis fuer '$target_file' im Service '$service_name' konnte nicht erstellt werden."
    return 1
  fi

  if ! docker compose --env-file "$env_file" -f "$compose_file" cp "$source_file" "$service_name:$target_file"; then
    ERROR_MESSAGE="Datei '$source_file' konnte nicht nach '$target_file' im Service '$service_name' kopiert werden."
    return 1
  fi

  if ! docker compose --env-file "$env_file" -f "$compose_file" exec -T "$service_name" chown "$target_user:$target_group" "$target_file"; then
    ERROR_MESSAGE="Eigentuemer/Besitzergruppe '$target_user:$target_group' konnte fuer '$target_file' im Service '$service_name' nicht gesetzt werden."
    return 1
  fi

  ERROR_MESSAGE=""
  return 0
}

run_container_command_as_user() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local run_user="$4"
  shift 4

  ERROR_FUNCTION="run_container_command_as_user"
  ERROR_MESSAGE=""

  if [ "$#" -eq 0 ]; then
    ERROR_MESSAGE="Kein Befehl fuer Service '$service_name' angegeben."
    return 1
  fi

  if [ "$#" -eq 1 ]; then
    if docker compose --env-file "$env_file" -f "$compose_file" exec -T --user "$run_user" "$service_name" sh -lc "$1"; then
      ERROR_MESSAGE=""
      return 0
    fi
  elif docker compose --env-file "$env_file" -f "$compose_file" exec -T --user "$run_user" "$service_name" "$@"; then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="Befehl '$*' konnte als User '$run_user' im Service '$service_name' nicht ausgefuehrt werden."
  return 1
}

run_occ_cmd_in_container() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local use_tty=true
  shift 3

  ERROR_FUNCTION="run_occ_cmd_in_container"
  ERROR_MESSAGE=""

  if [ "$#" -eq 0 ]; then
    ERROR_MESSAGE="Kein OCC-Befehl fuer Service '$service_name' angegeben."
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    use_tty=false
  fi

  if [ "$use_tty" = "true" ]; then
    if docker compose --env-file "$env_file" -f "$compose_file" exec --user "www-data" "$service_name" php /var/www/html/occ "$@"; then
      ERROR_MESSAGE=""
      return 0
    fi
  elif docker compose --env-file "$env_file" -f "$compose_file" exec -T --user "www-data" "$service_name" php /var/www/html/occ "$@"; then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="OCC-Befehl '$*' konnte im Service '$service_name' nicht als User 'www-data' ausgefuehrt werden."
  return 1
}

docker_state_running() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local container_id
  local running

  ERROR_FUNCTION="docker_state_running"
  ERROR_MESSAGE=""

  container_id="$(docker compose --env-file "$env_file" -f "$compose_file" ps -q "$service_name" 2>/dev/null | head -n 1 || true)"
  if [ -z "$container_id" ]; then
    ERROR_MESSAGE="Service '$service_name' konnte ueber Compose-Datei '$compose_file' nicht gefunden werden."
    return 1
  fi

  running="$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || true)"
  if [ "$running" = "true" ]; then
    return 0
  fi

  if [ -z "$running" ]; then
    ERROR_MESSAGE="Running-Status fuer Service '$service_name' konnte nicht gelesen werden."
  else
    ERROR_MESSAGE="Service '$service_name' laeuft nicht."
  fi
  return 1
}

docker_state_healthy() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local container_id
  local health

  ERROR_FUNCTION="docker_state_healthy"
  ERROR_MESSAGE=""

  container_id="$(docker compose --env-file "$env_file" -f "$compose_file" ps -q "$service_name" 2>/dev/null | head -n 1 || true)"
  if [ -z "$container_id" ]; then
    ERROR_MESSAGE="Service '$service_name' konnte ueber Compose-Datei '$compose_file' nicht gefunden werden."
    return 1
  fi

  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"
  if [ "$health" = "healthy" ]; then
    return 0
  fi

  if [ -z "$health" ]; then
    ERROR_MESSAGE="Health-Status fuer Service '$service_name' konnte nicht gelesen werden."
  elif [ "$health" = "no-healthcheck" ]; then
    ERROR_MESSAGE="Service '$service_name' hat keinen Healthcheck."
  else
    ERROR_MESSAGE="Service '$service_name' ist nicht healthy (aktueller Status: $health)."
  fi
  return 1
}

docker_wait_for_state() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local state="$4"
  local timeout="${5:-120}"
  local interval="${6:-2}"
  local started_at
  local now
  local elapsed
  local state_error

  ERROR_FUNCTION="docker_wait_for_state"
  ERROR_MESSAGE=""

  if [ "$state" != "healthy" ] && [ "$state" != "running" ]; then
    ERROR_MESSAGE="Unbekannter State '$state'. Erlaubt sind 'healthy' und 'running'."
    return 1
  fi

  started_at="$(date +%s)"
  while true; do
    if [ "$state" = "healthy" ]; then
      if docker_state_healthy "$env_file" "$compose_file" "$service_name"; then
        ERROR_FUNCTION="docker_wait_for_state"
        ERROR_MESSAGE=""
        return 0
      fi
    else
      if docker_state_running "$env_file" "$compose_file" "$service_name"; then
        ERROR_FUNCTION="docker_wait_for_state"
        ERROR_MESSAGE=""
        return 0
      fi
    fi

    state_error="$ERROR_MESSAGE"
    now="$(date +%s)"
    elapsed=$((now - started_at))
    if [ "$elapsed" -ge "$timeout" ]; then
      ERROR_FUNCTION="docker_wait_for_state"
      if [ -n "$state_error" ]; then
        ERROR_MESSAGE="State '$state' fuer Service '$service_name' wurde innerhalb von ${timeout}s nicht erreicht. Letzter Status: $state_error"
      else
        ERROR_MESSAGE="State '$state' fuer Service '$service_name' wurde innerhalb von ${timeout}s nicht erreicht."
      fi
      return 1
    fi

    sleep "$interval"
  done
}

docker_wait_for_log_string() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local search_string="$4"
  local timeout="${5:-300}"
  local start_time
  local cmd_status

  ERROR_FUNCTION="docker_wait_for_log_string"
  ERROR_MESSAGE=""
  start_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  timeout "${timeout}s" bash -c 'docker compose --env-file "$1" -f "$2" logs -f --since "$3" --no-color "$4" 2>&1 | grep -F -m1 -- "$5" >/dev/null' _ "$env_file" "$compose_file" "$start_time" "$service_name" "$search_string"
  cmd_status=$?

  if [ "$cmd_status" -eq 0 ]; then
    ERROR_MESSAGE=""
    printf 'true\n'
    return 0
  fi

  if [ "$cmd_status" -eq 124 ]; then
    ERROR_MESSAGE="String '$search_string' wurde innerhalb von ${timeout}s in den Logs von Service '$service_name' nicht gefunden."
  else
    ERROR_MESSAGE="Logs von Service '$service_name' konnten nicht ausgewertet werden."
  fi

  printf 'false\n'
  return 0
}
