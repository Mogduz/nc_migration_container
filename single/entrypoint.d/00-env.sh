#!/usr/bin/env bash
set -euo pipefail

# Zentrale Pfade fuer Nextcloud-Migrationslauf.
NC_PATH="/var/www/html/nextcloud"
NC_CONFIG_DIR="$NC_PATH/config"

# Standardwerte fuer Migration.
: "${NC_DATA_DIR:=/mnt/NextCloud/data}"
