#!/usr/bin/env bash
# Strikter Modus fuer DB-Initialisierung und Import.
set -euo pipefail

log "Running 30-database.sh"
log "Restricting MySQL to localhost"

MYSQL_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"

ensure_mysql_bind_localhost() {
  # MySQL 8 auf localhost binden (Sicherheits- und Einfachheitsaspekt im AIO-Setup).
  if grep -Eq '^[[:space:]]*bind-address[[:space:]]*=' "$MYSQL_CNF"; then
    sed -i 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 127.0.0.1/' "$MYSQL_CNF"
  else
    printf '\nbind-address = 127.0.0.1\n' >> "$MYSQL_CNF"
  fi

  # Nur setzen, wenn die Option in der vorhandenen Datei bereits existiert.
  if grep -Eq '^[[:space:]#]*mysqlx-bind-address[[:space:]]*=' "$MYSQL_CNF"; then
    sed -i 's/^[[:space:]#]*mysqlx-bind-address[[:space:]]*=.*/mysqlx-bind-address = 127.0.0.1/' "$MYSQL_CNF"
  fi
}

ensure_mysql_datadir_initialized() {
  mkdir -p /var/lib/mysql /var/run/mysqld
  chown -R mysql:mysql /var/lib/mysql /var/run/mysqld
  # Nur initialisieren, wenn das Systemschema noch fehlt.
  if [ ! -d /var/lib/mysql/mysql ]; then
    log "Initializing MySQL datadir (insecure)"
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
  fi
  chown -R mysql:mysql /var/lib/mysql /var/run/mysqld
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sanitize_dump() {
  perl -ne '
    if ($. == 1) { s/^\x{FEFF}//; }
    s/\r$//;
    next if /^\s*SET\s+@@(?:GLOBAL\.)?GTID_PURGED\s*=/i;
    next if /^\s*SET\s+@@(?:SESSION|GLOBAL)\.SQL_LOG_BIN\s*=/i;
    next if /^\s*SET\s+@@GLOBAL\.time_zone\s*=/i;
    s/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`//g;
    s/DEFINER[ ]*=[ ]*[^ ]+//g;
    print;
  '
}

ensure_mysql_bind_localhost
ensure_mysql_datadir_initialized

# Root-Admin-Kommandos zunaechst ohne Passwort via lokalem Socket.
SOCKET_ADMIN_CMD=(mysqladmin --defaults-file=/dev/null -uroot)
SOCKET_MYSQL_CMD=(mysql --defaults-file=/dev/null -uroot)
MYSQL_ADMIN_CMD=("${SOCKET_ADMIN_CMD[@]}")
MYSQL_CMD=("${SOCKET_MYSQL_CMD[@]}")

log "Starting MySQL for installation"
# MySQL temporaer starten, um Setup und Dump-Import durchzufuehren.
mysqld_safe --datadir=/var/lib/mysql >/var/log/mysqld_safe.log 2>&1 &

log "Waiting for MySQL to accept connections"
# Bis zu 30 Sekunden auf DB-Verfuegbarkeit warten.
for i in $(seq 1 30); do
  if "${SOCKET_ADMIN_CMD[@]}" ping --silent; then
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    log "ERROR: MySQL not ready"
    exit 1
  fi
done

log "Configuring root user and creating database/user"
if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
  ROOT_PASS_ESCAPED="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
  # Root zuerst socketbasiert setzen, danach mit Passwort nutzbar machen.
  "${SOCKET_MYSQL_CMD[@]}" --force -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS_ESCAPED}'; FLUSH PRIVILEGES;"
  MYSQL_ADMIN_CMD=(mysqladmin --defaults-file=/dev/null -h"$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD")
  MYSQL_CMD=(mysql --defaults-file=/dev/null -h"$MYSQL_HOST" -uroot -p"$MYSQL_ROOT_PASSWORD")
fi

# Ziel-Datenbank und lokaler Anwendungsvendor-User.
USER_DB="${MYSQL_DATABASE}"
USER_DB_ESCAPED="$(sql_escape "$USER_DB")"
MYSQL_USER_ESCAPED="$(sql_escape "$MYSQL_USER")"
MYSQL_PASSWORD_ESCAPED="$(sql_escape "$MYSQL_PASSWORD")"
"${MYSQL_CMD[@]}" --force -e "CREATE DATABASE IF NOT EXISTS \`${USER_DB_ESCAPED}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
"${MYSQL_CMD[@]}" --force -e "CREATE USER IF NOT EXISTS '${MYSQL_USER_ESCAPED}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASSWORD_ESCAPED}'; GRANT ALL PRIVILEGES ON \`${USER_DB_ESCAPED}\`.* TO '${MYSQL_USER_ESCAPED}'@'localhost'; FLUSH PRIVILEGES;"

log "Checking for SQL dumps in /mnt/mysql"
# Nullglob vermeidet literale Muster, wenn keine Dateien existieren.
shopt -s nullglob
for dump in /mnt/mysql/*.sql /mnt/mysql/*.sql.gz; do
  if [ -f "$dump" ]; then
    DUMP_DB="${MYSQL_DUMP_DB:-$MYSQL_DATABASE}"
    log "Importing dump: $dump"
    log "Using database: $DUMP_DB"
    log "Applying dump sanitization: CRLF/BOM, DEFINER, GTID_PURGED, SQL_LOG_BIN, time_zone"
    MYSQL_USER_CMD=(mysql --defaults-file=/dev/null -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD")
    # Identische Sanitizer-Pipeline fuer .sql und .sql.gz.
    if [[ "$dump" == *.gz ]]; then
      gzip -dc "$dump" | sanitize_dump | "${MYSQL_USER_CMD[@]}" --binary-mode --force "$DUMP_DB"
    else
      sanitize_dump < "$dump" | "${MYSQL_USER_CMD[@]}" --binary-mode --force "$DUMP_DB"
    fi
  fi
done
shopt -u nullglob

# Optional: Tabellenliste ausgeben, wenn ein Dump verarbeitet wurde.
if [ -n "${DUMP_DB:-}" ]; then
  log "Listing tables in $DUMP_DB"
  MYSQL_USER_CMD=(mysql --defaults-file=/dev/null -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD")
  "${MYSQL_USER_CMD[@]}" --batch --raw -e "SHOW TABLES;" "$DUMP_DB" || true
fi

log "Shutting down MySQL after import"
# Sauberer Shutdown; spaeter uebernimmt Supervisor den DB-Start.
"${MYSQL_ADMIN_CMD[@]}" shutdown
