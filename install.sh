#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SKILL_DIR="$REPO_ROOT/secure-mail-automation"

if [[ ! -d "$SRC_SKILL_DIR" ]]; then
  echo "[ERROR] Skill source directory not found: $SRC_SKILL_DIR"
  exit 1
fi

DEFAULT_BASE=""
if [[ -d "/data/.openclaw/workspace/skills" ]]; then
  DEFAULT_BASE="/data/.openclaw/workspace/skills"
elif [[ -d "$HOME/.openclaw/workspace/skills" ]]; then
  DEFAULT_BASE="$HOME/.openclaw/workspace/skills"
else
  DEFAULT_BASE="$HOME/.openclaw/workspace/skills"
fi

TARGET_DIR="${1:-$DEFAULT_BASE/secure-mail-automation}"
mkdir -p "$(dirname "$TARGET_DIR")"

if [[ -d "$TARGET_DIR" ]]; then
  BACKUP_DIR="${TARGET_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "[INFO] Existing installation detected. Backing up to: $BACKUP_DIR"
  mv "$TARGET_DIR" "$BACKUP_DIR"
fi

cp -a "$SRC_SKILL_DIR" "$TARGET_DIR"

# Ensure scripts are executable
if [[ -d "$TARGET_DIR/scripts" ]]; then
  chmod +x "$TARGET_DIR/scripts"/* || true
fi

# Optional config bootstrap
CONFIG_DIR=""
if [[ -d "/data/.openclaw/workspace/config" ]]; then
  CONFIG_DIR="/data/.openclaw/workspace/config"
elif [[ -d "$HOME/.openclaw/workspace/config" ]]; then
  CONFIG_DIR="$HOME/.openclaw/workspace/config"
fi

if [[ -n "$CONFIG_DIR" ]]; then
  mkdir -p "$CONFIG_DIR"
  CFG_TARGET="$CONFIG_DIR/mail-automation.json"
  if [[ ! -f "$CFG_TARGET" ]]; then
    cp "$TARGET_DIR/references/mail-automation.example.json" "$CFG_TARGET"
    echo "[INFO] Created config template: $CFG_TARGET"
  else
    echo "[INFO] Config already exists, not overwritten: $CFG_TARGET"
  fi
fi

echo ""
echo "[OK] secure-mail-automation installed to: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "1) Authenticate gog for your mailbox"
echo "2) Edit config (mailbox/policy/limits/templates):"
if [[ -n "$CONFIG_DIR" ]]; then
  echo "   $CONFIG_DIR/mail-automation.json"
else
  echo "   <your-workspace>/config/mail-automation.json"
fi
echo "3) Manual test run:"
echo "   python3 $TARGET_DIR/scripts/mail_auto_reply_v1.py"
echo "4) Push stack control:"
echo "   bash $TARGET_DIR/scripts/start_mail_push_stack.sh"
echo "   bash $TARGET_DIR/scripts/status_mail_push_stack.sh"
echo "   bash $TARGET_DIR/scripts/stop_mail_push_stack.sh"
