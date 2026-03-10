#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# import_db_dump_simple.sh
# =============================================================================
# Dieses Script importiert einen MySQL-Dump in einen laufenden Docker-Container.
#
# Hauptaufgaben:
# 1) .env laden und validieren
# 2) optionales Datei-Logging frueh aktivieren (MIGRATION_LOG_FILE)
# 3) MySQL-Readiness pruefen
# 4) Root/App-User sowie Zieldatenbank vorbereiten
# 5) Dump importieren (plain SQL oder gzip)
# 6) Import-Report erzeugen
#
# WICHTIG:
# - Die Ziel-Datenbank wird vor dem Import geloescht und neu angelegt.
# - Das Script ist absichtlich sehr gespraechig fuer Betrieb/Debugging.
# =============================================================================

# Scriptname und Startzeit fuer Reports/Usage.
SCRIPT_NAME="$(basename "$0")"
START_TS="$(date +%s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_BOOTSTRAP_LIB="${SCRIPT_DIR}/lib/env_bootstrap.sh"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"

# Laufzeitkontext fuer saubere Fehlerdiagnose.
CURRENT_PHASE="INITIALISIERUNG"
CURRENT_ACTION="Scriptstart"

# Ausgabe-Slot fuer SQL-Abfragen und finaler Log-Dateipfad.
LAST_QUERY_OUTPUT=""
log_file_abs=""

# Zentrale Logging-Helfer laden (wiederverwendbar fuer mehrere Scripte).
[[ -f "$LOGGING_LIB" ]] || { printf 'Logging-Helper nicht gefunden: %s\n' "$LOGGING_LIB" >&2; exit 1; }
# shellcheck disable=SC1090
source "$LOGGING_LIB"

# Hilfeausgabe fuer falsche Parameterverwendung.
usage() {
  cat <<EOF
Verwendung:
  $SCRIPT_NAME /pfad/zur/.env

Beispiel:
  $SCRIPT_NAME ../.env

Dieses vereinfachte Script:
1. Liest die .env ein
2. Wartet auf MySQL im Zielcontainer
3. Legt Root/User/DB inkl. Rechte an
4. Importiert den Dump als MYSQL_USER
5. Zeigt einen Import-Report zur Nachvollziehbarkeit

Wichtig:
- Die Zieldatenbank wird vor dem Import geloescht und neu erstellt.
- Dieses Script nutzt bewusst kein pv.
- Optionales Datei-Logging via Env:
  MIGRATION_LOG_FILE=logs/shared_script.log
  (relativer Pfad wird relativ zum Verzeichnis der .env aufgeloest)
EOF
}

# Konvertiert Byte-Werte in grobe, menschenlesbare Einheiten.
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

# Entfernt trailing CR aus genannten Variablen (Windows-CRLF in .env).
strip_crlf() {
  local var_name
  for var_name in "$@"; do
    printf -v "$var_name" '%s' "${!var_name%$'\r'}"
  done
}

# Escaped SQL-Literale minimal (einfaches Quote verdoppeln).
sql_escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# Gibt je nach Phase kompakte Debug-Hinweise aus.
print_debug_hints() {
  log "ERROR" "Debug-Hinweise fuer die aktuelle Phase:"
  case "$CURRENT_PHASE" in
    *"EINGABE UND KONFIGURATION"*)
      log "ERROR" "- Pruefe, ob alle benoetigten Env-Variablen gesetzt sind."
      log "ERROR" "- Pruefe Pfade in der .env, insbesondere DB_DUMP_PATH."
      ;;
    *"MYSQL READINESS"*)
      log "ERROR" "- Pruefe Container-Startup: docker logs <container> --tail 100"
      log "ERROR" "- Pruefe Credentials in der .env (MYSQL_ROOT_PASSWORD)."
      ;;
    *"ROOT/USER/DB VORBEREITUNG"*)
      log "ERROR" "- Typische Ursache: fehlende Root-Rechte oder Access denied."
      log "ERROR" "- Pruefe DB-Name auf erlaubte Zeichen [A-Za-z0-9_]."
      ;;
    *"DUMP IMPORT"*)
      log "ERROR" "- Pruefe, ob der Dump zur Ziel-DB/MySQL-Version passt."
      log "ERROR" "- Bei .gz: Dump auf Integritaet pruefen (gzip -t)."
      log "ERROR" "- Bei SQL-Fehlern auf erste fehlerhafte Statement-Zeile achten."
      ;;
    *"IMPORT REPORT"*)
      log "ERROR" "- Import koennte teilweise gelaufen sein, aber Metadatenabfrage scheitert."
      log "ERROR" "- Pruefe Berechtigungen des App-Users auf information_schema."
      ;;
    *)
      log "ERROR" "- Pruefe Logs oberhalb dieser Meldung auf die letzte erfolgreiche Aktion."
      ;;
  esac
}

