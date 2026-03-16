#!/usr/bin/env python3
import base64
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path('/data/.openclaw/workspace')
CONFIG_PATH = ROOT / 'config' / 'mail-automation.json'


def load_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def ensure_parent(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)


def run(cmd, env=None, input_text=None):
    p = subprocess.run(cmd, text=True, input=input_text, capture_output=True, env=env)
    return p.returncode, p.stdout, p.stderr


def b64url_decode(data):
    if not data:
        return ''
    padding = '=' * (-len(data) % 4)
    try:
        return base64.urlsafe_b64decode(data + padding).decode('utf-8', errors='replace')
    except Exception:
        return ''


def headers_to_map(headers):
    out = {}
    for h in headers or []:
        name = (h.get('name') or '').lower()
        value = h.get('value') or ''
        out[name] = value
    return out


def extract_plain_text(payload):
    if not payload:
        return ''
    mime = payload.get('mimeType', '')
    body = payload.get('body', {})
    if mime.startswith('text/plain') and body.get('data'):
        return b64url_decode(body.get('data'))
    for part in payload.get('parts', []) or []:
        t = extract_plain_text(part)
        if t:
            return t
    return ''


def has_attachment(payload):
    if not payload:
        return False
    filename = payload.get('filename') or ''
    body = payload.get('body') or {}
    if filename.strip():
        return True
    if body.get('attachmentId'):
        return True
    for part in payload.get('parts', []) or []:
        if has_attachment(part):
            return True
    return False


def now_local(tz_name):
    os.environ['TZ'] = tz_name
    try:
        import time
        time.tzset()
    except Exception:
        pass
    return dt.datetime.now()


def email_from_header(val):
    m = re.search(r'<([^>]+)>', val or '')
    if m:
        return m.group(1).strip().lower()
    return (val or '').strip().lower()


def has_suspicious_forward(subject, text):
    s = (subject or '').strip().lower()
    if re.match(r'^(fwd:|fw:|wg:|weitergeleitet)', s):
        return True
    t = (text or '').lower()
    return ('forwarded message' in t) or ('weitergeleitete nachricht' in t)


def extract_urls(text):
    return re.findall(r'https?://[^\s)\]>"\']+', text or '', flags=re.IGNORECASE)


def log_event(log_path, obj):
    ensure_parent(log_path)
    with log_path.open('a', encoding='utf-8') as f:
        f.write(json.dumps(obj, ensure_ascii=False) + '\n')


