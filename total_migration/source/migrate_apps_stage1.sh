#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/.env

Description:
  Runs app maintenance via docker exec + php occ as user www-data:
    1) disable + remove: calender, gallery, bruteforce_protection
    2) disable only: files_antivirus
    3) install + enable: calender
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

occ_exec() {
  docker exec -u www-data -w /var/www/html "$app_container_name" php occ "$@"
}

run_occ_allow_fail() {
  echo "-> occ $*"
  if ! occ_exec "$@"; then
    echo "WARN: occ $* failed, continuing."
  fi
}

apps_disable_remove=(
  "calender"
  "gallery"
  "bruteforce_protection"
)

for app_id in "${apps_disable_remove[@]}"; do
  echo
  echo "Processing app (disable + remove): ${app_id}"
  run_occ_allow_fail app:disable "${app_id}"
  run_occ_allow_fail app:remove "${app_id}"
done

echo
echo "Processing app (disable only): files_antivirus"
run_occ_allow_fail app:disable files_antivirus

echo
echo "Re-installing and enabling app: calender"
echo "-> occ app:install calender"
occ_exec app:install calender
echo "-> occ app:enable calender"
occ_exec app:enable calender

echo
echo "Done."
