#!/usr/bin/env python3
"""Owned snapshot+bundle; hold the second sync without returning a response.

Native Codex produces every app-server frame and all installed-cache writes.
Synthetic identity/HTTPS are fixed setup, with no header or policy checks.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tarfile
import threading

sys.dont_write_bytecode = True
from ordinary_app_context_fixture import Fixture as OrdinarySetup, write_json

MAX_BODY = 131072
REMOTE = "plugins~Plugin_owned_null_snapshot"
NAME = "owned-null-snapshot"
MARKER = "Owned null snapshot bundle λ🙂\n"
SKILL = "---\nname: notes\ndescription: Owned null snapshot notes\n---\nOwned inert snapshot β🙂\n"


def certificates(root):
    directory = root / "ordinary-installed-null-tls"
    directory.mkdir()
    extension = directory / "extension.cnf"
    extension.write_text("subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\n"
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
         "-CAcreateserial", "-days", "2", "-sha256", "-extfile", str(extension),
         "-out", str(directory / "server.pem")],
    ]
    for command in commands:
        subprocess.run([executable, *command], check=True, timeout=4,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    return directory


def bundle():
    buffer = io.BytesIO()
    files = {".codex-plugin/plugin.json": json.dumps({"name": NAME, "version": "1.0.0"}),
             "marker.txt": MARKER, "skills/notes/SKILL.md": SKILL}
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, text in files.items():
            data = text.encode()
            item = tarfile.TarInfo(name)
            item.size, item.mode, item.mtime = len(data), 0o644, 0
            archive.addfile(item, io.BytesIO(data))
    data = buffer.getvalue()
    assert len(data) <= MAX_BODY
    return data


class Fixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.lock = threading.Lock()
        self.release = threading.Event()
        self.events = []
        self.counts = {"installed": 0, "bundle": 0, "http": 0}
        self.auxiliary = {}
        self.journal = self.root / "ordinary-installed-null-journal.json"
        self.payload = bundle()
        self.directory = certificates(self.root)
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def reply(self, value, kind="application/json"):
                data = value if isinstance(value, bytes) else json.dumps(value).encode()
                assert len(data) <= MAX_BODY
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.wfile.flush()
                self.close_connection = True

            def do_GET(self):
                try:
                    with owner.lock:
                        owner.counts["http"] += 1
                        assert owner.counts["http"] <= 24 and len(self.path) <= 4096
                        owner.record("http_received", path=self.path,
                                     listener="bundle" if self.server is owner.bundles else "metadata")
                    if self.server is owner.bundles:
                        assert self.path == "/bundles/owned-null-v1"
                        with owner.lock:
                            owner.counts["bundle"] += 1
                            assert owner.counts["bundle"] == 1
                            owner.record("bundle", sequence=1, size=len(owner.payload),
                                         sha256=hashlib.sha256(owner.payload).hexdigest())
                        self.reply(owner.payload, "application/gzip")
                        with owner.lock:
                            owner.record("bundle_response_sent", sequence=1)
                    elif self.path == "/backend-api/ps/plugins/installed?limit=200&includeDownloadUrls=true":
                        with owner.lock:
                            owner.counts["installed"] += 1
                            sequence = owner.counts["installed"]
                            assert sequence in (1, 2)
                            owner.record("installed", sequence=sequence, path=self.path)
                        if sequence == 1:
                            self.reply({"plugins": [owner.metadata()],
                                        "pagination": {"next_page_token": None}})
                            with owner.lock:
                                owner.record("installed_response_sent", sequence=1)
                        else:
                            # No status/header/body is emitted for this second sync.
                            with owner.lock:
                                owner.record("second_held", sequence=2)
                            assert owner.release.wait(20), "Owned pending sync hold deadline"
                            self.close_connection = True
                            with owner.lock:
                                owner.record("second_closed_without_response", sequence=2)
                    elif self.path == "/backend-api/wham/config/bundle":
                        owner.auxiliary_once(self.path)
                        self.reply({})
                    elif self.path == "/backend-api/wham/accounts/check":
                        owner.auxiliary_once(self.path)
                        self.reply({"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif self.path == "/backend-api/wham/settings/user":
                        owner.auxiliary_once(self.path)
                        self.reply({"commit_attribution_enabled": False})
                    else:
                        raise ValueError("Unexpected owned HTTP route")
                except Exception as failure:
                    with owner.lock:
                        owner.record("fixture_error", kind=type(failure).__name__)
                    self.close_connection = True

            def do_POST(self):
                with owner.lock:
                    owner.record("unexpected_write", method="POST")
                self.close_connection = True

            def do_DELETE(self):
                with owner.lock:
                    owner.record("unexpected_write", method="DELETE")
                self.close_connection = True

        self.http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.bundles = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.directory / "server.pem", self.directory / "server.key")
        self.bundles.socket = context.wrap_socket(self.bundles.socket, server_side=True)
        self.bundles.socket.settimeout(3)
        self.workers = [threading.Thread(target=server.serve_forever)
                        for server in (self.http, self.bundles)]
        self.started = []
        for server in (self.http, self.bundles):
            server.daemon_threads = False
        with self.lock:
            self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        # Caller holds lock; journals contain only allowlisted fixture facts.
        assert len(self.events) < 64
        self.events.append({"event": event, **fields})
        data = {"events": self.events, "counts": self.counts}
        assert len(json.dumps(data).encode()) <= MAX_BODY
        write_json(self.journal, data)

    def metadata(self):
        return {"id": REMOTE, "name": NAME, "scope": "USER", "enabled": True,
                "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
                "release": {"version": "1.0.0", "display_name": "Owned snapshot",
                    "description": "Owned inert skills snapshot", "interface": {},
                    "bundle_download_url": f"https://127.0.0.1:{self.bundles.server_port}/bundles/owned-null-v1"}}

    def auxiliary_once(self, path):
        with self.lock:
            self.auxiliary[path] = self.auxiliary.get(path, 0) + 1
            assert self.auxiliary[path] == 1, "Owned auxiliary route count"
            self.record("auxiliary_get", path=path)

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert text.count(marker) == 1
        path.write_text(text.replace(marker, "apps = false\nplugins = false\n"
                        "remote_plugin = false\ncodex_hooks = false\nplugin_sharing = false\n"
                        "recommended_plugins = false\n"))

    def start(self):
        for server, worker in zip((self.http, self.bundles), self.workers):
            worker.start()
            self.started.append((server, worker))

    def close(self):
        self.release.set()
        for server, _worker in self.started:
            server.shutdown()
        for server in (self.http, self.bundles):
            server.server_close()
        for _server, worker in self.started:
            worker.join(3)
            assert not worker.is_alive(), "Owned listener shutdown unconfirmed"
        with self.lock:
            self.record("fixture_closed", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    parser.add_argument("--scenario", choices=["ordinary-installed-null"], required=True)
    args = parser.parse_args()
    fixture = Fixture(args)
    try:
        fixture.configure()
        fixture.start()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        for raw in sys.stdin:
            assert len(raw) <= 128 and json.loads(raw) == {"close": True}
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
