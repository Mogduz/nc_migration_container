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
