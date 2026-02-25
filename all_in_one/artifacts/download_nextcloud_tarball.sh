#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NC_VERSION="25.0.13"

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi

TARBALL="nextcloud-${NC_VERSION}.tar.bz2"
URL="https://download.nextcloud.com/server/releases/${TARBALL}"
TARGET="${SCRIPT_DIR}/${TARBALL}"

echo "Downloading ${URL}"
curl -fSL "${URL}" -o "${TARGET}"
echo "Saved to ${TARGET}"
