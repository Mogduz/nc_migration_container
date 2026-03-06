#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/.env

Description:
  Copies stage1 version file into the running Nextcloud app container
  using docker exec and enforces owner/group www-data:www-data.
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

app_container_name="${NEXTCLOUD_APP_CONTAINER_NAME:-}"
app_container_name="${app_container_name%$'\r'}"
[[ -n "$app_container_name" ]] || fail "NEXTCLOUD_APP_CONTAINER_NAME is empty in env"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_version_php="${script_dir}/../compose/stage1/files/versions.php"
target_version_php="/var/www/html/version.php"
tmp_version_php="/tmp/stage1-version.php"

[[ -f "$source_version_php" ]] || fail "Source file not found: $source_version_php"
if ! docker ps --format '{{.Names}}' | grep -Fxq "$app_container_name"; then
  fail "Container is not running: $app_container_name"
fi

echo "Copying ${source_version_php} to ${app_container_name}:${target_version_php}..."

cat "$source_version_php" | docker exec -u 0 -i "$app_container_name" sh -c "cat > '$tmp_version_php'"
docker exec -u 0 "$app_container_name" sh -c "install -o www-data -g www-data -m 0644 '$tmp_version_php' '$target_version_php' && rm -f '$tmp_version_php'"

owner_group="$(docker exec -u 0 "$app_container_name" sh -c "stat -c '%U:%G' '$target_version_php'")"
[[ "$owner_group" == "www-data:www-data" ]] || fail "Unexpected owner/group after copy: $owner_group"

echo "Done. ${target_version_php} owner/group is ${owner_group}."
