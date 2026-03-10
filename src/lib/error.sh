#!/usr/bin/env bash

abort_with_error() {
  local message="$1"
  local failed_function="${2:-}"

  if [ -z "$message" ]; then
    message="Unbekannter Fehler."
  fi

  if [ -z "$failed_function" ]; then
    failed_function="unbekannte funktion"
  fi

  echo "Fehler in Funktion '$failed_function': $message" >&2
  exit 1
}
