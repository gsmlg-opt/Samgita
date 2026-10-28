#!/usr/bin/env python3
"""Owned content-only plugin share upload dependency, never an app-server peer.

Native Codex creates the tar bytes and every app-server frame. Inert identity is
fixed setup only. No credential headers, access fields or policy/default outcomes
are read. Content-Length is consumed only for bounded ordinary body framing.
One synchronous loopback listener, no children, model requests or command tools.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import signal
import tarfile
from urllib.parse import urlparse

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 32
MAX_FILE = 16_384
REMOTE_ID = "plugins~Plugin_owned_ordinary_save"
UPLOAD = "/backend-api/public/plugins/workspace/upload-url"
FINALIZE = "/backend-api/public/plugins/workspace"
FILES = {".codex-plugin/plugin.json", "marker.txt", "skills/notes/SKILL.md"}


class ShareSaveFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-share-save-journal.json"
        self.http_count = self.upload_count = self.finalize_count = 0
        self.pending = None
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
                assert len(data) <= MAX_BODY, "Owned reply byte bound"
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"

            def body(self):
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size <= MAX_BODY, "Owned input byte bound"
                data = self.rfile.read(size)
                assert len(data) == size, "Owned complete input body"
                return data

            def fail(self, method, path):
                owner.record("fatal", method=method, path=path)
                self.reply(500, {"error": "owned ordinary content dependency failed"})

            def do_GET(self):
                path = urlparse(self.path).path
                try:
                    self.count()
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
                except Exception:
                    self.fail("GET", path)

            def do_POST(self):
                path = urlparse(self.path).path
                try:
                    self.count()
                    if path == UPLOAD:
                        body = json.loads(self.body())
                        assert owner.pending is None, "Owned sequential explicit save"
                        owner.upload_count += 1
                        sequence = owner.upload_count
                        assert sequence <= 2, "Owned explicit save count bound"
                        assert body["filename"] == "ordinary-source.tar.gz"
                        assert body["mime_type"] == "application/gzip"
                        assert 0 < body["size_bytes"] <= MAX_BODY
                        plugin_id = body.get("plugin_id")
                        assert plugin_id == (None if sequence == 1 else REMOTE_ID)
                        file_id = f"file_ordinary_save_{sequence}"
                        etag = f'"upload_url_ordinary_{sequence}"'
                        owner.pending = {"sequence": sequence, "size": body["size_bytes"],
                                         "file_id": file_id, "etag": etag, "uploaded": False}
                        owner.record("upload_url", sequence=sequence, path=path,
                                     filename=body["filename"], mime_type=body["mime_type"],
                                     size=body["size_bytes"], plugin_id=plugin_id,
                                     file_id=file_id, etag=etag)
                        self.reply(201, {"file_id": file_id, "etag": etag,
                            "upload_url": f"http://127.0.0.1:{owner.http.server_port}/upload/ordinary/{sequence}"})
                    elif path in (FINALIZE, FINALIZE + "/" + REMOTE_ID):
                        body = json.loads(self.body())
                        pending = owner.pending
                        assert pending is not None and pending["uploaded"]
                        sequence = pending["sequence"]
                        expected_path = FINALIZE if sequence == 1 else FINALIZE + "/" + REMOTE_ID
                        assert path == expected_path
                        assert body["file_id"] == pending["file_id"]
                        assert body["etag"] == pending["etag"]
                        owner.finalize_count += 1
                        assert owner.finalize_count == sequence
                        owner.record("finalize", sequence=sequence, path=path,
                                     file_id=body["file_id"], etag=body["etag"])
                        owner.pending = None
                        self.reply(200, {"plugin_id": REMOTE_ID,
                            "share_url": f"https://synthetic.invalid/share/ordinary-v{sequence}"})
                    else:
                        owner.record("unexpected_http", method="POST", path=path)
                        self.reply(404, {})
                except Exception:
                    self.fail("POST", path)

            def do_PUT(self):
                path = urlparse(self.path).path
                try:
                    self.count()
                    pending = owner.pending
                    assert pending is not None and not pending["uploaded"]
                    sequence = pending["sequence"]
                    assert path == f"/upload/ordinary/{sequence}"
                    data = self.body()
                    assert len(data) == pending["size"]
                    entries = {}
                    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
                        members = archive.getmembers()
                        assert len(members) <= 16, "Owned native archive member bound"
                        for member in members:
                            if member.isdir():
                                continue
                            assert member.isfile() and member.name in FILES
                            assert member.name not in entries and member.size <= MAX_FILE
                            contents = archive.extractfile(member).read(MAX_FILE + 1)
                            assert len(contents) == member.size
                            entries[member.name] = contents.decode()
                    assert set(entries) == FILES, "Owned native content inventory"
                    filename = f"ordinary-share-upload-{sequence}.tar.gz"
                    (owner.root / filename).write_bytes(data)
                    owner.record("blob_upload", sequence=sequence, path=path, size=len(data),
                                 sha256=hashlib.sha256(data).hexdigest(), archive=filename,
                                 files=entries)
                    pending["uploaded"] = True
                    self.reply(201, b"", "application/octet-stream")
                except Exception:
                    self.fail("PUT", path)

            def do_DELETE(self):
                path = urlparse(self.path).path
                self.count()
                owner.record("unexpected_http", method="DELETE", path=path)
                self.reply(404, {})

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
    parser.add_argument("--scenario", required=True, choices=["ordinary-plugin-share-save"])
    args = parser.parse_args()
    fixture = ShareSaveFixture(args)

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
