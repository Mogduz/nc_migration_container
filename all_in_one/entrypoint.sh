#!/usr/bin/env bash
set -euo pipefail

NC_PATH="/var/www/html/nextcloud"
NC_CONFIG_DIR="$NC_PATH/config"
NC_SQLITE_DIR="/mnt/NextCloud/sqlite"
NC_APPS_DIR="/mnt/NextCloud/apps"
NC_FILES_DIR="/mnt/NextCloud/files"
NC_SESSIONS_DIR="/mnt/NextCloud/sessions"

log() {
  echo "[entrypoint] $*"
}

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

log "Preparing data/config/sqlite directories"
mkdir -p "$NC_DATA_DIR" "$NC_CONFIG_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"
chown -R www-data:www-data "$NC_CONFIG_DIR" "$NC_DATA_DIR" "$NC_SQLITE_DIR" "$NC_APPS_DIR" "$NC_FILES_DIR" "$NC_SESSIONS_DIR"

log "Wiring apps, files, and sessions to mount points"
if [ -d "/var/www/html/nextcloud/custom_apps" ] && [ ! -L "/var/www/html/nextcloud/custom_apps" ]; then
  rm -rf /var/www/html/nextcloud/custom_apps
fi
ln -sfn "$NC_APPS_DIR" /var/www/html/nextcloud/custom_apps

if [ -d "/var/lib/php/sessions" ] && [ ! -L "/var/lib/php/sessions" ]; then
  rm -rf /var/lib/php/sessions
fi
ln -sfn "$NC_SESSIONS_DIR" /var/lib/php/sessions

log "Configuring Apache for Nextcloud"
sed -i 's#DocumentRoot /var/www/html#DocumentRoot /var/www/html/nextcloud#' /etc/apache2/sites-available/000-default.conf
cat > /etc/apache2/conf-available/nextcloud.conf <<'CONF'
<Directory /var/www/html/nextcloud>
  Require all granted
  AllowOverride All
  Options FollowSymLinks MultiViews
</Directory>
CONF
cat > /etc/apache2/conf-available/nextcloud-redirect.conf <<'CONF'
RedirectMatch 302 ^/nextcloud/?$ /
CONF
a2enconf nextcloud >/dev/null
a2enconf nextcloud-redirect >/dev/null

if [ -d "/mnt/redis" ]; then
  log "Configuring Redis to use /mnt/redis as data dir"
  mkdir -p /mnt/redis
  chown -R redis:redis /mnt/redis
  if grep -q '^dir ' /etc/redis/redis.conf; then
    sed -i 's#^dir .*#dir /mnt/redis#' /etc/redis/redis.conf
  else
    printf '\ndir /mnt/redis\n' >> /etc/redis/redis.conf
  fi
  REDIS_RDB_FILE=""
  for f in /mnt/redis/*.rdb; do
    if [ -f "$f" ]; then
      REDIS_RDB_FILE="$(basename "$f")"
      break
    fi
  done
  if [ -z "$REDIS_RDB_FILE" ]; then
    REDIS_RDB_FILE="dump.rdb"
  fi
  if grep -q '^dbfilename ' /etc/redis/redis.conf; then
    sed -i "s#^dbfilename .*#dbfilename ${REDIS_RDB_FILE}#" /etc/redis/redis.conf
  else
    printf 'dbfilename %s\n' "$REDIS_RDB_FILE" >> /etc/redis/redis.conf
  fi
else
  log "/mnt/redis not mounted; using default Redis data dir"
fi

MYSQL_ADMIN_CMD=(mysqladmin --defaults-file=/dev/null -h"$MYSQL_HOST" -uroot)
MYSQL_CMD=(mysql --defaults-file=/dev/null -h"$MYSQL_HOST" -uroot)
if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
  MYSQL_ADMIN_CMD+=(-p"$MYSQL_ROOT_PASSWORD")
  MYSQL_CMD+=(-p"$MYSQL_ROOT_PASSWORD")
fi

log "Starting MariaDB for installation"
mysqld_safe --datadir=/var/lib/mysql >/var/log/mysqld_safe.log 2>&1 &

log "Waiting for MariaDB to accept connections"
for i in $(seq 1 30); do
  if "${MYSQL_ADMIN_CMD[@]}" ping --silent; then
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    log "ERROR: MariaDB not ready"
    exit 1
  fi
done

log "Checking for SQL dumps in /mnt/mysql"
shopt -s nullglob
for dump in /mnt/mysql/*.sql /mnt/mysql/*.sql.gz; do
  if [ -f "$dump" ]; then
    log "Importing dump: $dump"
    DUMP_DB="${MYSQL_DUMP_DB:-}"
    if [ -z "$DUMP_DB" ]; then
      if [[ "$(basename "$dump")" == *owncloud* ]]; then
        DUMP_DB="owncloud"
      else
        DUMP_DB="$MYSQL_DATABASE"
      fi
    fi
    log "Ensuring database exists: $DUMP_DB"
    "${MYSQL_CMD[@]}" --force -e "CREATE DATABASE IF NOT EXISTS \`$DUMP_DB\`"
    if [[ "$dump" == *.gz ]]; then
      gzip -dc "$dump" | sed -E \
        -e 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`//g' \
        -e 's/DEFINER[ ]*=[ ]*[^ ]+//g' \
        | "${MYSQL_CMD[@]}" --binary-mode --force "$DUMP_DB"
    else
      sed -E \
        -e 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`//g' \
        -e 's/DEFINER[ ]*=[ ]*[^ ]+//g' \
        < "$dump" | "${MYSQL_CMD[@]}" --binary-mode --force "$DUMP_DB"
    fi
  fi
done
shopt -u nullglob

log "Shutting down MariaDB after import"
"${MYSQL_ADMIN_CMD[@]}" shutdown

exec "$@"