# Kontrollierter Abbruch mit klarer Fehlermeldung.
fail() {
  log "ERROR" "$*"
  exit 1
}

# Globaler ERR-Handler fuer unerwartete Fehler.
# Liefert maximalen Kontext inkl. Phase/Aktion/Zeile/Befehl/Containerstatus.
on_error() {
  local exit_code=$?
  local line_no="${BASH_LINENO[0]:-unbekannt}"
  local raw_command="${BASH_COMMAND:-unbekannt}"
  local safe_command
  safe_command="$(sanitize_command_for_log "$raw_command")"

  # Verhindert rekursive ERR-Trigger waehrend der Diagnose selbst.
  set +e
  trap - ERR

  section "FEHLERDIAGNOSE"
  log "ERROR" "Das Script wurde unerwartet beendet."
  log "ERROR" "Exit-Code:               $exit_code"
  log "ERROR" "Phase:                   $CURRENT_PHASE"
  log "ERROR" "Aktion:                  $CURRENT_ACTION"
  log "ERROR" "Zeile:                   $line_no"
  log "ERROR" "Befehl:                  $safe_command"
  log "ERROR" "Env-Datei:               ${env_file_abs:-<nicht gesetzt>}"
  log "ERROR" "Dump-Datei:              ${db_dump_abs:-<nicht gesetzt>}"
  log "ERROR" "DB-Container:            ${db_container_name:-<nicht gesetzt>}"
  log "ERROR" "Ziel-Datenbank:          ${mysql_database:-<nicht gesetzt>}"
  log "ERROR" "Log-Datei:               ${log_file_abs:-<nicht gesetzt>}"

  # Zusatzdiagnose aus Docker, falls moeglich.
  if command -v docker >/dev/null 2>&1 && [[ -n "${db_container_name:-}" ]]; then
    if docker ps -a --format '{{.Names}}' | grep -Fxq "$db_container_name"; then
      local container_state
      container_state="$(docker inspect -f 'status={{.State.Status}}, running={{.State.Running}}, exit_code={{.State.ExitCode}}, restart_count={{.RestartCount}}' "$db_container_name" 2>/dev/null)"
      log "ERROR" "Container-Status:        ${container_state:-<nicht verfuegbar>}"
      log "ERROR" "Letzte 20 Zeilen Container-Logs:"
      docker logs --tail 20 "$db_container_name" 2>&1 | sed 's/^/[container] /'
    else
      log "ERROR" "Container wurde nicht gefunden (auch nicht gestoppt): $db_container_name"
    fi
  fi

  print_debug_hints
  exit "$exit_code"
}

# Erzeugt eine temporaere Datei fuer stderr-Capturing.
# Nutzt mktemp, faellt bei Bedarf auf /tmp zurueck.
new_tmp_file() {
  if command -v mktemp >/dev/null 2>&1; then
    mktemp
  else
    local fallback="/tmp/${SCRIPT_NAME}.$$.${RANDOM}.tmp"
    : > "$fallback"
    printf '%s\n' "$fallback"
  fi
}

