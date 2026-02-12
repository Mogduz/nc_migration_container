#!/usr/bin/env bash
set -euo pipefail

log "Running 50-upgrade-map.sh"
log "Ensuring Nextcloud upgrade map allows ownCloud 10.16"
if [ -f /var/www/html/nextcloud/version.php ]; then
  python - <<'PY' || true
from pathlib import Path
path = Path("/var/www/html/nextcloud/version.php")
text = path.read_text()
old = """  'owncloud' =>
  array (
    '10.13' => true,
  ),
);"""
new = """  'owncloud' =>
  array (
    '10.16' => true,
  ),
);"""
if old in text:
    path.write_text(text.replace(old, new))
PY
fi
