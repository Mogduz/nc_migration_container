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