def main():
    cfg = load_json(CONFIG_PATH, None)
    if not cfg:
        print('Missing config:', CONFIG_PATH)
        return 1

    state_path = ROOT / cfg.get('state_file', 'data/mail-automation/state.json')
    log_path = ROOT / cfg.get('log_file', 'logs/mail-automation/audit.jsonl')
    state = load_json(state_path, {
        'processed_message_ids': [],
        'per_sender_day': {},
        'per_thread': {},
        'sender_last_reply_ts': {},
        'global_day': {},
    })

    if not cfg.get('enabled', False):
        print('mail automation disabled')
        return 0

    now = now_local(cfg.get('timezone', 'Europe/Berlin'))
    day_key = now.strftime('%Y-%m-%d')

    office = cfg.get('office_hours', {})
    if office.get('enabled', True):
        hour = now.hour
        if not (int(office.get('start_hour', 8)) <= hour < int(office.get('end_hour', 20))):
            print('outside office hours')
            return 0

    keyfile = Path(cfg.get('keyring_password_file', ''))
    if not keyfile.exists():
        print('missing keyring password file:', keyfile)
        return 1

    env = os.environ.copy()
    env['GOG_KEYRING_PASSWORD'] = keyfile.read_text().strip()

    account = cfg['account']
    query = cfg.get('query', 'in:inbox is:unread newer_than:7d')
    max_fetch = int(cfg.get('max_fetch', 20))

    code, out, err = run(['gog', 'gmail', 'search', '--account', account, query, '--max', str(max_fetch), '--json'], env=env)
    if code != 0:
        print(err.strip() or out.strip())
        return 1

    data = json.loads(out or '{}')
    threads = data.get('threads', []) or []
    processed_any = 0

    # reset daily counters if needed
    if state.get('global_day', {}).get('date') != day_key:
        state['global_day'] = {'date': day_key, 'count': 0}
        state['per_sender_day'] = {}

    limits = cfg.get('limits', {})
    pol = cfg.get('policy', {})

    for th in threads:
        thread_id = th.get('id')
        code, tout, terr = run(['gog', 'gmail', 'thread', 'get', '--account', account, thread_id, '--json'], env=env)
        if code != 0:
            log_event(log_path, {'ts': now.isoformat(), 'thread_id': thread_id, 'decision': 'error', 'reason': terr.strip()})
            continue

        tjson = json.loads(tout or '{}').get('thread', {})
        msgs = tjson.get('messages', []) or []
        inbound = None
        for m in reversed(msgs):
            labels = set(m.get('labelIds', []) or [])
            if 'SENT' in labels:
                continue
            inbound = m
            break
        if not inbound:
            continue

        msg_id = inbound.get('id')
        if msg_id in state.get('processed_message_ids', []):
            continue

        headers = headers_to_map((inbound.get('payload') or {}).get('headers', []))
        text = extract_plain_text(inbound.get('payload') or {}) or inbound.get('snippet', '')

        from_raw = headers.get('from', '')
        from_email = email_from_header(from_raw)
        to_raw = headers.get('to', '')
        cc_raw = headers.get('cc', '')
        subject = headers.get('subject', '')

        is_direct = account.lower() in (to_raw or '').lower() or (pol.get('allow_cc_as_direct', True) and account.lower() in (cc_raw or '').lower())
        is_forward = has_suspicious_forward(subject, text)
        no_reply = bool(re.search(r'no-?reply|donotreply|do-not-reply|mailer-daemon', from_email, re.I))
        from_main = from_email == cfg.get('main_account', '').lower()
        has_att = has_attachment(inbound.get('payload') or {})

        reasons = []
        decision = 'allow'

        if not is_direct:
            decision = 'block'
            reasons.append('not_directly_addressed')
        if pol.get('block_forwarded', True) and is_forward:
            decision = 'block'
            reasons.append('forwarded_mail')
        if pol.get('block_no_reply', True) and no_reply:
            decision = 'block'
            reasons.append('no_reply_sender')
        if pol.get('block_from_main_account', True) and from_main:
            decision = 'block'
            reasons.append('from_main_account')
        if pol.get('block_on_attachments', True) and has_att:
            decision = 'fallback'
            reasons.append('contains_attachment')

        # security checks
        if pol.get('block_on_prompt_injection', True):
            c2, _, _ = run([str(ROOT / 'scripts' / 'clawdefender.sh'), '--check-prompt'], input_text=text)
            if c2 != 0:
                decision = 'fallback'
                reasons.append('prompt_injection_signal')

        if pol.get('block_on_suspicious_url', True):
            for u in extract_urls(text):
                c3, _, _ = run([str(ROOT / 'scripts' / 'clawdefender.sh'), '--check-url', u])
                if c3 != 0:
                    decision = 'fallback'
                    reasons.append(f'suspicious_url:{u}')
                    break

        # rate limits
        sender_day_key = f"{day_key}|{from_email}"
        sender_count = int(state.get('per_sender_day', {}).get(sender_day_key, 0))
        thread_count = int(state.get('per_thread', {}).get(thread_id, 0))
        global_count = int(state.get('global_day', {}).get('count', 0))

        if sender_count >= int(limits.get('per_sender_per_day', 3)):
            decision = 'fallback'
            reasons.append('limit_sender_day')
        if thread_count >= int(limits.get('per_thread', 2)):
            decision = 'fallback'
            reasons.append('limit_thread')
        if global_count >= int(limits.get('global_per_day', 30)):
            decision = 'fallback'
            reasons.append('limit_global_day')

        last_ts = state.get('sender_last_reply_ts', {}).get(from_email)
        if last_ts:
            try:
                last = dt.datetime.fromisoformat(last_ts)
                mins = (now - last).total_seconds() / 60
                if mins < int(limits.get('cooldown_minutes_same_sender', 15)):
                    decision = 'fallback'
                    reasons.append('cooldown_sender')
            except Exception:
                pass

        if decision == 'block':
            # no auto reply
            state.setdefault('processed_message_ids', []).append(msg_id)
            log_event(log_path, {
                'ts': now.isoformat(), 'message_id': msg_id, 'thread_id': thread_id,
                'from': from_email, 'subject': subject, 'decision': 'blocked_no_reply', 'reasons': reasons
            })
            processed_any += 1
            continue

        body = cfg.get('reply', {}).get('normal_auto_reply_template', '').strip()
        if decision == 'fallback':
            body = cfg.get('reply', {}).get('fallback_reply_template', '').strip()

        subj = subject if subject.lower().startswith('re:') else f"Re: {subject}" if subject else 'Re: Nachricht'

        sc, so, se = run([
            'gog', 'gmail', 'send', '--account', account,
            '--reply-to-message-id', msg_id, '--reply-all',
            '--subject', subj, '--body', body, '--plain'
        ], env=env)

        if sc == 0:
            state.setdefault('processed_message_ids', []).append(msg_id)
            state.setdefault('per_sender_day', {})[sender_day_key] = sender_count + 1
            state.setdefault('per_thread', {})[thread_id] = thread_count + 1
            state.setdefault('global_day', {})['date'] = day_key
            state.setdefault('global_day', {})['count'] = global_count + 1
            state.setdefault('sender_last_reply_ts', {})[from_email] = now.isoformat()
            log_event(log_path, {
                'ts': now.isoformat(), 'message_id': msg_id, 'thread_id': thread_id,
                'from': from_email, 'subject': subject, 'decision': 'sent_'+decision,
                'reasons': reasons
            })
        else:
            log_event(log_path, {
                'ts': now.isoformat(), 'message_id': msg_id, 'thread_id': thread_id,
                'from': from_email, 'subject': subject, 'decision': 'send_error',
                'reasons': reasons, 'error': (se or so).strip()
            })

        processed_any += 1

    ensure_parent(state_path)
    # cap processed ids
    ids = state.get('processed_message_ids', [])
    if len(ids) > 1000:
        state['processed_message_ids'] = ids[-1000:]
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')

    print(f'processed_threads={processed_any}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
