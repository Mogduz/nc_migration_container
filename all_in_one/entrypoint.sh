#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[entrypoint] $*"
}

for f in /entrypoint.d/*.sh; do
  if [ -f "$f" ]; then
    # shellcheck source=/dev/null
    . "$f"
  fi
done

exec "$@"