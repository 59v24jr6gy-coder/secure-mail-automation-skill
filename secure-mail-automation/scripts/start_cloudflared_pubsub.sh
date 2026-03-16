#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
SUB_NAME="${PUBSUB_SUBSCRIPTION_NAME:-gmail-watch-push}"
TOKEN="${MAIL_PUSH_TOKEN:-CHANGE_ME_MAIL_PUSH_TOKEN}"
LOG_FILE="/data/.openclaw/workspace/logs/mail-automation/cloudflared.log"
URL_FILE="/data/.openclaw/workspace/data/mail-automation/tunnel-url.txt"

mkdir -p /data/.openclaw/workspace/logs/mail-automation /data/.openclaw/workspace/data/mail-automation
: > "$LOG_FILE"

/home/linuxbrew/.linuxbrew/bin/cloudflared tunnel --url http://127.0.0.1:8788 >> "$LOG_FILE" 2>&1 &
CF_PID=$!

cleanup() {
  kill "$CF_PID" 2>/dev/null || true
}
trap cleanup EXIT

TUNNEL_URL=""
for _ in $(seq 1 60); do
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "cloudflared exited unexpectedly" >> "$LOG_FILE"
    exit 1
  fi
  TUNNEL_URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_FILE" | tail -n1 || true)
  if [[ -n "$TUNNEL_URL" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$TUNNEL_URL" ]]; then
  echo "failed to get tunnel URL" >> "$LOG_FILE"
  exit 1
fi

echo "$TUNNEL_URL" > "$URL_FILE"

gcloud pubsub subscriptions update "$SUB_NAME" \
  --project "$PROJECT_ID" \
  --push-endpoint="${TUNNEL_URL}/gmail-pubsub?token=${TOKEN}" >> "$LOG_FILE" 2>&1

wait "$CF_PID"