# Fuehrt SQL aus stdin aus und faengt Fehlerausgaben sauber ab.
# Parameter:
# - role: root|app
# - action_label: lesbarer Aktionsname fuer Log und Fehlermeldungen
run_mysql_stdin() {
  local role="$1"
  local action_label="$2"
  local err_file
  err_file="$(new_tmp_file)"

  set_action "$action_label"
  if ! { mysql_exec "$role" --stdin; } 2>"$err_file"; then
    log "ERROR" "SQL-Schritt fehlgeschlagen: $action_label"
    if [[ -s "$err_file" ]]; then
      log "ERROR" "MySQL-Fehlerausgabe (letzte 30 Zeilen):"
      tail -n 30 "$err_file" | sed 's/^/[mysql] /'
    else
      log "ERROR" "Keine MySQL-Fehlerausgabe verfuegbar."
    fi
    rm -f "$err_file"
    fail "Abbruch waehrend SQL-Schritt: $action_label"
  fi

  rm -f "$err_file"
  log "OK" "SQL-Schritt abgeschlossen: $action_label"
}

# Fuehrt SQL-Abfrage aus, speichert das Ergebnis in LAST_QUERY_OUTPUT.
# Fehlerausgaben werden wie bei run_mysql_stdin sauber aufbereitet.
run_mysql_query_capture() {
  local role="$1"
  local action_label="$2"
  shift 2

  local err_file
  local output
  err_file="$(new_tmp_file)"

  set_action "$action_label"
  if ! output="$(mysql_exec "$role" "$@" 2>"$err_file")"; then
    log "ERROR" "SQL-Abfrage fehlgeschlagen: $action_label"
    if [[ -s "$err_file" ]]; then
      log "ERROR" "MySQL-Fehlerausgabe (letzte 30 Zeilen):"
      tail -n 30 "$err_file" | sed 's/^/[mysql] /'
    else
      log "ERROR" "Keine MySQL-Fehlerausgabe verfuegbar."
    fi
    rm -f "$err_file"
    fail "Abbruch waehrend SQL-Abfrage: $action_label"
  fi

  rm -f "$err_file"
  log "OK" "SQL-Abfrage abgeschlossen: $action_label"
  LAST_QUERY_OUTPUT="$output"
}

# Importiert den Dump mit detaillierter Fehlerdiagnose.
# mode=gzip:  gzip -dc dump.gz | mysql
# mode=plain: mysql < dump.sql
run_import_with_debug() {
  local mode="$1"
  local err_file
  local import_start
  local import_elapsed
  err_file="$(new_tmp_file)"

  set_action "Starte Dump-Import (Modus: $mode)"
  import_start="$(date +%s)"

  if [[ "$mode" == "gzip" ]]; then
    if ! { gzip -dc "$db_dump_abs" | mysql_exec app --stdin "$mysql_database"; } 2>"$err_file"; then
      log "ERROR" "Import fehlgeschlagen (gzip -> mysql)."
      if [[ -s "$err_file" ]]; then
        log "ERROR" "Import-Fehlerausgabe (letzte 30 Zeilen):"
        tail -n 30 "$err_file" | sed 's/^/[import] /'
      else
        log "ERROR" "Keine zusaetzliche Fehlerausgabe verfuegbar."
      fi
      rm -f "$err_file"
      fail "Dump-Import abgebrochen. Siehe Fehlerdetails oberhalb."
    fi
  else
    if ! { mysql_exec app --stdin "$mysql_database" < "$db_dump_abs"; } 2>"$err_file"; then
      log "ERROR" "Import fehlgeschlagen (sql-file -> mysql)."
      if [[ -s "$err_file" ]]; then
        log "ERROR" "Import-Fehlerausgabe (letzte 30 Zeilen):"
        tail -n 30 "$err_file" | sed 's/^/[import] /'
      else
        log "ERROR" "Keine zusaetzliche Fehlerausgabe verfuegbar."
      fi
      rm -f "$err_file"
      fail "Dump-Import abgebrochen. Siehe Fehlerdetails oberhalb."
    fi
  fi

  rm -f "$err_file"
  import_elapsed="$(( $(date +%s) - import_start ))"
  log "OK" "Dump-Import abgeschlossen in ${import_elapsed}s."
}

# Globales Error-Trapping aktivieren.
trap on_error ERR

