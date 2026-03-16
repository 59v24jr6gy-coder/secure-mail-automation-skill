#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT/secure-mail-automation"

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

[[ -d "$SKILL_DIR" ]] || fail "Missing skill directory: $SKILL_DIR"
[[ -f "$SKILL_DIR/SKILL.md" ]] || fail "Missing SKILL.md"
[[ -f "$SKILL_DIR/references/mail-automation.example.json" ]] || fail "Missing example config"

for f in mail_auto_reply_v1.py gmail_push_hook.py run_mail_push_supervisor.sh start_mail_push_stack.sh stop_mail_push_stack.sh status_mail_push_stack.sh start_cloudflared_pubsub.sh; do
  [[ -f "$SKILL_DIR/scripts/$f" ]] || fail "Missing script: $f"
done
ok "Skill files present"

command -v python3 >/dev/null 2>&1 || fail "python3 not found"
ok "python3 found"

if command -v gog >/dev/null 2>&1; then ok "gog found"; else warn "gog not found"; fi
if command -v gcloud >/dev/null 2>&1; then ok "gcloud found"; else warn "gcloud not found"; fi
if command -v cloudflared >/dev/null 2>&1; then ok "cloudflared found"; else warn "cloudflared not found"; fi

python3 -m py_compile "$SKILL_DIR/scripts/mail_auto_reply_v1.py" "$SKILL_DIR/scripts/gmail_push_hook.py"
ok "Python scripts compile"

echo "Smoke test completed"
