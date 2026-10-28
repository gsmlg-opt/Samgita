#!/usr/bin/env python3
"""Owned ordinary list metadata dependency, never an app-server peer.

One synchronous loopback HTTP listener; no children, threads, tools or model route.
Fixed synthetic identity is inert setup only. Headers and permission/policy fields
are never inspected or journaled. Native Codex creates every app-server frame.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import sys
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 32
REMOTE_ID = "plugins~Plugin_owned_ordinary_list_4883"
NAME = "owned-ordinary-list"
VERSION = "4.8.83"
DISPLAY = "Owned ordinary remote list λ🙂"
DESCRIPTION = "Owned list-only description β🙂"
CREATED = "/backend-api/ps/plugins/workspace/created"
INSTALLED = "/backend-api/ps/plugins/installed"


def remote_plugin():
    # Required native DTO setup only; only identity/descriptive metadata is tested.
    return {"id": REMOTE_ID, "name": NAME, "scope": "WORKSPACE",
            "discoverability": "PRIVATE", "installation_policy": "AVAILABLE",
            "authentication_policy": "ON_USE", "share_principals": [],
            "release": {"version": VERSION, "display_name": DISPLAY,
                        "description": DESCRIPTION, "skills": [],
                        "interface": {"short_description": DESCRIPTION}}}


class ShareListFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-share-list-journal.json"
        self.http_count = self.created_count = self.installed_count = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = json.dumps(value, ensure_ascii=False).encode()
                assert len(data) <= MAX_BODY, "Owned reply byte bound"
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

            def fail(self, method, path):
                owner.record("fatal", method=method, path=path)
                self.reply(500, {"error": "owned ordinary list dependency failed"})

            def do_GET(self):
                parsed = urlparse(self.path)
                path = parsed.path
                try:
                    self.count()
                    query = parse_qs(parsed.query, keep_blank_values=True,
                                     strict_parsing=True, max_num_fields=4)
                    if path == CREATED:
                        assert query == {"limit": ["200"]}, "Owned terminal created page"
                        owner.created_count += 1
                        assert owner.created_count == 1, "Owned one created read"
                        plugin = remote_plugin()
                        owner.record("created_page", path=path, query=query,
                                     remote_plugin_id=REMOTE_ID, name=NAME, version=VERSION,
                                     display_name=DISPLAY, description=DESCRIPTION, count=1)
                        self.reply(200, {"plugins": [plugin],
                                         "pagination": {"next_page_token": None}})
                    elif path == INSTALLED:
                        assert query == {"scope": ["WORKSPACE"]}, "Owned terminal installed page"
                        owner.installed_count += 1
                        assert owner.installed_count == 1, "Owned one installed read"
                        owner.record("installed_page", path=path, query=query, count=0)
                        self.reply(200, {"plugins": [],
                                         "pagination": {"next_page_token": None}})
                    elif path == "/backend-api/wham/config/bundle":
                        owner.record("startup_read", path=path)
                        self.reply(200, {})
                    elif path == "/backend-api/wham/accounts/check":
                        owner.record("startup_read", path=path)
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif path == "/backend-api/wham/settings/user":
                        owner.record("startup_read", path=path)
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=path)
                        self.reply(404, {})
                except Exception:
                    self.fail("GET", path)

            def unexpected(self):
                path = urlparse(self.path).path
                try:
                    self.count()
                    owner.record("unexpected_http", method=self.command, path=path)
                    self.reply(404, {})
                except Exception:
                    self.fail(self.command, path)

            do_POST = unexpected
            do_PUT = unexpected
            do_PATCH = unexpected
            do_DELETE = unexpected
            do_HEAD = unexpected
            do_OPTIONS = unexpected

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 64, "Owned journal event bound"
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
    parser.add_argument("--scenario", required=True, choices=["ordinary-plugin-share-list"])
    args = parser.parse_args()
    fixture = ShareListFixture(args)

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