# =============================================================================
# FRUEHINITIALISIERUNG
# =============================================================================
# Ziel: Logging in Datei so frueh wie moeglich aktivieren.
# Daher hier bereits:
# - .env ueber externes Env-Bootstrap-Helper-Script parsen/pruefen/laden
# - MIGRATION_LOG_FILE auslesen
# - tee-Logging aktivieren
# =============================================================================
CURRENT_PHASE="FRUEHINITIALISIERUNG"
CURRENT_ACTION="Parameter-/Env-Pruefung und Datei-Logging"

set_action "Parse/Pruefe/Lade Env-Datei ueber externen Helper"
[[ -f "$ENV_BOOTSTRAP_LIB" ]] || fail "Env-Bootstrap-Helper nicht gefunden: $ENV_BOOTSTRAP_LIB"
ENV_BOOTSTRAP_EXPECTED_ARGS=1
ENV_BOOTSTRAP_LAST_ERROR=""
env_bootstrap_rc=0
# shellcheck disable=SC1090
source "$ENV_BOOTSTRAP_LIB" || env_bootstrap_rc=$?
if (( env_bootstrap_rc != 0 )); then
  if (( env_bootstrap_rc == 64 )); then
    usage
  fi
  fail "${ENV_BOOTSTRAP_LAST_ERROR:-Env-Bootstrap fehlgeschlagen (Exit-Code: $env_bootstrap_rc)}"
fi
unset ENV_BOOTSTRAP_EXPECTED_ARGS
log "OK" "Env-Datei geparst/geprueft/geladen: $env_file_abs"

migration_log_file_path="${MIGRATION_LOG_FILE:-}"
strip_crlf migration_log_file_path
if ! init_file_logging "$migration_log_file_path" "$env_file_dir"; then
  fail "${LOGGING_LAST_ERROR:-Datei-Logging konnte nicht initialisiert werden.}"
fi

if [[ -n "$log_file_abs" ]]; then
  log "OK" "Datei-Logging frueh aktiviert: $log_file_abs"
else
  log "INFO" "Datei-Logging nicht konfiguriert (MIGRATION_LOG_FILE leer)."
fi

# =============================================================================
# PHASE 0/4 - EINGABE UND KONFIGURATION
# =============================================================================
set_phase "PHASE 0/4 - EINGABE UND KONFIGURATION"
set_action "Pruefe Anzahl uebergebener Parameter (bereits erfolgt)"
log "OK" "Parameterpruefung abgeschlossen."
set_action "Pruefe Existenz der Env-Datei (bereits erfolgt)"
log "OK" "Env-Datei gefunden: $env_file_abs"
set_action "Variablen aus der Env-Datei wurden bereits geladen"
log "OK" "Env-Datei wurde in der Fruehinitialisierung geladen."

# Variablen aus .env mit sinnvollen Defaults, wo moeglich.
db_container_name="${DB_CONTAINER_NAME:-db}"
mysql_database="${MYSQL_DATABASE:-nextcloud}"
mysql_user="${MYSQL_USER:-}"
mysql_password="${MYSQL_PASSWORD:-}"
mysql_root_password="${MYSQL_ROOT_PASSWORD:-}"
db_dump_path="${DB_DUMP_PATH:-}"
mysql_wait_timeout="${MYSQL_WAIT_TIMEOUT_SECONDS:-120}"
mysql_host_in_container="127.0.0.1"

# CRLF-Bereinigung fuer alle kritischen Werte.
set_action "Bereinige moegliche CRLF-Zeilenenden aus Env-Werten"
strip_crlf \
  db_container_name \
  mysql_database \
  mysql_user \
  mysql_password \
  mysql_root_password \
  db_dump_path \
  mysql_wait_timeout
log "OK" "CRLF-Bereinigung abgeschlossen."

# Basis-Tools pruefen.
set_action "Pruefe Tool-Abhaengigkeiten"
command -v docker >/dev/null 2>&1 || fail "docker wurde nicht gefunden. Bitte Docker installieren/verfuegbar machen."
command -v wc >/dev/null 2>&1 || fail "wc wurde nicht gefunden."
command -v sed >/dev/null 2>&1 || fail "sed wurde nicht gefunden."
log "OK" "Benoetigte Basis-Tools sind verfuegbar."

