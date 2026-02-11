#!/usr/bin/env bash
set -euo pipefail

log "Preparing data/config/sqlite directories"
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"