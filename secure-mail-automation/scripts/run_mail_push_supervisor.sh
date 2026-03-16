#!/usr/bin/env bash
set -euo pipefail

ROOT="/data/.openclaw/workspace"
LOG_DIR="$ROOT/logs/mail-automation"
DATA_DIR="$ROOT/data/mail-automation"
PID_DIR="$DATA_DIR/pids"
mkdir -p "$LOG_DIR" "$DATA_DIR" "$PID_DIR"

SUP_LOG="$LOG_DIR/supervisor.log"
TOKEN="${MAIL_PUSH_TOKEN:-CHANGE_ME_MAIL_PUSH_TOKEN}"
PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
SUB_NAME="${PUBSUB_SUBSCRIPTION_NAME:-gmail-watch-push}"
ASSISTANT_EMAIL="${ASSISTANT_EMAIL:-assistant@example.com}"
GOG_KEYRING_PASSWORD_FILE="${GOG_KEYRING_PASSWORD_FILE:-$HOME/.config/gogcli/.keyring_pass}"

CLOUDFLARED_BIN="/home/linuxbrew/.linuxbrew/bin/cloudflared"
GOG_BIN="/home/linuxbrew/.linuxbrew/bin/gog"

hook_pid_file="$PID_DIR/hook.pid"
watch_pid_file="$PID_DIR/watch.pid"
cf_pid_file="$PID_DIR/cloudflared.pid"

log() {
  echo "$(date -Iseconds) $*" | tee -a "$SUP_LOG" >/dev/null
}

is_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

read_pid() {
  local f="$1"
  [[ -f "$f" ]] && cat "$f" || true
}

start_hook() {
  nohup python3 "$ROOT/scripts/gmail_push_hook.py" >> "$LOG_DIR/hook.out.log" 2>&1 &
  echo $! > "$hook_pid_file"
  log "hook started pid=$(cat "$hook_pid_file")"
}

start_watch() {
  nohup bash -lc "export GOG_KEYRING_PASSWORD=\"\$(cat \"$GOG_KEYRING_PASSWORD_FILE\")\"; exec $GOG_BIN gmail settings watch serve --account $ASSISTANT_EMAIL --bind 127.0.0.1 --port 8788 --path /gmail-pubsub --token $TOKEN --hook-url http://127.0.0.1:8790/hook --fetch-delay 2s --save-hook" >> "$LOG_DIR/watch-serve.out.log" 2>&1 &
  echo $! > "$watch_pid_file"
  log "watch started pid=$(cat "$watch_pid_file")"
}

start_cloudflared_and_set_subscription() {
  : > "$LOG_DIR/cloudflared.log"
  nohup "$CLOUDFLARED_BIN" tunnel --url http://127.0.0.1:8788 >> "$LOG_DIR/cloudflared.log" 2>&1 &
  local cpid=$!
  echo "$cpid" > "$cf_pid_file"
  log "cloudflared started pid=$cpid"

  local tunnel_url=""
  for _ in $(seq 1 60); do
    if ! is_alive "$cpid"; then
      log "cloudflared died before URL extraction"
      return 1
    fi
    tunnel_url=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" | tail -n1 || true)
    [[ -n "$tunnel_url" ]] && break
    sleep 1
  done

  if [[ -z "$tunnel_url" ]]; then
    log "cloudflared URL not found"
    return 1
  fi

  echo "$tunnel_url" > "$DATA_DIR/tunnel-url.txt"
  if gcloud pubsub subscriptions update "$SUB_NAME" --project "$PROJECT_ID" --push-endpoint="${tunnel_url}/gmail-pubsub?token=${TOKEN}" >> "$SUP_LOG" 2>&1; then
    log "subscription updated push_endpoint=${tunnel_url}/gmail-pubsub?token=***"
  else
    log "subscription update FAILED"
  fi
}

stop_pid_file() {
  local f="$1"
  local p
  p=$(read_pid "$f")
  if is_alive "$p"; then
    kill "$p" 2>/dev/null || true
    sleep 1
    is_alive "$p" && kill -9 "$p" 2>/dev/null || true
  fi
  rm -f "$f"
}

cleanup_children() {
  stop_pid_file "$hook_pid_file"
  stop_pid_file "$watch_pid_file"
  stop_pid_file "$cf_pid_file"
  pkill -f '/data/.openclaw/workspace/scripts/gmail_push_hook.py' 2>/dev/null || true
  pkill -f 'gog gmail settings watch serve --account' 2>/dev/null || true
  pkill -f 'cloudflared tunnel --url http://127.0.0.1:8788' 2>/dev/null || true
}

trap 'log "supervisor stopping"; cleanup_children; exit 0' INT TERM

log "supervisor started"

# clean stale first
cleanup_children

while true; do
  hp=$(read_pid "$hook_pid_file")
  is_alive "$hp" || start_hook

  wp=$(read_pid "$watch_pid_file")
  is_alive "$wp" || start_watch

  cp=$(read_pid "$cf_pid_file")
  if ! is_alive "$cp"; then
    start_cloudflared_and_set_subscription || true
  fi

  sleep 8
done
