#!/usr/bin/env bash
# Strikter Shell-Modus fuer robuste Initialisierung.
set -euo pipefail

log "Running 00-env.sh"

# Basis-Pfade fuer Nextcloud-Bestandteile.
NC_PATH="/var/www/html/nextcloud"
NC_CONFIG_DIR="$NC_PATH/config"
NC_SQLITE_DIR="$NC_PATH/sqlite"
NC_APPS_DIR="$NC_PATH/custom"
NC_FILES_DIR="$NC_PATH/data"
NC_SESSIONS_DIR="/var/lib/php/sessions"

# Nextcloud-Defaults; koennen per ENV ueberschrieben werden.
: "${NC_ADMIN_USER:=admin}"
: "${NC_ADMIN_PASSWORD:=admin}"
: "${NC_DATA_DIR:=${NC_FILES_DIR}}"

# MariaDB-Defaults fuer lokale Migrationsumgebung.
: "${MYSQL_DATABASE:=nextcloud}"
: "${MYSQL_USER:=nextcloud}"
: "${MYSQL_PASSWORD:=nextcloud}"
: "${MYSQL_ROOT_PASSWORD:=}"
: "${MYSQL_HOST:=localhost}"

# Mapping auf ownCloud-kompatible Variablennamen.
# Diese Werte koennen in Migrations-/Override-Konfigurationen weiterverwendet werden.
: "${DB_TYPE:=mysql}"
: "${OWNCLOUD_DB_TYPE:=${DB_TYPE}}"
: "${OWNCLOUD_DB_HOST:=${MYSQL_HOST}}"
: "${OWNCLOUD_DB_NAME:=${MYSQL_DATABASE}}"
: "${OWNCLOUD_DB_USER:=${MYSQL_USER}}"
: "${OWNCLOUD_DB_PASSWORD:=${MYSQL_PASSWORD}}"
# Export, damit nachfolgende Skripte/Prozesse die Variablen sehen.
export OWNCLOUD_DB_TYPE OWNCLOUD_DB_HOST OWNCLOUD_DB_NAME OWNCLOUD_DB_USER OWNCLOUD_DB_PASSWORD
