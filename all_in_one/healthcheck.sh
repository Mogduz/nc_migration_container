#!/usr/bin/env bash
set -euo pipefail

if curl -fsS -o /dev/null http://127.0.0.1/; then
  exit 0
fi

exit 1