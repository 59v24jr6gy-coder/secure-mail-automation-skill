# secure-mail-automation-skill

Hardened, reusable AgentSkill for Gmail automation with strong safety guardrails.

This repository provides a **secure email automation stack** that can:

- auto-reply to inbound email under strict policy rules,
- defend against prompt-injection attempts in email text,
- check links for phishing/SSRF patterns before processing,
- enforce reply limits to prevent abuse/token drain,
- run in push mode (Gmail → Pub/Sub → local hook),
- keep decision logs for auditability.

---

## What this skill does

### 1) Secure auto-reply pipeline
The core runner (`mail_auto_reply_v1.py`) fetches inbox threads and decides per message:

- **allow** (normal auto reply)
- **fallback** (safe default response)
- **block** (no auto reply)

Decision is based on policy, safety checks, and rate limits.

### 2) Prompt-injection defense
Incoming untrusted email content is checked before reply decisions.

- Uses ClawDefender prompt checks (when enabled)
- Marks risky content as fallback/block instead of free auto-response

### 3) Phishing/link defense
URLs extracted from email text are validated via ClawDefender URL checks.

- Suspicious links trigger fallback behavior
- Prevents blind trust in malicious URLs (including SSRF/exfil patterns)

### 4) Sender/addressing policy controls
Built-in controls include:

- reply only when directly addressed mailbox is in To/Cc,
- block forwarded emails,
- block no-reply senders,
- optionally block mails from owner/main account.

### 5) Cost and abuse limits
Configurable limits protect against spam loops and token burn:

- max replies per sender/day,
- max replies per thread,
- global replies/day,
- cooldown per sender.

### 6) Push-driven operation + local supervisor
Included scripts can run a local push stack:

- local Gmail push receiver,
- `gog gmail settings watch serve` listener,
- cloudflared tunnel + Pub/Sub endpoint update,
- supervisor loop with restart behavior.

### 7) Audit trail
All decisions are written to JSONL audit logs for debugging and compliance review.

---

## Repository structure

```text
secure-mail-automation/
  SKILL.md
  references/
    mail-automation.example.json
  scripts/
    mail_auto_reply_v1.py
    gmail_push_hook.py
    run_mail_push_supervisor.sh
    start_mail_push_stack.sh
    stop_mail_push_stack.sh
    status_mail_push_stack.sh
    start_cloudflared_pubsub.sh
install.sh
```

---

## Prerequisites

- Linux/macOS shell
- Python 3.11+
- `gog` CLI authenticated for Gmail account
- `gcloud` CLI (for Pub/Sub endpoint updates)
- `cloudflared` (for local tunnel push mode)
- ClawDefender scripts available if URL/prompt checks are enabled

Optional but recommended:
- dedicated Gmail account for automation
- restricted API credentials and minimal IAM scope

---

## Installation

Use the included installer:

```bash
bash install.sh
```

Environment setup (recommended):

```bash
cp .env.example .env
# edit .env with your values
```

You can export variables before starting the push stack:

```bash
set -a
source .env
set +a
```

What it does:

1. Creates target skill directory in OpenClaw workspace
2. Copies `secure-mail-automation/` into workspace skills
3. Makes scripts executable
4. Creates config from example if missing
5. Prints next-step commands

By default it installs to:

- `/data/.openclaw/workspace/skills/secure-mail-automation` (if present), otherwise
- `~/.openclaw/workspace/skills/secure-mail-automation`

Custom install path:

```bash
bash install.sh /custom/path/skills/secure-mail-automation
```

---

## Configuration

Start from:

- `secure-mail-automation/references/mail-automation.example.json`

Key options:

- `enabled`: kill-switch for automation
- `account`: assistant mailbox
- `main_account`: owner mailbox to exclude from auto-reply
- `query`: inbox fetch query
- `office_hours`: active reply time window
- `limits`: sender/thread/global/cooldown limits
- `policy`: forwarding/no-reply/injection/url/attachment behavior
- `reply.normal_auto_reply_template`
- `reply.fallback_reply_template`

---

## Usage

### Manual run

```bash
python3 secure-mail-automation/scripts/mail_auto_reply_v1.py
```

### Push stack (local)

```bash
bash secure-mail-automation/scripts/start_mail_push_stack.sh
bash secure-mail-automation/scripts/status_mail_push_stack.sh
bash secure-mail-automation/scripts/stop_mail_push_stack.sh
```

---

## Security guidance (important)

1. Treat all inbound email content as untrusted data.
2. Never auto-share secrets (tokens, config IDs, credentials).
3. Keep fallback template conservative for suspicious/uncertain cases.
4. Keep limits enabled to reduce abuse and token exhaustion.
5. Review `audit.jsonl` periodically for false positives/negatives.
6. Prefer direct-addressed-only replies; block forwards by default.
7. For attachments, start with fallback/block unless explicit safe parsing is required.
8. Rotate credentials and keep IAM minimal.

---

## Logs and state

Default paths (configurable):

- state: `data/mail-automation/state.json`
- audit: `logs/mail-automation/audit.jsonl`

These files are required for deduplication and rate-limit enforcement.

---

## Threat model and limitations

### In scope
- Prompt-injection text patterns in inbound emails
- Suspicious URL patterns (including SSRF/exfil indicators)
- Over-reply loops and token burn via sender/thread/global limits
- Unsafe auto-reply contexts (forwarded/no-reply/non-directly-addressed mail)

### Out of scope (v1)
- Full malware scanning/sandbox detonation of attachments
- Full anti-spoofing pipeline beyond basic sender/header policy checks
- Enterprise DLP/IR workflows and SIEM-native integrations

### Operational limits
- This is a **policy-and-guardrail layer**, not a complete mail security gateway.
- Keep conservative defaults for unknown senders and attachment-heavy workflows.

## Security files in this repo

- `SECURITY.md` — vulnerability reporting and security operations guidance
- `LICENSE` — MIT license
- `.env.example` — placeholder-based environment configuration
- `scripts/smoke-test.sh` — preflight validation of dependencies and scripts

## Notes

- This skill is intentionally conservative by default.
- Tune policy and fallback wording to your workflow.
- If your environment does not support systemd user services, use the provided supervisor scripts.
