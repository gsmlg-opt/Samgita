#!/usr/bin/env python3
"""Finite content-only dependency for actual native share checkout/deletion.

Every app-server request/response originates in native Codex. Synthetic runtime
identity and owned HTTPS are fixed scaffolding only; no credential/header,
authentication, permission, policy, trust or TLS outcome is inspected or tested.
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
import signal
import ssl
import sys
import tarfile
import time
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json
from ordinary_remote_lifecycle_fixture import certificates

MAX_BODY = 131_072
MAX_HTTP = 24
MAX_EVENTS = 64
REMOTE_ID = "plugins~Plugin_owned_ordinary_checkout_delete"
NAME = "ordinary-share-checkout-delete"
VERSION = "3.4.0"
MANIFEST = '{"name":"ordinary-share-checkout-delete","version":"3.4.0"}\n'
MARKER = "Owned ordinary checkout marker λ🙂\n"
EDITED_MARKER = "Owned explicit local checkout edit γ🙂\n"
SKILL = "---\nname: notes\ndescription: Owned ordinary checkout notes\n---\nKeep the independent project notes β🙂.\n"
DETAIL = "/backend-api/ps/plugins/" + REMOTE_ID
INSTALLED = "/backend-api/ps/plugins/installed"
CREATED = "/backend-api/ps/plugins/workspace/created"
DELETE = "/backend-api/public/plugins/workspace/" + REMOTE_ID
BUNDLE = "/bundles/ordinary-checkout-v1"
FILES = {".codex-plugin/plugin.json": MANIFEST, "marker.txt": MARKER,
         "skills/notes/SKILL.md": SKILL}


def bundle():
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, contents in FILES.items():
            data = contents.encode()
            entry = tarfile.TarInfo(name)
            entry.size, entry.mode, entry.mtime = len(data), 0o644, 0
            archive.addfile(entry, io.BytesIO(data))
    data = gzip.compress(raw.getvalue(), mtime=0)
    assert 0 < len(data) <= MAX_BODY
    return data


class Fixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.http_count = self.detail_count = self.scope_count = self.bundle_count = 0
        self.delete_count = self.created_count = 0
        self.present = True
        self.journal = self.root / "ordinary-share-checkout-delete-journal.json"
        self.payload = bundle()
        (self.root / "ordinary-share-checkout-bundle.tar.gz").write_bytes(self.payload)
        write_json(self.root / "ordinary-share-remote-state.json", {"remotePluginId": REMOTE_ID, "exists": True})
        directory = certificates(self.root)
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None, content_type="application/json"):
                data = b"" if value is None else (
                    value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode())
                assert len(data) <= MAX_BODY
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP and len(self.path.encode()) <= 4096

            def fail(self, stage, error):
                owner.record("fixture_error", stage=stage, kind=type(error).__name__)
                self.reply(500, {"error": "owned ordinary share dependency failed"})

            def do_GET(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    query = parse_qs(parsed.query, keep_blank_values=True,
                                     strict_parsing=True, max_num_fields=4)
                    if self.server is owner.bundles and parsed.path == BUNDLE:
                        assert query == {} and owner.present
                        assert owner.detail_count == owner.scope_count == 1 and owner.bundle_count == 0
                        owner.bundle_count += 1
                        owner.record("bundle", path=parsed.path, size=len(owner.payload),
                                     sha256=hashlib.sha256(owner.payload).hexdigest())
                        self.reply(200, owner.payload, "application/gzip")
                    elif self.server is owner.http and parsed.path == DETAIL:
                        assert owner.present and query == {"includeDownloadUrls": ["true"]}
                        assert owner.detail_count == owner.scope_count and owner.detail_count < 2
                        if owner.detail_count == 1:
                            assert owner.bundle_count == 1
                            owner.observe_checkout(EDITED_MARKER)
                        owner.detail_count += 1
                        owner.record("detail", sequence=owner.detail_count, path=parsed.path, query=query)
                        self.reply(200, owner.metadata())
                    elif self.server is owner.http and parsed.path == INSTALLED:
                        assert owner.present and query == {"scope": ["WORKSPACE"]}
                        assert owner.scope_count < 2 and owner.detail_count == owner.scope_count + 1
                        owner.scope_count += 1
                        owner.record("scope", sequence=owner.scope_count, path=parsed.path, query=query, items=[])
                        self.reply(200, {"plugins": [], "pagination": {"next_page_token": None}})
                    elif self.server is owner.http and parsed.path == CREATED:
                        assert not owner.present and owner.delete_count == 1 and owner.created_count == 0
                        assert query == {"limit": ["200"]}
                        owner.created_count += 1
                        owner.record("created", path=parsed.path, query=query, items=[])
                        self.reply(200, {"plugins": [], "pagination": {"next_page_token": None}})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/config/bundle":
                        owner.record("startup_read", path=parsed.path)
                        self.reply(200, {})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/accounts/check":
                        owner.record("startup_read", path=parsed.path)
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif self.server is owner.http and parsed.path == "/backend-api/wham/settings/user":
                        owner.record("startup_read", path=parsed.path)
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=parsed.path)
                        self.reply(404, {})
                except Exception as error:
                    self.fail("get", error)

            def do_DELETE(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    if self.server is not owner.http or parsed.path != DELETE or parsed.query:
                        owner.record("unexpected_http", method="DELETE", path=parsed.path)
                        self.reply(404, {})
                        return
                    assert owner.present and owner.delete_count == 0
                    assert owner.detail_count == owner.scope_count == 2 and owner.bundle_count == 1
                    observed = owner.observe_checkout(EDITED_MARKER)
                    effect = {"remotePluginId": REMOTE_ID, "deleted": True, **observed}
                    encoded = json.dumps(effect, ensure_ascii=False).encode()
                    assert len(encoded) <= 16_384
                    with (owner.root / "ordinary-share-delete-effect.json").open("xb") as output:
                        output.write(encoded)
                    owner.present = False
                    owner.delete_count += 1
                    write_json(owner.root / "ordinary-share-remote-state.json",
                               {"remotePluginId": REMOTE_ID, "exists": False})
                    owner.record("delete", path=parsed.path, status=204, remotePluginId=REMOTE_ID)
                    self.reply(204)
                except Exception as error:
                    self.fail("delete", error)

            def unexpected(self):
                try:
                    self.count()
                    owner.record("unexpected_http", method=self.command, path=urlparse(self.path).path)
                    self.reply(404, {})
                except Exception as error:
                    self.fail("unexpected", error)

            do_POST = unexpected
            do_PUT = unexpected
            do_PATCH = unexpected
            do_HEAD = unexpected
            do_OPTIONS = unexpected

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
        self.selector.register(sys.stdin, selectors.EVENT_READ)
        self.record("fixture_started", pid=os.getpid())

    def metadata(self):
        # Required DTO values are fixed scaffolding; their policy/access fields
        # are never read, compared or journaled as an observed result.
        return {"id": REMOTE_ID, "name": NAME, "scope": "WORKSPACE",
                "discoverability": "PRIVATE", "installation_policy": "AVAILABLE",
                "authentication_policy": "ON_USE", "share_principals": [],
                "release": {"version": VERSION, "display_name": "Owned ordinary checkout",
                            "description": "Owned inert checkout content", "interface": {}, "skills": [],
                            "bundle_download_url": f"https://127.0.0.1:{self.bundles.server_port}{BUNDLE}"}}

    def observe_checkout(self, marker):
        path = self.root / "home/plugins" / NAME
        expected = {**FILES, "marker.txt": marker}
        files = {name: (path / name).read_text() for name in expected}
        assert files == expected
        mapping_path = self.args.codex_home / ".tmp/plugin-share-local-paths-v1.json"
        assert mapping_path.stat().st_size <= 16_384
        mapping = json.loads(mapping_path.read_text())["localPluginPathsByRemotePluginId"]
        assert mapping == {REMOTE_ID: str(path)}
        return {"pluginPath": str(path), "files": files, "mapping": mapping}

    def record(self, event, **fields):
        assert len(self.events) < MAX_EVENTS
        self.events.append({"event": event, **fields})
        value = {"events": self.events}
        assert len(json.dumps(value).encode()) <= MAX_BODY
        write_json(self.journal, value)

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        fragment = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert text.count(fragment) == 1
        path.write_text(text.replace(fragment,
            "apps = false\nplugins = false\nremote_plugin = false\ncodex_hooks = false\n"
            "plugin_sharing = false\nrecommended_plugins = false\n"))

    def run(self):
        deadline = time.monotonic() + 50
        print(json.dumps({"url": f"http://127.0.0.1:{self.http.server_port}", "pid": os.getpid()}), flush=True)
        while True:
            remaining = deadline - time.monotonic()
            assert remaining > 0, "Owned ordinary share helper lifetime bound"
            for key, _events in self.selector.select(timeout=remaining):
                if key.fileobj is sys.stdin:
                    control = sys.stdin.buffer.readline(1025)
                    assert control in (b"", b"stop\n"), "Owned ordinary close framing"
                    return
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
    parser.add_argument("--scenario", required=True, choices=["ordinary-share-checkout-delete"])
    args = parser.parse_args()
    fixture = Fixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        fixture.run()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        fixture.close()


if __name__ == "__main__":
    main()
