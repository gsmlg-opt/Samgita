#!/usr/bin/env python3
"""Plain app/read metadata inputs for stock Codex, without a model/MCP executor.

Only the already-reviewed ordinary context fixture's inert runtime setup and
bounded journal/cleanup are reused. No mixed Apps/auth helper is imported.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
from urllib.parse import urlparse

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import MAX_BODY, MAX_HTTP

IDS = ["metadata-alpha", "metadata-beta"]
ABSENT = "metadata-absent"


def metadata(app_id, include_tools):
    suffix = {"metadata-alpha": "Alpha", "metadata-beta": "Beta"}[app_id]
    return {
        "id": app_id, "name": "Owned " + suffix,
        "description": "Owned " + suffix + " display metadata λ🙂",
        "icon_url": f"https://synthetic.invalid/{app_id}/light.svg",
        "icon_dark_url": f"https://synthetic.invalid/{app_id}/dark.svg",
        "distribution_channel": "OWNED_METADATA_DIRECTORY",
        "tools": [{"name": app_id + "_lookup", "title": suffix + " lookup β",
                   "description": "Display-only " + suffix + " tool summary 🙂",
                   "is_enabled": True, "disabled_reason": "Opaque metadata label λ",
                   "is_read_only": True}] if include_tools else None,
    }


class MetadataFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-app-metadata-journal.json"
        self.http_count = 0
        self.batch_count = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = json.dumps(value).encode()
                assert len(data) <= MAX_BODY, "Owned metadata reply bound"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def do_GET(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                path = urlparse(self.path).path
                if path == "/backend-api/wham/config/bundle":
                    self.reply(200, {})
                elif path == "/backend-api/wham/accounts/check":
                    self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                        "workspace_backend_origin": "https://synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]})
                elif path == "/backend-api/wham/settings/user":
                    self.reply(200, {"commit_attribution_enabled": False})
                else:
                    owner.record("unexpected_http", method="GET", path=path)
                    self.reply(404, {})

            def do_POST(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                path = urlparse(self.path).path
                if path != "/backend-api/ps/apps/batch":
                    owner.record("unexpected_http", method="POST", path=path)
                    self.reply(404, {})
                    return
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 65_536, "Owned metadata request body bound"
                    raw = self.rfile.read(size)
                    body = json.loads(raw)
                    assert set(body) == {"app_ids", "include_tools"}
                    assert isinstance(body["app_ids"], list) and len(body["app_ids"]) <= 100
                    assert all(value in IDS + [ABSENT] for value in body["app_ids"])
                    assert isinstance(body["include_tools"], bool)
                    owner.batch_count += 1
                    assert owner.batch_count <= 4, "Owned metadata batch count bound"
                    owner.record("batch", sequence=owner.batch_count, body=body,
                                 raw=raw.decode(), size=len(raw))
                    # Native selection/deduplication/order must be independent
                    # of the backend's canonical order and extra/duplicate rows.
                    apps = [metadata(app_id, body["include_tools"])
                            for app_id in IDS if app_id in body["app_ids"]]
                    if "metadata-alpha" in body["app_ids"]:
                        duplicate = metadata("metadata-alpha", body["include_tools"])
                        duplicate["name"] = "Duplicate must not replace first"
                        apps.append(duplicate)
                    apps.append({**metadata("metadata-alpha", body["include_tools"]),
                                 "id": "metadata-surplus", "name": "Surplus display record"})
                    self.reply(200, {"apps": apps})
                except Exception:
                    owner.record("fatal", stage="ordinary-metadata-handler")
                    self.reply(500, {"error": "owned metadata fixture failed"})

            def do_DELETE(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                owner.record("unexpected_http", method="DELETE", path=urlparse(self.path).path)
                self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-app-metadata"])
    args = parser.parse_args()
    fixture = MetadataFixture(args)

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
