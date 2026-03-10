timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  local level="$1"
  shift
  local message="[$(timestamp)] [$level] $*"
  if [ "$level" = "ERROR" ]; then
    printf '%s\n' "$message" >&2
  else
    printf '%s\n' "$message"
  fi
  if [ -n "${LOG_FILE:-}" ]; then
    printf '%s\n' "$message" >> "$LOG_FILE"
  fi
}

log_info() {
  log INFO "$@"
}

log_warn() {
  log WARN "$@"
}

log_error() {
  log ERROR "$@"
}
