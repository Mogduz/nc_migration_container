#!/usr/bin/env bash
set -euo pipefail

repo="$(pwd)"
sim_dir="$repo/.tmp_wsl_sim"
mock_dir="$sim_dir/mockbin"

mkdir -p "$mock_dir"
rm -f "$sim_dir/terminal.out" "$sim_dir/run.log" "$sim_dir/exit.code"
rm -f "$mock_dir/docker"

cat > "$mock_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  inspect)
    [ "${1:-}" = "--format" ] || exit 1
    fmt="${2:-}"
    container="${3:-}"
    [ "$container" = "demo-db" ] || exit 1
    case "$fmt" in
      '{{.State.Running}}')
        echo true
        ;;
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}')
        echo healthy
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  exec)
    cat >/dev/null || true
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$mock_dir/docker"

LOG_FILE="$sim_dir/run.log" \
PATH="$mock_dir:$PATH" \
bash "$repo/src/lib/stage1/01_configure_database_container.sh" \
  demo-db rootpass dbuser dbpass mydb \
  > "$sim_dir/terminal.out" 2>&1

echo $? > "$sim_dir/exit.code"
