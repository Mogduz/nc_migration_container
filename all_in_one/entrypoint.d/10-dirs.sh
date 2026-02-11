#!/usr/bin/env bash
set -euo pipefail

log "Running 10-dirs.sh"
log "Preparing data/config/sqlite directories"
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"

log "Fixing permissions on mounted volumes"
for dir in "$NC_CONFIG_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR"; do
  if [ -d "$dir" ]; then
    chown -R www-data:www-data "$dir"
    find "$dir" -type d -exec chmod 750 {} +
    find "$dir" -type f -exec chmod 640 {} +
  fi
done

if [ -d "$NC_SESSIONS_DIR" ]; then
  chown -R www-data:www-data "$NC_SESSIONS_DIR"
  chmod 700 "$NC_SESSIONS_DIR"
  find "$NC_SESSIONS_DIR" -type f -exec chmod 600 {} +
fi

if [ -f "$NC_CONFIG_DIR/config.php" ]; then
  chmod 640 "$NC_CONFIG_DIR/config.php"
fi
