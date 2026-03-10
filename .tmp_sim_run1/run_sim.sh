#!/usr/bin/env bash
set +e

chmod +x .tmp_sim_run1/mockbin/docker
PATH="$PWD/.tmp_sim_run1/mockbin:$PATH"

output="$(bash src/lib/stage1/01_configure_database_container.sh demo-db root supersecret app appsecret nextcloud 2>&1)"
rc=$?

printf 'EXIT_CODE=%s\n' "$rc"
if [ -z "$output" ]; then
  echo 'OUTPUT_EMPTY'
else
  echo 'OUTPUT_START'
  printf '%s\n' "$output"
  echo 'OUTPUT_END'
fi
