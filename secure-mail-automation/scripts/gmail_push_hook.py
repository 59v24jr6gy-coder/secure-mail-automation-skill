#!/usr/bin/env python3
import json
import datetime as dt
import subprocess
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = Path('/data/.openclaw/workspace')
RUNNER = ROOT / 'scripts' / 'mail_auto_reply_v1.py'
LOG = ROOT / 'logs' / 'mail-automation' / 'push-hook.log'
LOCK = ROOT / 'data' / 'mail-automation' / 'runner.lock'


def wlog(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open('a', encoding='utf-8') as f:
        f.write(f"{dt.datetime.now().isoformat()} {msg}\n")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path.startswith('/health'):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if not self.path.startswith('/hook'):
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length) if length > 0 else b''
        try:
            payload = json.loads(body.decode('utf-8')) if body else {}
        except Exception:
            payload = {'raw': body.decode('utf-8', errors='replace')}

        wlog('event=' + json.dumps(payload, ensure_ascii=False))

        if LOCK.exists():
            wlog('runner_skipped=lock_present')
        else:
            try:
                LOCK.parent.mkdir(parents=True, exist_ok=True)
                LOCK.write_text(str(dt.datetime.now().timestamp()), encoding='utf-8')
                p = subprocess.run(['python3', str(RUNNER)], capture_output=True, text=True)
                wlog(f"runner_exit={p.returncode} stdout={p.stdout.strip()} stderr={p.stderr.strip()}")
            finally:
                try:
                    LOCK.unlink(missing_ok=True)
                except Exception:
                    pass

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"ok":true}')


if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8790), Handler)
    wlog('hook_server_started on 127.0.0.1:8790')
    server.serve_forever()
