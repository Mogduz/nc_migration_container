#!/usr/bin/env bash
set -euo pipefail


set_vars() {
    wait_seconds=120
    interval_seconds=2
    current_dir="$(pwd)"
    env_file="$(make_path_absolut "$1")"
    compose_file="$current_dir/compose/stage1/docker-compose.yml"
}

check_env() {
    local env_file="$1"
    if [ -z "$env_file" ]; then
        echo "Fehler: Erster Parameter muss der Pfad zur Env-Datei sein." >&2
        return 1
    fi
}

make_path_absolut() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s\n' "$(cd "$current_dir/$(dirname "$path")" && pwd)/$(basename "$path")"
    fi
}

load_env() {
    local env_file="$1"
    set -a
    . "$env_file"
    set +a
}

import_scripts() {
    . "$current_dir/src/lib/logging.sh"
    . "$current_dir/src/lib/error.sh"
    . "$current_dir/src/lib/docker_compose.sh"
    . "$current_dir/src/lib/mysql.sh"
}

migrate_stage1() {

    local env_file="$1"
    local compose_file="$2"
    local timeout="${3:-$wait_seconds}"
    local failed=true
    if start_single_compose_container "$env_file" "$compose_file" "db"; then
        if docker_wait_for_state "$env_file" "$compose_file" "db" "healthy" "$timeout" "$interval_seconds"; then
            if configure_root_user "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD"; then
                if add_db_user "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_USER" "$MYSQL_PASSWORD"; then
                    if create_database "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"; then
                        if grant_db_user_privileges "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_USER" "$MYSQL_DATABASE"; then
                            if import_database_dump "$env_file" "$compose_file" "db" "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DATABASE" "$DB_DUMP_PATH"; then
                                failed=false
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    if [ "$failed" = "true" ]; then
        abort_with_error "$ERROR_MESSAGE" "$ERROR_FUNCTION"
    fi
}

startup() {

    set_vars "$1"
    check_env "$env_file"
    load_env "$env_file"
    import_scripts

}

startup "$1"
migrate_stage1 "$env_file" "$compose_file"
