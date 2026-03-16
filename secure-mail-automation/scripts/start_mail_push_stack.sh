#!/usr/bin/env bash
set -euo pipefail
ROOT="/data/.openclaw/workspace"
LOG_DIR="$ROOT/logs/mail-automation"
PID_DIR="$ROOT/data/mail-automation/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

"$ROOT/scripts/stop_mail_push_stack.sh" || true
nohup bash "$ROOT/scripts/run_mail_push_supervisor.sh" >> "$LOG_DIR/supervisor.out.log" 2>&1 &
echo $! > "$PID_DIR/supervisor.pid"
echo "started supervisor pid $(cat "$PID_DIR/supervisor.pid")"
