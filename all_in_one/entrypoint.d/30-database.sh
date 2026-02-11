#!/usr/bin/env bash
set -euo pipefail

log "Restricting MariaDB to localhost"
if grep -q '^bind-address' /etc/mysql/mariadb.conf.d/50-server.cnf; then
  sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf
else
  printf '\nbind-address = 127.0.0.1\n' >> /etc/mysql/mariadb.conf.d/50-server.cnf
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

log "Configuring root user and creating database/user"
if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
  "${MYSQL_CMD[@]}" --force -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
fi
USER_DB="${MYSQL_DATABASE}"
"${MYSQL_CMD[@]}" --force -e "CREATE DATABASE IF NOT EXISTS \`${USER_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
"${MYSQL_CMD[@]}" --force -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}'; GRANT ALL PRIVILEGES ON \`${USER_DB}\`.* TO '${MYSQL_USER}'@'localhost'; FLUSH PRIVILEGES;"

log "Checking for SQL dumps in /mnt/mysql"
shopt -s nullglob
for dump in /mnt/mysql/*.sql /mnt/mysql/*.sql.gz; do
  if [ -f "$dump" ]; then
    log "Importing dump: $dump"
    DUMP_DB="${MYSQL_DUMP_DB:-$MYSQL_DATABASE}"
    log "Using database: $DUMP_DB"
    MYSQL_USER_CMD=(mysql --defaults-file=/dev/null -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD")
    if [[ "$dump" == *.gz ]] && gzip -t "$dump" >/dev/null 2>&1; then
      gzip -dc "$dump" | perl -pe 's/\r//g; s/\\-/-/g; s/^\x{FEFF}//; s/^--/--/; s/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`//g; s/DEFINER[ ]*=[ ]*[^ ]+//g' \
        | "${MYSQL_USER_CMD[@]}" --binary-mode --force "$DUMP_DB"
    else
      perl -pe 's/\r//g; s/\\-/-/g; s/^\x{FEFF}//; s/^--/--/; s/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`//g; s/DEFINER[ ]*=[ ]*[^ ]+//g' < "$dump" \
        | "${MYSQL_USER_CMD[@]}" --binary-mode --force "$DUMP_DB"
    fi
  fi
done
shopt -u nullglob

log "Shutting down MariaDB after import"
"${MYSQL_ADMIN_CMD[@]}" shutdown