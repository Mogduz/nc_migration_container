#!/usr/bin/env bash
set -euo pipefail

# Alle Ausgaben in Container-STDOUT/STDERR lassen und parallel
# in eine Datei spiegeln (fuer spaetere Diagnose im Container).
ENTRYPOINT_LOG_FILE="${ENTRYPOINT_LOG_FILE:-/var/log/entrypoint.log}"
mkdir -p "$(dirname "$ENTRYPOINT_LOG_FILE")"
touch "$ENTRYPOINT_LOG_FILE"
exec > >(tee -a "$ENTRYPOINT_LOG_FILE") 2>&1

# Einheitliches Logging fuer den gesamten Entry-Flow.
log() {
  echo "[entrypoint] $*"
}

# Schrittweise Initialisierung aus modularen Skripten.
for f in /entrypoint.d/*.sh; do
  if [ -f "$f" ]; then
    log "Running $(basename "$f")"
    # shellcheck source=/dev/null
    . "$f"
  fi
done

# Hauptprozess starten.
exec "$@"
