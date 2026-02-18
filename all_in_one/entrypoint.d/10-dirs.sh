#!/usr/bin/env bash
# Strikter Modus fuer verlassliche Startphase.
set -euo pipefail

log "Running 10-dirs.sh"
log "Preparing data/config/sqlite directories"
# Alle benoetigten Laufzeitverzeichnisse erzeugen.
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"
# Standard-Besitzer fuer Web-/PHP-Zugriff setzen.
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"

log "Fixing permissions on mounted volumes"
# Hilfsfunktion:
# - Verzeichnisse: 750
# - Dateien:      640
# Ziel: restriktive, aber funktionale Rechte fuer Nextcloud.
apply_nc_permissions() {
  local dir="$1"
  if [ -d "$dir" ]; then
    chown -R www-data:www-data "$dir"
    find "$dir" -type d -exec chmod 750 {} +
    find "$dir" -type f -exec chmod 640 {} +
  fi
}

# Rechte fuer zentrale Nextcloud-Mounts anwenden.
apply_nc_permissions "$NC_CONFIG_DIR"
apply_nc_permissions "$NC_APPS_DIR"
apply_nc_permissions "$NC_FILES_DIR"

log "Ensuring config dir is writable for www-data"
# config-Verzeichnis bekommt zusaetzlich Schreibrechte fuer Runtime-Updates.
if [ -d "$NC_CONFIG_DIR" ]; then
  chown -R www-data:www-data "$NC_CONFIG_DIR" || true
  chmod 770 "$NC_CONFIG_DIR" || true
  find "$NC_CONFIG_DIR" -type d -exec chmod 770 {} + || true
  find "$NC_CONFIG_DIR" -type f -exec chmod 660 {} + || true
fi

log "Ensuring /mnt/mysql is writable for www-data"
# Falls SQL-Dumps gemountet sind, auch dort Schreibrechte setzen
# (z. B. fuer Export nach erfolgreicher Migration).
if [ -d "/mnt/mysql" ]; then
  chown -R www-data:www-data /mnt/mysql || true
  find /mnt/mysql -type d -exec chmod 770 {} + || true
  find /mnt/mysql -type f -exec chmod 660 {} + || true
fi

# Sessions restriktiv halten (700/600), da sensible Laufzeitdaten.
if [ -d "$NC_SESSIONS_DIR" ]; then
  chown -R www-data:www-data "$NC_SESSIONS_DIR"
  chmod 700 "$NC_SESSIONS_DIR"
  find "$NC_SESSIONS_DIR" -type f -exec chmod 600 {} +
fi

# Falls config.php schon existiert: lesbar fuer Dienst, nicht world-readable.
if [ -f "$NC_CONFIG_DIR/config.php" ]; then
  chmod 640 "$NC_CONFIG_DIR/config.php"
fi
