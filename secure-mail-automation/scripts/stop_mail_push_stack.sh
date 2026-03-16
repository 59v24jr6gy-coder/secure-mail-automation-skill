#!/usr/bin/env bash
set -euo pipefail
ROOT="/data/.openclaw/workspace"
PID_DIR="$ROOT/data/mail-automation/pids"

stop_pid_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local pid
  pid=$(cat "$f" || true)
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$f"
}

# stop supervisor first (it handles child cleanup)
stop_pid_file "$PID_DIR/supervisor.pid"

# hard cleanup in case stale children remain
for f in cloudflared.pid watch.pid hook.pid; do
  stop_pid_file "$PID_DIR/$f"
done
pkill -f '/data/.openclaw/workspace/scripts/gmail_push_hook.py' 2>/dev/null || true
pkill -f 'gog gmail settings watch serve --account david.uhlig.assistent.neo@gmail.com' 2>/dev/null || true
pkill -f 'cloudflared tunnel --url http://127.0.0.1:8788' 2>/dev/null || true

echo "stopped"
