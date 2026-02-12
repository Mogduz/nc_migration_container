#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[migrate] $*"
}

OCC="php /var/www/html/nextcloud/occ"
OCC_NOINT="$OCC --no-interaction"

log "Starting migration steps"

log "Running occ upgrade (non-interactive)"
$OCC_NOINT upgrade

log "Disabling maintenance mode"
$OCC_NOINT maintenance:mode --off

log "Running database maintenance commands (non-interactive)"
$OCC_NOINT db:convert-filecache-bigint
$OCC_NOINT db:add-missing-columns
$OCC_NOINT db:add-missing-indices
$OCC_NOINT db:add-missing-primary-keys

log "Updating apps (non-interactive)"
$OCC_NOINT app:update --all

log "Migration finished"
log "Current status:"
$OCC_NOINT status || true
