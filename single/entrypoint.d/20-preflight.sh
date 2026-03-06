#!/usr/bin/env bash
set -euo pipefail

# Kein Installationsmodus: Migration erwartet eine vorhandene Nextcloud-Konfiguration.
if [ ! -f "$NC_CONFIG_DIR/config.php" ]; then
  log "ERROR: config.php missing at $NC_CONFIG_DIR/config.php"
  log "ERROR: this container is migration-only and will not run installation."
  log "ERROR: mount an existing Nextcloud config (migrated from ownCloud) to /mnt/NextCloud/config."
  exit 1
fi

log "Preflight OK: existing config.php found."
