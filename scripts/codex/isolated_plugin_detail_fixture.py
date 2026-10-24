#!/usr/bin/env python3
"""Owned metadata-only remote plugin details for the pinned native app-server.

This composes the existing namespace, file-auth, and native-process lifecycle.
Only the backend fixture is replaced; app-server messages are forwarded intact.
No model, download, mutation, or scheduled execution endpoint is admitted.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
from urllib.parse import parse_qs, urlparse

import isolated_remote_plugin_fixture as shared

REMOTE_ID = "plugins~Plugin_owned_schedule"
METHODS = {"initialize", "initialized", "thread/loaded/list", "plugin/read"}
DETAIL = "/backend-api/ps/plugins/" + REMOTE_ID
INSTALLED = "/backend-api/ps/plugins/installed"


class Fixture(shared.Fixture):
    def __init__(self, root, namespace):
        self.root, self.lock = root, threading.Lock()
        namespace = dict(namespace)
        for family, key in [("-4", "routes_v4"), ("-6", "routes_v6")]:
            routes = json.loads(subprocess.check_output(
                ["ip", family, "-j", "route", "show", "table", "all"], timeout=5))
            assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
            namespace[key] = routes
        journal = root / "journal.json"
        self.journal = json.loads(journal.read_text()) if journal.exists() else {"events": []}
        self.journal["namespace"] = namespace
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = False

            def handle_error(self, _request, _client):
                fixture.record("fixture_error", error=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def respond(self, status, value, raw=None):
                body = raw.encode() if raw is not None else json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                if status == 429:
                    self.send_header("Retry-After", "0")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path in {DETAIL, INSTALLED}:
                    state = json.loads((root / "detail-state.json").read_text())
                    resource = "detail" if parsed.path == DETAIL else "installed"
                    selected = state[resource]
                    bearer = self.headers.get("Authorization") == "Bearer " + shared.ACCESS_TOKEN
                    account = self.headers.get("chatgpt-account-id") == shared.ACCOUNT_ID
                    product = self.headers.get("oai-product-sku") == "codex"
                    status = selected.get("status", 200)
                    fixture.record(resource, path=parsed.path, query=parse_qs(parsed.query),
                                   status=status, bearer_verified=bearer,
                                   account_verified=account, product_verified=product)
                    if not (bearer and account and product):
                        self.respond(401, {"error": "owned header mismatch"})
                    elif status != 200:
                        self.respond(status, {"error": "owned backend failure"})
                    else:
                        self.respond(status, selected.get("body"), selected.get("raw"))
                elif parsed.path in {"/backend-api/wham/config/bundle",
                                      "/backend-api/wham/accounts/check",
                                      "/backend-api/wham/settings/user"}:
                    body = {"accounts": [{"id": shared.ACCOUNT_ID,
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]} if parsed.path.endswith("accounts/check") else {}
                    fixture.record("startup_metadata", path=parsed.path)
                    self.respond(200, body)
                else:
                    fixture.record("forbidden_http", method="GET", path=parsed.path)
                    self.respond(404, {"error": "unapproved route"})

            def do_POST(self):
                fixture.record("forbidden_http", method="POST", path=urlparse(self.path).path)
                self.respond(405, {"error": "no model, scheduler, or mutation endpoint"})

        self.backend = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.backend.serve_forever, daemon=True)
        self.thread.start()

    # configure and record intentionally use the shared, file-only credential
    # configuration. The shared TLS CA is unused: this fixture has no bundle route.
    def close(self):
        self.backend.shutdown()
        self.backend.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned plugin detail peer did not stop"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--auth", choices=["chatgpt", "none", "apikey"], default="chatgpt")
    parser.add_argument("--trust-env", choices=["CODEX_CA_CERTIFICATE", "SSL_CERT_FILE"], default="CODEX_CA_CERTIFICATE")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    assert hashlib.sha256(args.codex.resolve(strict=True).read_bytes()).hexdigest() == shared.BINARY_SHA256
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip", "openssl"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.Fixture = Fixture
    shared.ALLOWED_METHODS = METHODS
    shared.isolated(args)


if __name__ == "__main__":
    main()
