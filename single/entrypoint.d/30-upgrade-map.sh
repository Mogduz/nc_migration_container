#!/usr/bin/env bash
set -euo pipefail

log "Ensuring Nextcloud upgrade map allows ownCloud 10.16"
# Patcht die Upgrade-Matrix in version.php, damit ownCloud 10.16
# als gueltiger Upgrade-Pfad akzeptiert wird.
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
