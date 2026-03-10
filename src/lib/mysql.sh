#!/usr/bin/env bash
set -euo pipefail

configure_root_user() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local root_password="$4"
  local root_password_sql

  ERROR_FUNCTION="configure_root_user"
  ERROR_MESSAGE=""
  root_password_sql="$(printf '%s' "$root_password" | sed "s/'/''/g")"

  if docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$root_password" "$service_name" mysql -h127.0.0.1 -uroot <<SQL
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'%' IDENTIFIED BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
  then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="Root-User 'root' konnte fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' nicht angelegt oder aktualisiert werden."
  return 1
}

add_db_user() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local root_password="$4"
  local db_user="$5"
  local db_user_password="$6"
  local db_user_sql
  local db_user_password_sql

  ERROR_FUNCTION="add_db_user"
  ERROR_MESSAGE=""
  db_user_sql="$(printf '%s' "$db_user" | sed "s/'/''/g")"
  db_user_password_sql="$(printf '%s' "$db_user_password" | sed "s/'/''/g")"

  if docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$root_password" "$service_name" mysql -h127.0.0.1 -uroot <<SQL
CREATE USER IF NOT EXISTS '${db_user_sql}'@'localhost' IDENTIFIED BY '${db_user_password_sql}';
ALTER USER '${db_user_sql}'@'localhost' IDENTIFIED BY '${db_user_password_sql}';
CREATE USER IF NOT EXISTS '${db_user_sql}'@'%' IDENTIFIED BY '${db_user_password_sql}';
ALTER USER '${db_user_sql}'@'%' IDENTIFIED BY '${db_user_password_sql}';
FLUSH PRIVILEGES;
SQL
  then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="User '$db_user' konnte fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' nicht angelegt oder aktualisiert werden."
  return 1
}

create_database() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local root_password="$4"
  local database_name="$5"
  local database_name_escaped

  ERROR_FUNCTION="create_database"
  ERROR_MESSAGE=""

  database_name_escaped="$(printf '%s' "$database_name" | sed 's/`/``/g')"

  if docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$root_password" "$service_name" mysql -h127.0.0.1 -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${database_name_escaped}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL
  then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="Datenbank '$database_name' konnte fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' nicht angelegt werden."
  return 1
}

grant_db_user_privileges() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local root_password="$4"
  local db_user="$5"
  local database_name="$6"
  local db_user_sql
  local database_name_escaped

  ERROR_FUNCTION="grant_db_user_privileges"
  ERROR_MESSAGE=""
  db_user_sql="$(printf '%s' "$db_user" | sed "s/'/''/g")"
  database_name_escaped="$(printf '%s' "$database_name" | sed 's/`/``/g')"

  if docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$root_password" "$service_name" mysql -h127.0.0.1 -uroot <<SQL
GRANT ALL PRIVILEGES ON \`${database_name_escaped}\`.* TO '${db_user_sql}'@'localhost';
GRANT ALL PRIVILEGES ON \`${database_name_escaped}\`.* TO '${db_user_sql}'@'%';
FLUSH PRIVILEGES;
SQL
  then
    ERROR_MESSAGE=""
    return 0
  fi

  ERROR_MESSAGE="Berechtigungen fuer User '$db_user' auf Datenbank '$database_name' konnten fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' nicht gesetzt werden."
  return 1
}

import_database_dump() {
  local env_file="$1"
  local compose_file="$2"
  local service_name="$3"
  local db_user="$4"
  local db_user_password="$5"
  local database_name="$6"
  local dump_file_path="$7"
  local import_mode="plain"
  local database_name_sql
  local object_count

  ERROR_FUNCTION="import_database_dump"
  ERROR_MESSAGE=""
  database_name_sql="$(printf '%s' "$database_name" | sed "s/'/''/g")"

  if [[ "$dump_file_path" == *.gz ]]; then
    import_mode="gzip"
  fi

  if [ "$import_mode" = "gzip" ]; then
    if ! docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$db_user_password" "$service_name" sh -lc 'gzip -dc "$1" | mysql -h127.0.0.1 -u"$2" "$3"' -- "$dump_file_path" "$db_user" "$database_name"; then
      ERROR_MESSAGE="Gzip-Dump '$dump_file_path' konnte nicht in Datenbank '$database_name' fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' importiert werden."
      return 1
    fi
  else
    if ! docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$db_user_password" "$service_name" sh -lc 'mysql -h127.0.0.1 -u"$2" "$3" < "$1"' -- "$dump_file_path" "$db_user" "$database_name"; then
      ERROR_MESSAGE="SQL-Dump '$dump_file_path' konnte nicht in Datenbank '$database_name' fuer Service '$service_name' mit Compose-Datei '$compose_file' und Env-Datei '$env_file' importiert werden."
      return 1
    fi
  fi

  object_count="$(docker compose --env-file "$env_file" -f "$compose_file" exec -T -e MYSQL_PWD="$db_user_password" "$service_name" mysql -h127.0.0.1 -u"$db_user" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${database_name_sql}';" 2>/dev/null || true)"
  if [[ ! "$object_count" =~ ^[0-9]+$ ]]; then
    ERROR_MESSAGE="Import-Pruefung fehlgeschlagen: Tabellenanzahl in Datenbank '$database_name' konnte nicht gelesen werden."
    return 1
  fi

  if [ "$object_count" -eq 0 ]; then
    ERROR_MESSAGE="Import-Pruefung fehlgeschlagen: Datenbank '$database_name' ist nach dem Import leer."
    return 1
  fi

  ERROR_MESSAGE=""
  return 0
}
