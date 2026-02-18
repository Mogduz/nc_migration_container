#!/usr/bin/env bash
# Strikter Ausfuehrungsmodus fuer robuste Initialisierung.
set -euo pipefail

# Einheitliche Log-Ausgabe fuer alle Entry-Skripte.
log() {
  echo "[entrypoint] $*"
}

# Modularer Start:
# Fuehrt alle Skripte in /entrypoint.d in alphabetischer Reihenfolge aus.
# Die Skripte werden "gesourced", damit gesetzte Variablen erhalten bleiben.
for f in /entrypoint.d/*.sh; do
  if [ -f "$f" ]; then
    log "Running $(basename "$f")"
    # shellcheck source=/dev/null
    . "$f"
  fi
done

# Danach den eigentlichen Hauptprozess starten (CMD).
exec "$@"