# Pflichtparameter und Werte validieren.
set_action "Validiere Pflichtparameter"
[[ -n "$mysql_root_password" ]] || fail "MYSQL_ROOT_PASSWORD ist leer."
[[ -n "$mysql_user" ]] || fail "MYSQL_USER ist leer."
[[ -n "$mysql_password" ]] || fail "MYSQL_PASSWORD ist leer."
[[ -n "$db_dump_path" ]] || fail "DB_DUMP_PATH ist leer."
[[ "$mysql_database" =~ ^[A-Za-z0-9_]+$ ]] || fail "MYSQL_DATABASE darf nur [A-Za-z0-9_] enthalten: '$mysql_database'"
[[ "$mysql_wait_timeout" =~ ^[0-9]+$ ]] || fail "MYSQL_WAIT_TIMEOUT_SECONDS muss numerisch sein: '$mysql_wait_timeout'"
log "OK" "Pflichtparameter sind valide."

# Dump-Pfad absolut aufloesen (absolut unveraendert, relativ zu .env).
set_action "Berechne absoluten Dump-Pfad"
case "$db_dump_path" in
  /*) db_dump_abs="$db_dump_path" ;;
  *) db_dump_abs="${env_file_dir}/${db_dump_path}" ;;
esac
log "INFO" "Dump-Pfad (absolut): $db_dump_abs"

# Sicherstellen, dass Dump existiert und lesbar ist.
set_action "Pruefe Dump-Datei auf Existenz und Lesbarkeit"
[[ -f "$db_dump_abs" ]] || fail "Dump-Datei nicht gefunden: $db_dump_abs"
[[ -r "$db_dump_abs" ]] || fail "Dump-Datei ist nicht lesbar: $db_dump_abs"
log "OK" "Dump-Datei ist vorhanden und lesbar."

# Sicherstellen, dass Zielcontainer laeuft.
set_action "Pruefe, ob der DB-Container aktuell laeuft"
if ! docker ps --format '{{.Names}}' | grep -Fxq "$db_container_name"; then
  fail "Container laeuft nicht: $db_container_name"
fi
log "OK" "Container laeuft: $db_container_name"

# Zentraler MySQL-Wrapper fuer alle DB-Operationen.
# Parameter:
# - role: root|app
# - optional --stdin: aktiviert docker -i fuer Stream/Heredoc/Pipe
# - rest: direkte mysql-Argumente
mysql_exec() {
  local role="$1"
  shift

  local with_stdin=0
  if [[ "${1:-}" == "--stdin" ]]; then
    with_stdin=1
    shift
  fi

  local mysql_cli_user mysql_pwd
  case "$role" in
    root)
      mysql_cli_user="root"
      mysql_pwd="$mysql_root_password"
      ;;
    app)
      mysql_cli_user="$mysql_user"
      mysql_pwd="$mysql_password"
      ;;
    *)
      fail "Unbekannte DB-Rolle: $role"
      ;;
  esac

  local docker_args=()
  (( with_stdin )) && docker_args+=("-i")

  docker exec "${docker_args[@]}" -e MYSQL_PWD="$mysql_pwd" "$db_container_name" \
    mysql --show-warnings -h"$mysql_host_in_container" -u"$mysql_cli_user" "$@"
}

# Dump-Groesse und Typ fuer Statusausgaben bestimmen.
set_action "Ermittle Dump-Dateigroesse und Typ"
dump_size_bytes="$(wc -c < "$db_dump_abs" | tr -d ' ')"
dump_size_human="$(human_bytes "$dump_size_bytes")"
if [[ "$db_dump_abs" == *.gz ]]; then
  dump_kind="gzip-komprimiert (.gz)"
  dump_mode="gzip"
else
  dump_kind="plain SQL (.sql)"
  dump_mode="plain"
fi

# Laufzeit-Kontext in kompakter Form loggen.
section "LAUFZEIT-KONTEXT"
log "INFO" "Script:                  $SCRIPT_NAME"
log "INFO" "Startzeit:               $(timestamp)"
log "INFO" "Arbeitsverzeichnis:      $(pwd)"
log "INFO" "Env-Datei:               $env_file_abs"
log "INFO" "DB-Container:            $db_container_name"
log "INFO" "Ziel-Datenbank:          $mysql_database"
log "INFO" "App-User:                $mysql_user"
log "INFO" "MYSQL_PASSWORD:          $(mask_secret "$mysql_password")"
log "INFO" "MYSQL_ROOT_PASSWORD:     $(mask_secret "$mysql_root_password")"
log "INFO" "Dump-Datei:              $db_dump_abs"
log "INFO" "Dump-Typ:                $dump_kind"
log "INFO" "Dump-Groesse:            $dump_size_human ($dump_size_bytes Bytes)"
log "INFO" "MySQL-Timeout:           ${mysql_wait_timeout}s"
log "INFO" "Hinweis:                 Dieses Script nutzt kein pv."
if [[ -n "$log_file_abs" ]]; then
  log "INFO" "Log-Datei:               $log_file_abs"
else
  log "INFO" "Log-Datei:               <nicht konfiguriert>"
fi

# =============================================================================
# PHASE 1/4 - MYSQL READINESS
# =============================================================================
# Wartet aktiv auf eine erfolgreiche Root-Verbindung.
set_phase "PHASE 1/4 - MYSQL READINESS"
set_action "Warte auf erreichbares MySQL im Zielcontainer"
wait_start_ts="$(date +%s)"
for ((attempt = 1; attempt <= mysql_wait_timeout; attempt++)); do
  log "INFO" "Readiness-Check ${attempt}/${mysql_wait_timeout}: pruefe 'SELECT 1'"
  if mysql_exec root -Nse "SELECT 1;" >/dev/null 2>&1; then
    waited_seconds="$(( $(date +%s) - wait_start_ts ))"
    log "OK" "MySQL ist bereit (nach ${waited_seconds}s)."
    break
  fi

  if (( attempt == mysql_wait_timeout )); then
    fail "MySQL wurde innerhalb von ${mysql_wait_timeout}s nicht bereit."
  fi
  sleep 1
done

# Credentials fuer SQL-Literale vorbereiten.
root_password_sql="$(sql_escape_literal "$mysql_root_password")"
mysql_user_sql="$(sql_escape_literal "$mysql_user")"
mysql_password_sql="$(sql_escape_literal "$mysql_password")"

# =============================================================================
# PHASE 2/4 - ROOT/USER/DB VORBEREITUNG
# =============================================================================
set_phase "PHASE 2/4 - ROOT/USER/DB VORBEREITUNG"

# Root-Accounts (localhost + %) konsistent setzen.
run_mysql_stdin root "Root-Accounts (localhost + %) erstellen/aktualisieren" <<SQL
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${root_password_sql}';
ALTER USER 'root'@'%' IDENTIFIED BY '${root_password_sql}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# Destruktiver DB-Reset vor dem Import.
run_mysql_stdin root "Zieldatenbank loeschen und neu anlegen (ACHTUNG: destruktiv)" <<SQL
DROP DATABASE IF EXISTS \`${mysql_database}\`;
CREATE DATABASE \`${mysql_database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL

# App-User erstellen/aktualisieren und Rechte vergeben.
run_mysql_stdin root "App-User erstellen/aktualisieren und Rechte setzen" <<SQL
CREATE USER IF NOT EXISTS '${mysql_user_sql}'@'localhost' IDENTIFIED BY '${mysql_password_sql}';
ALTER USER '${mysql_user_sql}'@'localhost' IDENTIFIED BY '${mysql_password_sql}';
CREATE USER IF NOT EXISTS '${mysql_user_sql}'@'%' IDENTIFIED BY '${mysql_password_sql}';
ALTER USER '${mysql_user_sql}'@'%' IDENTIFIED BY '${mysql_password_sql}';
GRANT ALL PRIVILEGES ON \`${mysql_database}\`.* TO '${mysql_user_sql}'@'localhost';
GRANT ALL PRIVILEGES ON \`${mysql_database}\`.* TO '${mysql_user_sql}'@'%';
FLUSH PRIVILEGES;
SQL

# Schneller Verbindungs-/Berechtigungstest fuer den App-User.
set_action "Pruefe Login mit App-User gegen Ziel-Datenbank"
mysql_exec app -D "$mysql_database" -Nse "SELECT 'app-user-login-ok';" >/dev/null
log "OK" "Login-Test erfolgreich: App-User kann auf die Ziel-Datenbank zugreifen."

# =============================================================================
# PHASE 3/4 - DUMP IMPORT
# =============================================================================
set_phase "PHASE 3/4 - DUMP IMPORT"
set_action "Bereite Importmodus vor"
if [[ "$dump_mode" == "gzip" ]]; then
  log "INFO" "Dump ist gzip-komprimiert. Pruefe Verfuegbarkeit von gzip."
  command -v gzip >/dev/null 2>&1 || fail "gzip wurde nicht gefunden, aber Dump ist .gz"

  # Integritaetscheck vor Start des eigentlichen Imports.
  set_action "Pruefe gzip-Integritaet des Dumps"
  if ! gzip -t "$db_dump_abs"; then
    fail "gzip-Integritaetspruefung fehlgeschlagen. Dump scheint defekt zu sein: $db_dump_abs"
  fi
  log "OK" "gzip-Integritaet erfolgreich geprueft."

  run_import_with_debug "gzip"
else
  log "INFO" "Dump ist plain SQL. Import via stdin-Redirect."
  run_import_with_debug "plain"
fi

# Post-Import-Schnellcheck (Tabellenzahl in User-Sicht).
run_mysql_query_capture app "Schneller Post-Import-Check: Tabellenzaehlung (App-User)" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${mysql_database}';"
post_import_table_count="$LAST_QUERY_OUTPUT"
log "INFO" "Post-Import-Check: App-User sieht aktuell ${post_import_table_count} Tabellen."

# =============================================================================
# PHASE 4/4 - IMPORT REPORT
# =============================================================================
set_phase "PHASE 4/4 - IMPORT REPORT"

# Kennzahlen aus information_schema ziehen.
run_mysql_query_capture root "Import-Report Kennzahlen laden (Root-Sicht)" -Nse "
SELECT
  COUNT(*) AS table_count_root,
  IFNULL(ROUND(SUM(data_length + index_length)/1024/1024,2),0) AS db_size_mib,
  IFNULL(SUM(CASE WHEN (data_length > 0 OR index_length > 0 OR table_rows > 0) THEN 1 ELSE 0 END),0) AS non_empty_tables
FROM information_schema.tables
WHERE table_schema='${mysql_database}';
"
report_root_row="$LAST_QUERY_OUTPUT"

[[ -n "$report_root_row" ]] || fail "Import-Report konnte nicht gelesen werden (leere Antwort von MySQL)."

# Tab-separierte SQL-Antwort auf drei Shell-Variablen mappen.
IFS=$'\t' read -r table_count_root db_size_mib non_empty_tables <<< "$report_root_row"
table_count_user="$post_import_table_count"

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

# Groesste Tabellen (geschaetzt) fuer schnelle Kapazitaetsanalyse.
set_action "Lade Top-10 Tabellen nach Speicherbedarf"
mysql_exec root --table -e "
SELECT
  table_name AS tabelle,
  table_rows AS geschaetzte_zeilen,
  ROUND((data_length + index_length)/1024/1024, 2) AS groesse_mib
FROM information_schema.tables
WHERE table_schema='${mysql_database}'
ORDER BY (data_length + index_length) DESC, table_name
LIMIT 10;
"
log "OK" "Top-10 Report ausgegeben."

# Abschliessende Gesamtdauer und Ergebnisstatus.
elapsed_seconds="$(( $(date +%s) - START_TS ))"
section "FERTIG"
log "OK" "Import erfolgreich abgeschlossen in ${elapsed_seconds}s."
log "INFO" "Alle Phasen erfolgreich durchlaufen: Readiness, Vorbereitung, Import, Report."
log "INFO" "Bei spaeteren Problemen bitte die Logs dieses Laufs inkl. FEHLERDIAGNOSE-Block aufheben."
