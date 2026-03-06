#!/usr/bin/env bash
set -euo pipefail

log "Preparing data/config directories"
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR"
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR"
