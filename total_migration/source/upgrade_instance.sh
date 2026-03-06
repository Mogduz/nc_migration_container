#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/.env

Description:
  Runs Nextcloud OCC commands in this exact order via docker exec as user www-data.
  All commands run non-interactive and auto-confirm prompts with "yes":
    1) maintenance:mode --on
    2) upgrade
    3) maintenance:mode --off
    4) db:add-missing-columns
    5) db:add-missing-indices
    6) db:add-missing-primary-keys
    7) db:convert-filecache-bigint
    8) status (errors ignored)
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

env_file="$1"
[[ -f "$env_file" ]] || fail "Env file not found: $env_file"
command -v docker >/dev/null 2>&1 || fail "docker command not found"

env_dir="$(cd "$(dirname "$env_file")" && pwd)"
env_abs="${env_dir}/$(basename "$env_file")"

set -a
# shellcheck disable=SC1090
source "$env_abs"
set +a

app_container_name="${OCC_CONTAINER_NAME:-${NEXTCLOUD_APP_CONTAINER_NAME:-}}"
app_container_name="${app_container_name%$'\r'}"
[[ -n "$app_container_name" ]] || fail "OCC_CONTAINER_NAME and NEXTCLOUD_APP_CONTAINER_NAME are empty in env"

if ! docker ps --format '{{.Names}}' | grep -Fxq "$app_container_name"; then
  fail "Container is not running: $app_container_name"
fi

run_occ() {
  echo "-> occ --no-interaction $* (auto-yes)"
  yes | docker exec -i -u www-data -w /var/www/html "$app_container_name" php occ --no-interaction "$@"
}

run_final_status() {
  echo "-> occ --no-interaction status || true (final)"
  docker exec -u www-data -w /var/www/html "$app_container_name" php occ --no-interaction status || true
}

trap run_final_status EXIT

run_occ maintenance:mode --on
run_occ upgrade
run_occ maintenance:mode --off
run_occ db:add-missing-columns
run_occ db:add-missing-indices
run_occ db:add-missing-primary-keys
run_occ db:convert-filecache-bigint

echo "Done."
