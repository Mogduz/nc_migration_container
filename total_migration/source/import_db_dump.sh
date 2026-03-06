#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
START_TS="$(date +%s)"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  local level="$1"
  shift
  printf '[%s] %-5s %s\n' "$(timestamp)" "$level" "$*"
}

section() {
  local title="$1"
  printf '\n%s\n' "================================================================"
  printf '%s\n' "$title"
  printf '%s\n' "================================================================"
}

mask_secret() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf '<leer>'
  else
    printf '*** (%d Zeichen)' "${#value}"
  fi
}

human_bytes() {
  local bytes="$1"
  local units=(B KiB MiB GiB TiB)
  local unit_index=0
  local value="$bytes"

  while (( value >= 1024 && unit_index < ${#units[@]} - 1 )); do
    value=$((value / 1024))
    unit_index=$((unit_index + 1))
  done

  printf '%s %s' "$value" "${units[$unit_index]}"
}

usage() {
  cat <<EOF
Verwendung:
  $SCRIPT_NAME /pfad/zur/.env

Beispiel:
  $SCRIPT_NAME ../.env

Das Script:
1. Liest die .env ein
2. Wartet auf MySQL im Zielcontainer
3. Legt Root/User/DB inkl. Rechte an
4. Importiert den Dump als MYSQL_USER
5. Zeigt einen Import-Report zur Nachvollziehbarkeit
EOF
}

fail() {
  log "ERROR" "$*"
  exit 1
}

on_error() {
  local exit_code=$?
  log "ERROR" "Unerwarteter Abbruch in Zeile ${BASH_LINENO[0]} beim Befehl: ${BASH_COMMAND}"
  exit "$exit_code"
}

trap on_error ERR

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

env_file="$1"
if [[ ! -f "$env_file" ]]; then
  fail "Env-Datei nicht gefunden: $env_file"
fi

env_file_dir="$(cd "$(dirname "$env_file")" && pwd)"
env_file_abs="${env_file_dir}/$(basename "$env_file")"

set -a
# shellcheck disable=SC1090
source "$env_file_abs"
set +a

db_container_name="${DB_CONTAINER_NAME:-db}"
mysql_database="${MYSQL_DATABASE:-nextcloud}"
mysql_user="${MYSQL_USER:-}"
mysql_password="${MYSQL_PASSWORD:-}"
mysql_root_password="${MYSQL_ROOT_PASSWORD:-}"
db_dump_path="${DB_DUMP_PATH:-}"
mysql_wait_timeout="${MYSQL_WAIT_TIMEOUT_SECONDS:-120}"

# CRLF aus Windows-.env entfernen, damit Credentials nicht verfälscht werden.
db_container_name="${db_container_name%$'\r'}"
mysql_database="${mysql_database%$'\r'}"
mysql_user="${mysql_user%$'\r'}"
mysql_password="${mysql_password%$'\r'}"
mysql_root_password="${mysql_root_password%$'\r'}"
db_dump_path="${db_dump_path%$'\r'}"
mysql_wait_timeout="${mysql_wait_timeout%$'\r'}"

command -v docker >/dev/null 2>&1 || fail "docker wurde nicht gefunden"
[[ -n "$mysql_root_password" ]] || fail "MYSQL_ROOT_PASSWORD ist leer"
[[ -n "$mysql_user" ]] || fail "MYSQL_USER ist leer"
[[ -n "$mysql_password" ]] || fail "MYSQL_PASSWORD ist leer"
[[ -n "$db_dump_path" ]] || fail "DB_DUMP_PATH ist leer"
[[ "$mysql_database" =~ ^[A-Za-z0-9_]+$ ]] || fail "MYSQL_DATABASE darf nur [A-Za-z0-9_] enthalten"
[[ "$mysql_wait_timeout" =~ ^[0-9]+$ ]] || fail "MYSQL_WAIT_TIMEOUT_SECONDS muss numerisch sein"

if [[ "$db_dump_path" = /* ]]; then
  db_dump_abs="$db_dump_path"
else
  db_dump_abs="${env_file_dir}/${db_dump_path}"
fi

[[ -f "$db_dump_abs" ]] || fail "Dump-Datei nicht gefunden: $db_dump_abs"

if ! docker ps --format '{{.Names}}' | grep -Fxq "$db_container_name"; then
  fail "Container läuft nicht: $db_container_name"
fi

dump_size_bytes="$(wc -c < "$db_dump_abs" | tr -d ' ')"
dump_size_human="$(human_bytes "$dump_size_bytes")"
if [[ "$db_dump_abs" == *.gz ]]; then
  dump_kind="gzip-komprimiert (.gz)"
else
  dump_kind="plain SQL (.sql)"
fi

section "DB-IMPORT START"
log "INFO" "Env-Datei:               $env_file_abs"
log "INFO" "DB-Container:            $db_container_name"
log "INFO" "Ziel-Datenbank:          $mysql_database"
log "INFO" "App-User:                $mysql_user"
log "INFO" "MYSQL_PASSWORD:          $(mask_secret "$mysql_password")"
log "INFO" "MYSQL_ROOT_PASSWORD:     $(mask_secret "$mysql_root_password")"
log "INFO" "Dump-Datei:              $db_dump_abs"
log "INFO" "Dump-Typ:                $dump_kind"
log "INFO" "Dump-Größe:              $dump_size_human ($dump_size_bytes Bytes)"
log "INFO" "MySQL-Timeout:           ${mysql_wait_timeout}s"

sql_escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

section "PHASE 1/4 - MYSQL READINESS"
for ((i = 1; i <= mysql_wait_timeout; i++)); do
  if docker exec -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
    mysqladmin ping -h127.0.0.1 -uroot --silent >/dev/null 2>&1; then
    log "OK" "MySQL ist bereit (nach ${i}s)."
    break
  fi

  if (( i == 1 || i % 5 == 0 )); then
    log "INFO" "MySQL noch nicht bereit... Versuch ${i}/${mysql_wait_timeout}"
  fi

  if [[ "$i" -eq "$mysql_wait_timeout" ]]; then
    fail "MySQL wurde innerhalb von ${mysql_wait_timeout}s nicht bereit"
  fi

  sleep 1
done

root_password_sql="$(sql_escape_literal "$mysql_root_password")"
mysql_user_sql="$(sql_escape_literal "$mysql_user")"
mysql_password_sql="$(sql_escape_literal "$mysql_password")"

section "PHASE 2/4 - ROOT/USER/DB VORBEREITUNG"
log "INFO" "Setze Root-Accounts (localhost + %), App-User und Rechte..."
docker exec -i -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
  mysql -h127.0.0.1 -uroot <<SQL
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'%' IDENTIFIED BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

DROP DATABASE IF EXISTS \`${mysql_database}\`;
CREATE DATABASE \`${mysql_database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${mysql_user_sql}'@'localhost' IDENTIFIED BY '${mysql_password_sql}';
ALTER USER '${mysql_user_sql}'@'localhost' IDENTIFIED BY '${mysql_password_sql}';
CREATE USER IF NOT EXISTS '${mysql_user_sql}'@'%' IDENTIFIED BY '${mysql_password_sql}';
ALTER USER '${mysql_user_sql}'@'%' IDENTIFIED BY '${mysql_password_sql}';
GRANT ALL PRIVILEGES ON \`${mysql_database}\`.* TO '${mysql_user_sql}'@'localhost';
GRANT ALL PRIVILEGES ON \`${mysql_database}\`.* TO '${mysql_user_sql}'@'%';
FLUSH PRIVILEGES;
SQL
log "OK" "Benutzer, Datenbank und Rechte wurden vorbereitet."

log "INFO" "Prüfe Login mit App-User..."
docker exec -e MYSQL_PWD="$mysql_password" "$db_container_name" \
  mysql -h127.0.0.1 -u"$mysql_user" -D "$mysql_database" -Nse "SELECT 'app-user-login-ok';" >/dev/null
log "OK" "App-User kann sich an der Ziel-Datenbank anmelden."

section "PHASE 3/4 - DUMP IMPORT"
log "INFO" "Importiere Dump als Benutzer '$mysql_user'..."
if [[ "$db_dump_abs" == *.gz ]]; then
  command -v gzip >/dev/null 2>&1 || fail "gzip wurde nicht gefunden, aber Dump ist .gz"
  if command -v pv >/dev/null 2>&1; then
    log "INFO" "Fortschrittsanzeige aktiviert (pv)."
    gzip -dc "$db_dump_abs" | pv -ptebar -N "SQL-Stream" | docker exec -e MYSQL_PWD="$mysql_password" -i "$db_container_name" \
      mysql -h127.0.0.1 -u"$mysql_user" "$mysql_database"
  else
    log "INFO" "Hinweis: 'pv' nicht gefunden, Import läuft ohne Live-Fortschrittsbalken."
    gzip -dc "$db_dump_abs" | docker exec -e MYSQL_PWD="$mysql_password" -i "$db_container_name" \
      mysql -h127.0.0.1 -u"$mysql_user" "$mysql_database"
  fi
else
  if command -v pv >/dev/null 2>&1; then
    log "INFO" "Fortschrittsanzeige aktiviert (pv)."
    pv -ptebar "$db_dump_abs" | docker exec -e MYSQL_PWD="$mysql_password" -i "$db_container_name" \
      mysql -h127.0.0.1 -u"$mysql_user" "$mysql_database"
  else
    log "INFO" "Hinweis: 'pv' nicht gefunden, Import läuft ohne Live-Fortschrittsbalken."
    cat "$db_dump_abs" | docker exec -e MYSQL_PWD="$mysql_password" -i "$db_container_name" \
      mysql -h127.0.0.1 -u"$mysql_user" "$mysql_database"
  fi
fi
log "OK" "Dump-Import abgeschlossen."

section "PHASE 4/4 - IMPORT REPORT"
table_count_root="$(docker exec -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
  mysql -h127.0.0.1 -uroot -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${mysql_database}';")"
table_count_user="$(docker exec -e MYSQL_PWD="$mysql_password" "$db_container_name" \
  mysql -h127.0.0.1 -u"$mysql_user" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${mysql_database}';")"
db_size_mib="$(docker exec -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
  mysql -h127.0.0.1 -uroot -Nse "SELECT IFNULL(ROUND(SUM(data_length + index_length)/1024/1024,2),0) FROM information_schema.tables WHERE table_schema='${mysql_database}';")"
non_empty_tables="$(docker exec -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
  mysql -h127.0.0.1 -uroot -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${mysql_database}' AND (data_length > 0 OR index_length > 0 OR table_rows > 0);")"

log "INFO" "Tabellen (Root-Sicht):   $table_count_root"
log "INFO" "Tabellen (User-Sicht):   $table_count_user"
log "INFO" "Nicht-leere Tabellen:    $non_empty_tables"
log "INFO" "DB-Groesse (geschaetzt): ${db_size_mib} MiB"

if [[ "$table_count_root" -eq 0 ]]; then
  log "WARN" "Es wurden 0 Tabellen gefunden. Bitte Dump-Inhalt pruefen."
else
  log "OK" "Tabellen wurden in der Zieldatenbank gefunden."
fi

if [[ "$non_empty_tables" -eq 0 ]]; then
  log "WARN" "Keine nicht-leeren Tabellen erkannt. Der Dump kann schema-only sein."
else
  log "OK" "Es wurden Tabellen mit Inhalt erkannt."
fi

log "INFO" "Top 10 Tabellen nach Speicherbedarf (table_rows ist bei InnoDB geschaetzt):"
docker exec -e MYSQL_PWD="$mysql_root_password" "$db_container_name" \
  mysql -h127.0.0.1 -uroot --table -e "
SELECT
  table_name AS tabelle,
  table_rows AS geschaetzte_zeilen,
  ROUND((data_length + index_length)/1024/1024, 2) AS groesse_mib
FROM information_schema.tables
WHERE table_schema='${mysql_database}'
ORDER BY (data_length + index_length) DESC, table_name
LIMIT 10;
"

elapsed_seconds="$(( $(date +%s) - START_TS ))"
section "FERTIG"
log "OK" "Import erfolgreich abgeschlossen in ${elapsed_seconds}s."
log "INFO" "Pruefe oben den Report fuer Tabellenanzahl, Groesse und Top-Tabellen."
