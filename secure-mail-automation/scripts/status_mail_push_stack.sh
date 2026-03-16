#!/usr/bin/env bash
set -euo pipefail
ROOT="/data/.openclaw/workspace"
PID_DIR="$ROOT/data/mail-automation/pids"
URL_FILE="$ROOT/data/mail-automation/tunnel-url.txt"

show_proc() {
  local name="$1"
  local file="$2"
  if [[ -f "$file" ]]; then
    local pid
    pid=$(cat "$file" || true)
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$name: running (pid $pid)"
    else
      echo "$name: stale pid"
    fi
  else
    echo "$name: not running"
  fi
}

show_proc supervisor "$PID_DIR/supervisor.pid"
show_proc hook "$PID_DIR/hook.pid"
show_proc watch "$PID_DIR/watch.pid"
show_proc cloudflared "$PID_DIR/cloudflared.pid"

if [[ -f "$URL_FILE" ]]; then
  echo "tunnel_url: $(cat "$URL_FILE")"
else
  echo "tunnel_url: unknown"
fi
