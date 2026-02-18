#!/usr/bin/env bash
# Strikter Modus fuer reproduzierbare Migrationsschritte.
set -euo pipefail

# Konsistentes Logging mit Skript-Prefix.
log() {
  echo "[migrate] $*"
}

# Helper fuer occ-Aufrufe:
# - OCC fuer regulare Kommandos
# - OCC_NOINT fuer non-interactive CI-/Skript-Ausfuehrung
OCC="php /var/www/html/nextcloud/occ"
OCC_NOINT="$OCC --no-interaction"

log "Starting migration steps"

# Fuehrt das eigentliche Nextcloud-Upgrade durch.
log "Running occ upgrade (non-interactive)"
$OCC_NOINT upgrade

# Sicherheitsmodus nach Upgrade explizit deaktivieren.
log "Disabling maintenance mode"
$OCC_NOINT maintenance:mode --off

# Standard-DB-Nacharbeiten fuer typische Migrationsinkonsistenzen.
log "Running database maintenance commands (non-interactive)"
$OCC_NOINT db:convert-filecache-bigint
$OCC_NOINT db:add-missing-columns
$OCC_NOINT db:add-missing-indices
$OCC_NOINT db:add-missing-primary-keys

# Aktualisiert alle installierten Apps auf kompatible Versionen.
log "Updating apps (non-interactive)"
$OCC_NOINT app:update --all

log "Migration finished"
log "Current status:"
# Statusausgabe darf fehlschlagen, ohne das Skript komplett zu stoppen.
$OCC_NOINT status || true

log "Creating database dump (gz) in /mnt/mysql"
# DB-Parameter aus Umgebungsvariablen uebernehmen.
DB_HOST="${MYSQL_HOST:-localhost}"
DB_NAME="${MYSQL_DATABASE:-nextcloud}"
DB_USER="${MYSQL_USER:-nextcloud}"
DB_PASS="${MYSQL_PASSWORD:-nextcloud}"
# Zeitstempel fuer eindeutig benannten Dump.
TS="$(date +%Y%m%d_%H%M%S)"
DUMP_PATH="/mnt/mysql/nextcloud_migration_${DB_NAME}_${TS}.sql.gz"

# Ohne gemountetes Zielverzeichnis wird Dump uebersprungen.
if [ ! -d /mnt/mysql ]; then
  log "WARNING: /mnt/mysql not mounted; skipping dump"
  exit 0
fi

log "Dumping database ${DB_NAME} to ${DUMP_PATH}"
# Single-transaction reduziert Locking bei InnoDB-Dumps.
mysqldump -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASS}" \
  --single-transaction --routines --triggers --events \
  "${DB_NAME}" | gzip -c > "${DUMP_PATH}"
log "Database dump completed"
