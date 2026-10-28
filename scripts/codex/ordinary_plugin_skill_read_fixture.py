#!/usr/bin/env python3
"""Owned direct skill-content dependency for stock native Codex.

One synchronous loopback HTTP listener, no app-server emulator, model/tool or
bundle endpoint. Inert identity is setup only. No credential headers or policy
outcomes are read. Content-Length responses provide ordinary bounded framing.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
from urllib.parse import urlparse

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 65_536
MAX_HTTP = 32
REMOTE_ID = "plugins~Plugin_owned_skill"
SKILL_NAME = "notes"
SKILL_PATH = f"/backend-api/ps/plugins/{REMOTE_ID}/skills/{SKILL_NAME}"
CONTENTS = ("---\nname: notes\ndescription: Owned ordinary remote notes\n---\n"
            "# Ordinary skill λ🙂\nRecord project facts β, preserve 漢字.\n")


class SkillReadFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-plugin-skill-read-journal.json"
        self.http_count = self.skill_count = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
                assert len(data) <= MAX_BODY, "Owned response byte bound"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"

            def do_GET(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    if parsed.path == SKILL_PATH and parsed.query == "":
                        owner.skill_count += 1
                        sequence = owner.skill_count
                        assert sequence <= 2, "Owned explicit content fetch bound"
                        body = {"plugin_id": REMOTE_ID, "name": SKILL_NAME,
                                "skill_md_contents": CONTENTS if sequence == 1 else None}
                        raw = json.dumps(body, ensure_ascii=False)
                        data = raw.encode()
                        assert len(data) <= MAX_BODY
                        owner.record("skill", sequence=sequence, path=parsed.path,
                                     query=parsed.query, response=body, raw=raw, size=len(data))
                        self.reply(200, data)
                    elif parsed.path == "/backend-api/wham/config/bundle":
                        self.reply(200, {})
                    elif parsed.path == "/backend-api/wham/accounts/check":
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif parsed.path == "/backend-api/wham/settings/user":
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=parsed.path)
                        self.reply(404, {})
                except Exception:
                    owner.record("fatal", method="GET", path=parsed.path)
                    self.reply(500, {"error": "owned ordinary skill dependency failed"})

            def unexpected(self, method):
                self.count()
                owner.record("unexpected_http", method=method, path=urlparse(self.path).path)
                self.reply(404, {})

            def do_POST(self):
                self.unexpected("POST")

            def do_PUT(self):
                self.unexpected("PUT")

            def do_DELETE(self):
                self.unexpected("DELETE")

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 128, "Owned journal event bound"
        self.events.append({"event": event, **fields})
        data = {"events": self.events}
        assert len(json.dumps(data).encode()) <= MAX_BODY, "Owned journal byte bound"
        write_json(self.journal, data)

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert text.count(marker) == 1, "Owned ordinary feature fragment"
        path.write_text(text.replace(marker,
            "apps = false\nplugins = false\nremote_plugin = false\ncodex_hooks = false\n"
            "plugin_sharing = false\nrecommended_plugins = false\n"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-plugin-skill-read"])
    args = parser.parse_args()
    fixture = SkillReadFixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        fixture.http.serve_forever(poll_interval=0.1)
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
