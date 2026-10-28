#!/usr/bin/env python3
"""Owned ordinary remote lifecycle dependency; native Codex owns all wire frames.

Two synchronous owned loopback listeners supply one inert skill-only tar bundle
and real install/uninstall mutations. Synthetic identity and HTTPS setup are
fixed scaffolding only; no credential, header, policy or TLS outcome is tested.
"""
import argparse
import gzip
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
import sys
import tarfile
import time
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 24
MAX_EVENTS = 64
REMOTE_ID = "plugins~Plugin_ordinary_remote_lifecycle"
NAME = "ordinary-remote-lifecycle"
MARKET = "created-by-me-remote"
MANIFEST = '{"name":"ordinary-remote-lifecycle","version":"1.0.0"}\n'
MARKER = "Owned ordinary remote install marker λ🙂\n"
SKILL = "---\nname: notes\ndescription: Owned ordinary install notes\n---\nOwned installed skill text β🙂\n"


def bundle():
    files = {".codex-plugin/plugin.json": MANIFEST,
             "marker.txt": MARKER, "skills/notes/SKILL.md": SKILL}
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, contents in files.items():
            data = contents.encode()
            entry = tarfile.TarInfo(name)
            entry.size, entry.mode, entry.mtime = len(data), 0o644, 0
            archive.addfile(entry, io.BytesIO(data))
    data = gzip.compress(raw.getvalue(), mtime=0)
    if not 0 < len(data) <= MAX_BODY:
        raise RuntimeError("ordinary install bundle byte bound")
    return data


def certificates(root):
    directory = root / "ordinary-remote-lifecycle-tls"
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


class Fixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.http_count = self.detail_count = self.scope_count = 0
        self.bundle_count = self.install_count = self.uninstall_count = self.refresh_count = 0
        self.present = False
        self.journal = self.root / "ordinary-remote-lifecycle-journal.json"
        self.payload = bundle()
        (self.root / "ordinary-remote-lifecycle-bundle.tar.gz").write_bytes(self.payload)
        directory = certificates(self.root)
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def reply(self, status, value, content_type="application/json"):
                data = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
                if len(data) > MAX_BODY:
                    raise RuntimeError("ordinary install response byte bound")
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                if owner.http_count > MAX_HTTP or len(self.path.encode()) > 4096:
                    raise RuntimeError("ordinary install HTTP request bound")

            def do_GET(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    query = parse_qs(parsed.query, keep_blank_values=True, max_num_fields=8)
                    if self.server is owner.bundles and parsed.path == "/bundles/ordinary-v1":
                        owner.bundle_count += 1
                        if query != {} or owner.bundle_count != 1:
                            raise RuntimeError("ordinary install bundle route/count")
                        owner.record("bundle", sequence=owner.bundle_count, path=parsed.path,
                                     size=len(owner.payload), sha256=hashlib.sha256(owner.payload).hexdigest())
                        self.reply(200, owner.payload, "application/gzip")
                        owner.record("bundle_response_sent", sequence=owner.bundle_count)
                    elif self.server is owner.http and parsed.path == "/backend-api/ps/plugins/" + REMOTE_ID:
                        owner.detail_count += 1
                        installing = owner.detail_count == 1 and not owner.present
                        removing = owner.detail_count == 2 and owner.present and owner.install_count == 1
                        expected = {"includeDownloadUrls": ["true"]} if installing else {}
                        if not (installing or removing) or query != expected:
                            raise RuntimeError("ordinary lifecycle detail route/count")
                        owner.record("detail", sequence=owner.detail_count, path=parsed.path,
                                     query=query, rawQuery=parsed.query)
                        self.reply(200, owner.metadata())
                        owner.record("detail_response_sent", sequence=owner.detail_count)
                    elif self.server is owner.http and parsed.path == "/backend-api/ps/plugins/installed":
                        if query == {"scope": ["USER"]} and not owner.present:
                            owner.scope_count += 1
                            if owner.scope_count != 1:
                                raise RuntimeError("ordinary install scoped join count")
                            owner.record("scope", sequence=owner.scope_count, path=parsed.path, query=query, items=[])
                            self.reply(200, {"plugins": [], "pagination": {"next_page_token": None}})
                            owner.record("scope_response_sent", sequence=owner.scope_count)
                        elif query == {"limit": ["200"]}:
                            owner.refresh_count += 1
                            installing = owner.refresh_count == 1 and owner.present and owner.uninstall_count == 0
                            removing = owner.refresh_count == 2 and not owner.present and owner.uninstall_count == 1
                            if not (installing or removing):
                                raise RuntimeError("ordinary lifecycle refresh state/count")
                            owner.record("refresh", sequence=owner.refresh_count, path=parsed.path,
                                         query=query, items=[REMOTE_ID] if owner.present else [])
                            self.reply(200, {"plugins": [owner.installed()] if owner.present else [],
                                             "pagination": {"next_page_token": None}})
                            owner.record("refresh_response_sent", sequence=owner.refresh_count)
                        else:
                            raise RuntimeError("ordinary install installed route/state")
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
                except Exception as error:
                    owner.record("fixture_error", stage="ordinary-install-get", kind=type(error).__name__)
                    self.reply(500, {"error": "owned ordinary dependency failed"})

            def do_POST(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    base = "/backend-api/ps/plugins/" + REMOTE_ID
                    if self.server is not owner.http or parsed.path not in (base + "/install", base + "/uninstall"):
                        owner.record("unexpected_http", method="POST", path=parsed.path)
                        self.reply(404, {})
                        return
                    if parsed.path == base + "/uninstall":
                        owner.uninstall_count += 1
                        if owner.uninstall_count != 1 or not owner.present or owner.install_count != 1:
                            raise RuntimeError("ordinary lifecycle uninstall state/count")
                        if parsed.query != "":
                            raise RuntimeError("ordinary lifecycle uninstall route")
                        owner.require_materialized()
                        owner.present = False
                        write_json(owner.root / "ordinary-remote-lifecycle-state.json", {"removed": REMOTE_ID})
                        owner.record("uninstall", sequence=owner.uninstall_count, path=parsed.path,
                                     items=[REMOTE_ID], materialized=True)
                        self.reply(200, {"id": REMOTE_ID, "enabled": False})
                        owner.record("uninstall_response_sent", sequence=owner.uninstall_count)
                        return
                    owner.install_count += 1
                    # The native install URL's fixed optional setup query is not observed.
                    if owner.install_count != 1 or owner.present:
                        raise RuntimeError("ordinary install mutation route/count")
                    owner.require_materialized()
                    owner.present = True
                    write_json(owner.root / "ordinary-remote-lifecycle-state.json", {"installed": REMOTE_ID})
                    owner.record("install", sequence=owner.install_count, path=parsed.path,
                                 items=[REMOTE_ID], materialized=True)
                    self.reply(200, {"id": REMOTE_ID, "enabled": True, "app_ids_needing_auth": []})
                    owner.record("install_response_sent", sequence=owner.install_count)
                except Exception as error:
                    owner.record("fixture_error", stage="ordinary-install-post", kind=type(error).__name__)
                    self.reply(500, {"error": "owned ordinary mutation failed"})

            def do_DELETE(self):
                self.count()
                owner.record("unexpected_http", method="DELETE", path=urlparse(self.path).path)
                self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.bundles = HTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(directory / "server.pem", directory / "server.key")
        self.bundles.socket = context.wrap_socket(self.bundles.socket, server_side=True)
        self.bundles.socket.settimeout(3)
        self.selector = selectors.DefaultSelector()
        for server in (self.http, self.bundles):
            server.timeout = 0.1
            self.selector.register(server, selectors.EVENT_READ)
        self.record("fixture_started", pid=os.getpid())

    def require_materialized(self):
        version = self.args.codex_home / "plugins" / "cache" / MARKET / NAME / "1.0.0"
        actual = {
            ".codex-plugin/plugin.json": (version / ".codex-plugin/plugin.json").read_text(),
            "marker.txt": (version / "marker.txt").read_text(),
            "skills/notes/SKILL.md": (version / "skills/notes/SKILL.md").read_text(),
        }
        if actual != {".codex-plugin/plugin.json": MANIFEST,
                      "marker.txt": MARKER, "skills/notes/SKILL.md": SKILL}:
            raise RuntimeError("ordinary lifecycle materialization before mutation")

    def metadata(self):
        return {"id": REMOTE_ID, "name": NAME, "scope": "USER",
                # Required fixed DTO setup only; no policy behavior is observed.
                "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
                "release": {"version": "1.0.0", "display_name": "Owned ordinary install",
                            "description": "Owned inert skill-only install", "interface": {},
                            "bundle_download_url": f"https://127.0.0.1:{self.bundles.server_port}/bundles/ordinary-v1"}}

    def installed(self):
        return {**self.metadata(), "enabled": True, "disabled_skill_names": []}

    def record(self, event, **fields):
        if len(self.events) >= MAX_EVENTS:
            raise RuntimeError("ordinary install journal event bound")
        self.events.append({"event": event, **fields})
        write_json(self.journal, {"events": self.events})

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        if text.count(marker) != 1:
            raise RuntimeError("ordinary install setup fragment")
        path.write_text(text.replace(marker,
            "apps = false\nplugins = false\nremote_plugin = false\ncodex_hooks = false\n"
            "plugin_sharing = false\nrecommended_plugins = false\n"))

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
    parser.add_argument("--scenario", required=True, choices=["ordinary-remote-lifecycle"])
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
                raise TimeoutError("ordinary install helper lifetime bound")
            control = fixture.root / "ordinary-remote-lifecycle-close.json"
            if control.exists():
                if control.stat().st_size > 4096:
                    raise RuntimeError("ordinary install close control byte bound")
                raw = control.read_bytes()
                if len(raw) > 4096 or json.loads(raw) != {"action": "close"}:
                    raise RuntimeError("ordinary install close control framing")
                fixture.record("close_started")
                return
            for key, _events in fixture.selector.select(timeout=0.1):
                key.fileobj._handle_request_noblock()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
