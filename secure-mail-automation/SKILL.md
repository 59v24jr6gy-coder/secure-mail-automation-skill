---
name: secure-mail-automation
description: Hardened Gmail auto-reply and push-processing workflow with prompt-injection defense, phishing URL checks, forwarding guards, rate limits, fallback templates, and local push supervisor. Use when setting up secure inbound email automation, safe auto-replies, and event-driven Gmail processing via Pub/Sub + local webhook.
---

# Secure Mail Automation

## Configure

1. Create config file from template:
   - `references/mail-automation.example.json` -> runtime config path
2. Ensure `gog` is authenticated for Gmail.
3. Ensure ClawDefender scripts are available if URL/prompt checks are enabled.

## Run (manual)

```bash
python3 scripts/mail_auto_reply_v1.py
```

## Run (push-driven)

Use supervisor scripts:

```bash
bash scripts/start_mail_push_stack.sh
bash scripts/status_mail_push_stack.sh
bash scripts/stop_mail_push_stack.sh
```

## Safety Rules Implemented

- Reply only to directly addressed mailbox mail (To/Cc policy)
- Block auto-reply for forwarded/no-reply/main-account mail
- Optional fallback-only behavior for attachments
- Prompt-injection scan before content handling
- URL risk check before link handling
- Per-sender/per-thread/global rate limits + cooldown
- Configurable fallback template and kill switch
- Audit log + state tracking for dedupe and policy decisions

## References

- `references/mail-automation.example.json`: config schema/template
