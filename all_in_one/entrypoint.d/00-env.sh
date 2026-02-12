#!/usr/bin/env bash
set -euo pipefail

log "Running 00-env.sh"

NC_PATH="/var/www/html/nextcloud"
NC_CONFIG_DIR="$NC_PATH/config"
NC_SQLITE_DIR="$NC_PATH/sqlite"
NC_APPS_DIR="$NC_PATH/custom"
NC_FILES_DIR="$NC_PATH/data"
NC_SESSIONS_DIR="/var/lib/php/sessions"

# Defaults (can be overridden via env)
: "${NC_ADMIN_USER:=admin}"
: "${NC_ADMIN_PASSWORD:=admin}"
: "${NC_TRUSTED_DOMAINS:=localhost}"
: "${NC_DATA_DIR:=${NC_FILES_DIR}}"

# MariaDB defaults
: "${MYSQL_DATABASE:=nextcloud}"
: "${MYSQL_USER:=nextcloud}"
: "${MYSQL_PASSWORD:=nextcloud}"
: "${MYSQL_ROOT_PASSWORD:=}"
: "${MYSQL_HOST:=localhost}"

# Map compose env vars to ownCloud-style overrides (used by overwrite.config.php)
: "${DB_TYPE:=mysql}"
: "${OWNCLOUD_DB_TYPE:=${DB_TYPE}}"
: "${OWNCLOUD_DB_HOST:=${MYSQL_HOST}}"
: "${OWNCLOUD_DB_NAME:=${MYSQL_DATABASE}}"
: "${OWNCLOUD_DB_USER:=${MYSQL_USER}}"
: "${OWNCLOUD_DB_PASSWORD:=${MYSQL_PASSWORD}}"
export OWNCLOUD_DB_TYPE OWNCLOUD_DB_HOST OWNCLOUD_DB_NAME OWNCLOUD_DB_USER OWNCLOUD_DB_PASSWORD
