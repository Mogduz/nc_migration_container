#!/usr/bin/env bash
# Strikter Modus fuer reproduzierbare Migrationsschritte.
set -euo pipefail

# Konsistentes Logging mit Skript-Prefix.
log() {
  echo "[migrate] $*"
}

# occ muss als Besitzer von config/config.php laufen (typisch: www-data).
run_occ() {
  su -s /bin/sh www-data -c "php /var/www/html/nextcloud/occ --no-interaction $*"
}

log "Starting migration steps"

# Fuehrt das eigentliche Nextcloud-Upgrade durch.
log "Running occ upgrade (non-interactive)"
run_occ upgrade

# Sicherheitsmodus nach Upgrade explizit deaktivieren.
log "Disabling maintenance mode"
run_occ maintenance:mode --off

# Standard-DB-Nacharbeiten fuer typische Migrationsinkonsistenzen.
log "Running database maintenance commands (non-interactive)"
run_occ db:convert-filecache-bigint
run_occ db:add-missing-columns
run_occ db:add-missing-indices
run_occ db:add-missing-primary-keys

# Aktualisiert alle installierten Apps auf kompatible Versionen.
log "Updating apps (non-interactive)"
run_occ app:update --all

log "Migration finished"
log "Current status:"
# Statusausgabe darf fehlschlagen, ohne das Skript komplett zu stoppen.
run_occ status || true

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
  --single-transaction \
  --routines --triggers --events \
  --default-character-set=utf8mb4 \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --no-tablespaces \
  "${DB_NAME}" | gzip -c > "${DUMP_PATH}"
log "Database dump completed"
