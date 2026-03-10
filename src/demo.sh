#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${1:-}"

. "$script_dir/lib/logging.sh"
set -a
. "$env_file"
set +a

log_info "Env-Datei geladen: $env_file"
log_info "Umgebungsvariablen stehen fuer dieses Script zur Verfuegung."
