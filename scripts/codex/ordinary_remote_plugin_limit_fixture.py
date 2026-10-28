#!/usr/bin/env python3
"""Ordinary metadata pagination dependency for actual native plugin/search.

One synchronous loopback listener, no app-server emulator or model/tool route.
The reviewed ordinary setup writes inert runtime identity; it is never inspected
or compared here. Only ordinary search query/result metadata is journaled.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import time
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 65_536
MAX_HTTP = 32
MAX_EVENTS = 64
SEARCH_PATH = "/backend-api/ps/plugins/search"
KEYWORD = "owned ordinary remote limit marker"
TOKEN_PREFIX = "owned-limit-offset-"


def metadata(index):
    suffix = f"{index:02d}"
    return {
        "id": f"plugins~Plugin_ordinary_limit_{suffix}",
        "name": f"ordinary-limit-{suffix}",
        "scope": "USER",
        # Fixed required DTO setup only; no policy outcome is observed or tested.
        "installation_policy": "AVAILABLE",
        "authentication_policy": "ON_USE",
        "release": {
            "version": "1.0.0", "display_name": f"Owned remote limit {suffix} λ",
            "description": "Owned inert pagination metadata",
            "keywords": [KEYWORD], "interface": {},
        },
    }


ROWS = [metadata(index) for index in range(1, 19)]


def projection(row):
    return {"remoteId": row["id"], "name": row["name"],
            "displayName": row["release"]["display_name"]}


class Fixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.http_count = self.search_count = 0
        self.journal = self.root / "ordinary-remote-plugin-limit-journal.json"
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = json.dumps(value, ensure_ascii=False).encode()
                if len(data) > MAX_BODY:
                    raise RuntimeError("ordinary metadata response byte bound")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                if owner.http_count > MAX_HTTP or len(self.path.encode()) > 4096:
                    raise RuntimeError("ordinary metadata request bound")

            def do_GET(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    if parsed.path == SEARCH_PATH:
                        self.search(parsed)
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
                except Exception as error:
                    owner.record("fixture_error", stage="metadata-get", kind=type(error).__name__)
                    self.reply(500, {"error": "owned ordinary metadata dependency failed"})

            def search(self, parsed):
                owner.search_count += 1
                if owner.search_count > 7:
                    raise RuntimeError("ordinary explicit search count bound")
                query = parse_qs(parsed.query, keep_blank_values=True, max_num_fields=8)
                limit = int(query["limit"][0])
                if not 1 <= limit <= 1000:
                    raise RuntimeError("ordinary metadata page size bound")
                token = query.get("pageToken", [None])[0]
                offset = 0
                if token is not None:
                    if not token.startswith(TOKEN_PREFIX):
                        raise RuntimeError("ordinary metadata continuation framing")
                    offset = int(token.removeprefix(TOKEN_PREFIX))
                    if not 0 <= offset <= len(ROWS):
                        raise RuntimeError("ordinary metadata continuation bound")
                selected = ROWS[offset:offset + limit]
                end = offset + len(selected)
                next_token = f"{TOKEN_PREFIX}{end}" if end < len(ROWS) else None
                body = {"plugins": selected, "pagination": {"next_page_token": next_token}}
                encoded = json.dumps(body, ensure_ascii=False).encode()
                owner.record("search", sequence=owner.search_count, path=parsed.path,
                             query=query, rawQuery=parsed.query,
                             items=[projection(row) for row in selected], nextToken=next_token,
                             responseSize=len(encoded), responseSha256=hashlib.sha256(encoded).hexdigest())
                self.reply(200, body)
                owner.record("search_response_sent", sequence=owner.search_count)

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
        self.http.timeout = 0.1
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        if len(self.events) >= MAX_EVENTS:
            raise RuntimeError("ordinary metadata journal event bound")
        self.events.append({"event": event, **fields})
        write_json(self.journal, {"events": self.events})

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        if text.count(marker) != 1:
            raise RuntimeError("ordinary metadata setup fragment")
        path.write_text(text.replace(marker,
            "apps = false\nplugins = false\nremote_plugin = false\n"
            "plugin_sharing = false\ncodex_hooks = false\nrecommended_plugins = false\n"))
        catalog = self.root / "ordinary-remote-plugin-limit-rows.json"
        write_json(catalog, [projection(row) for row in ROWS])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-remote-plugin-limit"])
    args = parser.parse_args()
    fixture = Fixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        deadline = time.monotonic() + 50
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("ordinary metadata helper lifetime bound")
            control = fixture.root / "ordinary-remote-plugin-limit-close.json"
            if control.exists():
                if control.stat().st_size > 4096:
                    raise RuntimeError("ordinary metadata close control byte bound")
                raw = control.read_bytes()
                if len(raw) > 4096 or json.loads(raw) != {"action": "close"}:
                    raise RuntimeError("ordinary metadata close control framing")
                fixture.record("close_started")
                return
            fixture.http.handle_request()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
