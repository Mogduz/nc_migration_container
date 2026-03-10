#!/usr/bin/env bash
set -euo pipefail


set_vars() {
    timeout=120
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

print_loaded_env() {
    local env_file="$1"
    local line
    local key
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi
        line="${line#export }"
        key="${line%%=*}"
        key="${key%"${key##*[![:space:]]}"}"
        if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf '%s=%s\n' "$key" "${!key-}"
        fi
    done < "$env_file"
}

import_scripts() {
    . "$current_dir/src/lib/logging.sh"
    . "$current_dir/src/lib/error.sh"
    . "$current_dir/src/lib/docker_compose.sh"
    . "$current_dir/src/lib/mysql.sh"
}

preflight_migration_stage1() {
    if create_docker_network "$DOCKER_NETWORK_NAME"; then
        return 0
    fi
    return 1
}

prepare_database_stage1() {
    local env_file="$1"
    local compose_file="$2"
    local timeout="${3:-$timeout}"
    if start_single_compose_container "$env_file" "$compose_file" "db"; then
        if docker_wait_for_state "$env_file" "$compose_file" "db" "healthy" "$timeout" "$interval_seconds"; then
            if configure_root_user "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD"; then
                if add_db_user "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_USER" "$MYSQL_PASSWORD"; then
                    if create_database "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"; then
                        if grant_db_user_privileges "$env_file" "$compose_file" "db" "$MYSQL_ROOT_PASSWORD" "$MYSQL_USER" "$MYSQL_DATABASE"; then
                            if import_database_dump "$env_file" "$compose_file" "db" "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DATABASE" "$DB_DUMP_PATH"; then
                                if stop_compose "$env_file" "$compose_file"; then
                                    return 0
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    return 1
}

prepare_migration_stage1() {
    local env_file="$1"
    local compose_file="$2"
    if start_compose "$env_file" "$compose_file"; then
        if docker_wait_for_state "$env_file" "$compose_file" "db" "healthy" "$timeout" "$interval_seconds"; then
            if docker_wait_for_log_string "$env_file" "$compose_file" "nextcloud" "apache2 -D FOREGROUND"; then
                if copy_file_to_container "$env_file" "$compose_file" "nextcloud" "$current_dir/compose/stage1/files/version.php" "/var/www/html/version.php" "www-data" "www-data"; then
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

migrate_stage1() {
    local failed=true
    if preflight_migration_stage1; then 
        if prepare_database_stage1 "$env_file" "$compose_file"; then
            if prepare_migration_stage1 "$env_file" "$compose_file"; then
                if run_container_command_as_user "$env_file" "$compose_file" "nextcloud" "www-data" "php occ upgrade"; then
                    failed=false
                fi
            fi
        fi
    fi
    
    if [ "$failed" = "true" ]; then
        abort_with_error "$ERROR_MESSAGE" "$ERROR_FUNCTION"
    else
        echo "Done"
    fi
}

startup() {

    set_vars "$1"
    check_env "$env_file"
    load_env "$env_file"
    #print_loaded_env "$env_file"
    import_scripts

}

startup "$1"
migrate_stage1 "$env_file" "$compose_file"
