#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[migrate] $*"
}

OCC="php /var/www/html/nextcloud/occ"
OCC_NOINT="$OCC --no-interaction"

log "Starting migration steps"

log "Running occ upgrade (non-interactive)"
$OCC_NOINT upgrade

log "Disabling maintenance mode"
$OCC_NOINT maintenance:mode --off

log "Running database maintenance commands (non-interactive)"
$OCC_NOINT db:convert-filecache-bigint
$OCC_NOINT db:add-missing-columns
$OCC_NOINT db:add-missing-indices
$OCC_NOINT db:add-missing-primary-keys

log "Updating apps (non-interactive)"
$OCC_NOINT app:update --all

log "Migration finished"
log "Current status:"
$OCC_NOINT status || true

log "Creating database dump (gz) in /mnt/mysql"
DB_HOST="${MYSQL_HOST:-localhost}"
DB_NAME="${MYSQL_DATABASE:-nextcloud}"
DB_USER="${MYSQL_USER:-nextcloud}"
DB_PASS="${MYSQL_PASSWORD:-nextcloud}"
TS="$(date +%Y%m%d_%H%M%S)"
DUMP_PATH="/mnt/mysql/nextcloud_migration_${DB_NAME}_${TS}.sql.gz"

if [ ! -d /mnt/mysql ]; then
  log "WARNING: /mnt/mysql not mounted; skipping dump"
  exit 0
fi

log "Dumping database ${DB_NAME} to ${DUMP_PATH}"
mysqldump -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASS}" \
  --single-transaction --routines --triggers --events \
  "${DB_NAME}" | gzip -c > "${DUMP_PATH}"
log "Database dump completed"
