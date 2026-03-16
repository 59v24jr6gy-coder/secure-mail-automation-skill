# Security Policy

## Reporting a Vulnerability

Please do **not** open public issues for sensitive vulnerabilities.

Report privately with:
- Affected version/commit
- Reproduction steps
- Impact assessment
- Suggested mitigation (optional)

## Security Scope

This repository focuses on reducing risk in automated email handling:
- prompt-injection defenses
- phishing/URL risk checks
- guarded auto-reply policies
- rate limits and cooldowns
- audit logging

## Operational Guidance

- Keep secrets out of repository files.
- Use environment variables for tokens/project IDs.
- Keep principle-of-least-privilege for IAM and mailbox scopes.
- Review logs for anomalies and tune policies conservatively.
