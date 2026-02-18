#!/usr/bin/env bash
# Strikter Modus fuer den Versions-Mapping-Schritt.
set -euo pipefail

log "Running 50-upgrade-map.sh"
log "Ensuring Nextcloud upgrade map allows ownCloud 10.16"
# Patcht die Upgrade-Matrix in version.php, damit bestimmte
# ownCloud-Ausgangsversionen als gueltiger Upgrade-Pfad akzeptiert werden.
# Der sed-Aufruf ist absichtlich tolerant (`|| true`), damit ein
# abweichendes Datei-Layout den Containerstart nicht blockiert.
if [ -f /var/www/html/nextcloud/version.php ]; then
  sed -i "/'owncloud' =>/{
    n
    s/  array (/  array (/
    n
    s/'10\\.13' => true,/'10.16' => true,/
  }" /var/www/html/nextcloud/version.php || true
fi
