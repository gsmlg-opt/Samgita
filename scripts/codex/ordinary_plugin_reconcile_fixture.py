#!/usr/bin/env python3
"""Owned ordinary installed-plugin snapshot and skills-only bundle dependency.

Native Codex produces every app-server frame. Identity and loopback HTTPS are
fixed setup only; this fixture never inspects headers or tests their behavior.
One process owns two synchronous listeners, bounded requests and no model/tool.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import ssl
import subprocess
import tarfile
from urllib.parse import parse_qs, urlparse

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 32
REMOTE_ID = "plugins~Plugin_owned_ordinary"
NAME = "owned-ordinary"
MARKER = "Owned ordinary reconcile marker λ🙂\n"
SKILL = "---\nname: notes\ndescription: Owned ordinary notes\n---\nOwned skill text β🙂\n"


def bundle():
    files = {".codex-plugin/plugin.json": json.dumps({"name": NAME}),
             "marker.txt": MARKER, "skills/notes/SKILL.md": SKILL}
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as archive:
        for name, contents in files.items():
            data = contents.encode()
            entry = tarfile.TarInfo(name)
            entry.size, entry.mode, entry.mtime = len(data), 0o644, 0
            archive.addfile(entry, io.BytesIO(data))
    data = stream.getvalue()
    assert len(data) <= MAX_BODY, "Owned bundle size bound"
    return data


def certificates(root):
    directory = root / "ordinary-reconcile-tls"
    directory.mkdir()
    extensions = directory / "extensions.cnf"
    extensions.write_text("subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\n"
                          "keyUsage=critical,digitalSignature,keyEncipherment\n"
                          "extendedKeyUsage=serverAuth\n")
    executable = shutil.which("openssl")
    if executable is None:
        raise RuntimeError("BLOCKED_ENV: OpenSSL required for owned listener setup")
    commands = [
        ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "2",
         "-subj", "/CN=Owned ordinary dependency", "-addext", "basicConstraints=critical,CA:TRUE",
         "-keyout", str(directory / "ca.key"), "-out", str(directory / "ca.pem")],
        ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
         "-subj", "/CN=127.0.0.1", "-keyout", str(directory / "server.key"),
         "-out", str(directory / "server.csr")],
        ["x509", "-req", "-in", str(directory / "server.csr"),
         "-CA", str(directory / "ca.pem"), "-CAkey", str(directory / "ca.key"),
         "-CAcreateserial", "-days", "2", "-sha256", "-extfile", str(extensions),
         "-out", str(directory / "server.pem")],
    ]
    for args in commands:
        subprocess.run([executable, *args], check=True, timeout=4,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    return directory


class ReconcileFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-reconcile-journal.json"
        self.http_count = self.installed_count = self.bundle_count = 0
        self.payload = bundle()
        self.state = self.root / "ordinary-reconcile-state.json"
        write_json(self.state, {"present": True})
        directory = certificates(self.root)
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value, content_type="application/json"):
                data = value if isinstance(value, bytes) else json.dumps(value).encode()
                assert len(data) <= MAX_BODY, "Owned response size bound"
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned request count bound"

            def do_GET(self):
                self.count()
                parsed = urlparse(self.path)
                query = parse_qs(parsed.query, keep_blank_values=True)
                try:
                    if self.server is owner.bundles and parsed.path == "/bundles/ordinary-v1":
                        assert query == {}, "Owned bundle route"
                        owner.bundle_count += 1
                        assert owner.bundle_count <= 2, "Owned download count bound"
                        owner.record("bundle", sequence=owner.bundle_count,
                                     path=parsed.path, size=len(owner.payload),
                                     sha256=hashlib.sha256(owner.payload).hexdigest())
                        self.reply(200, owner.payload, "application/gzip")
                    elif self.server is owner.http and parsed.path == "/backend-api/ps/plugins/installed":
                        assert query == {"limit": ["200"], "includeDownloadUrls": ["true"]}, "Owned snapshot query"
                        state = json.loads(owner.state.read_text())
                        assert state in ({"present": True}, {"present": False}), "Owned snapshot state"
                        owner.installed_count += 1
                        assert owner.installed_count <= 8, "Owned snapshot count bound"
                        owner.record("installed", sequence=owner.installed_count,
                                     path=parsed.path, query=query, present=state["present"])
                        rows = [owner.installed()] if state["present"] else []
                        self.reply(200, {"plugins": rows, "pagination": {"next_page_token": None}})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/config/bundle":
                        self.reply(200, {})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/accounts/check":
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/settings/user":
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=parsed.path)
                        self.reply(404, {})
                except Exception:
                    owner.record("fatal", stage="ordinary-reconcile-handler", path=parsed.path)
                    self.reply(500, {"error": "owned ordinary dependency failed"})

            def do_POST(self):
                self.count()
                owner.record("unexpected_http", method="POST", path=urlparse(self.path).path)
                self.reply(404, {})

            def do_DELETE(self):
                self.count()
                owner.record("unexpected_http", method="DELETE", path=urlparse(self.path).path)
                self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.bundles = HTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(directory / "server.pem", directory / "server.key")
        self.bundles.socket = context.wrap_socket(self.bundles.socket, server_side=True)
        self.bundles.socket.settimeout(5)
        self.selector = selectors.DefaultSelector()
        for server in (self.http, self.bundles):
            server.timeout = 5
            self.selector.register(server, selectors.EVENT_READ)
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 128, "Owned journal count bound"
        self.events.append({"event": event, **fields})
        data = {"events": self.events}
        assert len(json.dumps(data).encode()) <= MAX_BODY, "Owned journal byte bound"
        write_json(self.journal, data)

    def installed(self):
        # Fixed required descriptive literals are inert dependency setup only.
        return {"id": REMOTE_ID, "name": NAME, "scope": "GLOBAL", "enabled": True,
                "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
                "release": {"version": "1.0.0", "display_name": "Owned ordinary notes",
                            "description": "Owned skills-only bundle", "interface": {},
                            "bundle_download_url": f"https://127.0.0.1:{self.bundles.server_port}/bundles/ordinary-v1"}}

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert text.count(marker) == 1, "Owned ordinary feature fragment"
        path.write_text(text.replace(marker,
            "apps = false\nplugins = false\nremote_plugin = false\ncodex_hooks = false\n"
            "plugin_sharing = false\nrecommended_plugins = false\n"))

    def serve(self):
        while True:
            for key, _events in self.selector.select(timeout=0.1):
                key.fileobj._handle_request_noblock()

    def close(self):
        self.selector.close()
        self.http.server_close()
        self.bundles.server_close()
        self.record("fixture_closed", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-plugin-reconcile"])
    args = parser.parse_args()
    fixture = ReconcileFixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        fixture.serve()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
