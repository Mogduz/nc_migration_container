#!/usr/bin/env bash
# Strikter Shell-Modus:
# -e  Abbruch bei Fehler
# -u  Fehler bei undefinierten Variablen
# -o pipefail  Pipeline-Fehler werden weitergereicht
set -euo pipefail

# Zentrale Pfade fuer Nextcloud, Konfiguration und SQLite-Auslagerung.
NC_PATH="/var/www/html/nextcloud"
NC_CONFIG_DIR="$NC_PATH/config"
NC_SQLITE_DIR="/mnt/NexCloud/sqlite"

# Einheitliches Logging mit Prefix.
log() {
  echo "[entrypoint] $*"
}

# Standardwerte, falls keine ENV-Variablen gesetzt sind.
: "${NC_ADMIN_USER:=admin}"
: "${NC_ADMIN_PASSWORD:=admin}"
: "${NC_TRUSTED_DOMAINS:=localhost}"
: "${NC_DATA_DIR:=/mnt/NexCloud/data}"

# Vorbereitende Verzeichnisse erstellen und Besitzrechte setzen.
log "Preparing data/config/sqlite directories"
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR" "$NC_SQLITE_DIR"
# Nur relevante Verzeichnisse rekursiv uebernehmen, um Startzeit begrenzt zu halten.
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR" "$NC_SQLITE_DIR"

# Schutzmechanismus:
# Wenn config.php bereits existiert, wird absichtlich nicht weiter initialisiert.
if [ -f "$NC_CONFIG_DIR/config.php" ]; then
  log "config.php already present; aborting startup as requested."
  exit 0
fi

# Ohne explizite Freigabe keine Auto-Installation.
if [ "${NC_AUTO_INSTALL:-0}" != "1" ]; then
  log "config.php missing; auto-install disabled (set NC_AUTO_INSTALL=1 to install)."
  exec "$@"
fi

log "config.php missing; proceeding with installation."

# Erstinstallation via SQLite, ausgefuehrt als www-data.
su -s /bin/sh www-data -c "php '$NC_PATH/occ' maintenance:install \
  --database 'sqlite' \
  --database-name 'nextcloud' \
  --admin-user '$NC_ADMIN_USER' \
  --admin-pass '$NC_ADMIN_PASSWORD' \
  --data-dir '$NC_DATA_DIR'"

# Trusted Domain in Nextcloud-Systemkonfiguration eintragen.
su -s /bin/sh www-data -c "php '$NC_PATH/occ' config:system:set trusted_domains 0 --value='$NC_TRUSTED_DOMAINS'"

# SQLite-Dateiname automatisch ermitteln (je nach Nextcloud/SQLite-Benennung).
DB_FILE=""
for f in nextcloud.db nextcloud.sqlite nextcloud.sqlite3; do
  if [ -f "$NC_DATA_DIR/$f" ]; then
    DB_FILE="$f"
    break
  fi
done

# Gefundene SQLite-Datei nach extern verschieben und Ruecklink setzen.
if [ -n "$DB_FILE" ]; then
  mkdir -p "$NC_SQLITE_DIR"
  if [ ! -f "$NC_SQLITE_DIR/$DB_FILE" ]; then
    mv "$NC_DATA_DIR/$DB_FILE" "$NC_SQLITE_DIR/$DB_FILE"
  fi
  ln -sfn "$NC_SQLITE_DIR/$DB_FILE" "$NC_DATA_DIR/$DB_FILE"
  chown -R www-data:www-data "$NC_SQLITE_DIR"
  log "SQLite DB moved to $NC_SQLITE_DIR/$DB_FILE and symlinked."
else
  log "WARNING: SQLite DB file not found in $NC_DATA_DIR"
fi

# Hauptprozess (CMD) starten.
exec "$@"
