#!/usr/bin/env bash
set -euo pipefail

log "Running 50-upgrade-map.sh"
log "Ensuring Nextcloud upgrade map allows ownCloud 10.16"
if [ -f /var/www/html/nextcloud/version.php ]; then
  sed -i "/'owncloud' =>/{
    n
    s/  array (/  array (/
    n
    s/'10\\.13' => true,/'10.16' => true,/
  }" /var/www/html/nextcloud/version.php || true
fi
