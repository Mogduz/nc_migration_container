#!/usr/bin/env bash
# Fehler strikt behandeln, damit Healthcheck eindeutig fehlschlaegt.
set -euo pipefail

# Prueft lokale HTTP-Erreichbarkeit des Apache/Nextcloud-Endpunkts.
# Erfolgreicher HTTP-Handshake => Container gilt als healthy.
if curl -fsS -o /dev/null http://127.0.0.1/; then
  exit 0
fi

# Jede fehlgeschlagene Anfrage markiert den Healthcheck als failed.
exit 1
