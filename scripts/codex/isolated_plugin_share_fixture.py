#!/usr/bin/env python3
"""Source-only owned HTTP/TLS dependencies for native Codex plugin sharing.

The bridge forwards allowlisted requests to the real pinned app-server unchanged.
It never constructs an app-server response or exposes model/execution endpoints.
"""
import argparse
from copy import deepcopy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import shutil
import signal
import ssl
import subprocess
import sys
import tarfile
import threading
from urllib.parse import parse_qs, urlparse

import isolated_remote_plugin_fixture as shared

REMOTE_ID = "plugins~Plugin_owned_share"
NAME = "owned-share"
METHODS = {"initialize", "initialized", "thread/loaded/list", "plugin/share/save",
           "plugin/share/list", "plugin/share/updateTargets", "plugin/share/checkout",
           "plugin/share/delete"}
BASE = "/backend-api"
UPLOAD = BASE + "/public/plugins/workspace/upload-url"
CREATE = BASE + "/public/plugins/workspace"
MUTATE = CREATE + "/" + REMOTE_ID
CREATED = BASE + "/ps/plugins/workspace/created"
INSTALLED = BASE + "/ps/plugins/installed"
DETAIL = BASE + "/ps/plugins/" + REMOTE_ID
TARGETS = DETAIL + "/shares"


class Fixture:
    def __init__(self, root, namespace):
        self.root, self.lock = root, threading.RLock()
        path = root / "journal.json"
        self.journal = json.loads(path.read_text()) if path.exists() else {"events": []}
        self.journal["namespace"] = namespace
        path = root / "share-db.json"
        self.db = json.loads(path.read_text()) if path.exists() else {
            "exists": self.state().get("seed", True), "version": 1,
            "marker": "remote owned marker", "discoverability": "PRIVATE",
            "principals": [{"principal_type": "user", "principal_id": "owner-1",
                            "role": "owner", "name": "Owned owner"}],
        }
        self.persist()
        self.uploaded = None
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

            def respond(self, status, body=b"", content_type="application/json", **headers):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                if status == 429:
                    self.send_header("Retry-After", "0")
                for key, value in headers.items():
                    self.send_header(key, value)
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def reply(self, status, body):
                self.respond(status, json.dumps(body).encode())

            def backend(self, resource, default, body=None, status=200, effect=None):
                assert self.server is fixture.backend
                bearer = self.headers.get("Authorization") == "Bearer " + shared.ACCESS_TOKEN
                account = self.headers.get("chatgpt-account-id") == shared.ACCOUNT_ID
                parsed = urlparse(self.path)
                override = fixture.state().get("overrides", {}).get(resource, {})
                selected_status = override.get("status", status)
                fixture.record(resource, path=parsed.path, method=self.command,
                               query=parse_qs(parsed.query), body=body, status=selected_status,
                               bearer_verified=bearer, account_verified=account)
                if not (bearer and account):
                    self.reply(401, {"error": "synthetic credentials mismatch"})
                    return False
                if override:
                    if "raw" in override:
                        self.respond(selected_status, override["raw"].encode())
                    elif "merge" in override:
                        self.reply(selected_status, {**default, **override["merge"]})
                    else:
                        self.reply(selected_status, override.get("body", {"error": "synthetic failure"}))
                    return False
                if effect is not None:
                    effect()
                if status == 204:
                    self.respond(status)
                else:
                    self.reply(status, default)
                return True

            def forbidden(self):
                fixture.record("forbidden_http", path=urlparse(self.path).path, method=self.command)
                self.reply(404, {"error": "route not allowlisted"})

            def request_json(self):
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 <= size <= 64_000
                return json.loads(self.rfile.read(size))

            def do_GET(self):
                parsed = urlparse(self.path)
                if self.server is fixture.objects:
                    if parsed.path != "/bundles/owned.tar.gz" or parsed.query:
                        return self.forbidden()
                    assert isinstance(self.connection, ssl.SSLSocket)
                    fixture.record("bundle", path=parsed.path, tls_version=self.connection.version(),
                                   authorization_absent=self.headers.get("Authorization") is None,
                                   account_absent=self.headers.get("chatgpt-account-id") is None)
                    self.respond(200, shared.bundle_bytes({"name": NAME, "marker": fixture.db["marker"],
                                                          "capabilities": []}), "application/gzip")
                elif parsed.path == CREATED:
                    rows = [fixture.row()] if fixture.db["exists"] else []
                    self.backend("created", {"plugins": rows, "pagination": {"next_page_token": None}})
                elif parsed.path == INSTALLED:
                    rows = []
                    if fixture.db["exists"] and fixture.state().get("installed", False):
                        row = fixture.row()
                        row.update(enabled=True, disabled_skill_names=[])
                        rows.append(row)
                    self.backend("installed", {"plugins": rows, "pagination": {"next_page_token": None}})
                elif parsed.path == DETAIL:
                    self.backend("detail", fixture.row())
                elif parsed.path in {BASE + "/wham/config/bundle", BASE + "/wham/accounts/check",
                                     BASE + "/wham/settings/user"}:
                    fixture.record("startup_metadata", path=parsed.path)
                    body = {"accounts": [{"id": shared.ACCOUNT_ID,
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]} if parsed.path.endswith("accounts/check") else {}
                    self.reply(200, body)
                else:
                    self.forbidden()

            def do_POST(self):
                path = urlparse(self.path).path
                if self.server is not fixture.backend or path not in {UPLOAD, CREATE, MUTATE}:
                    return self.forbidden()
                body = self.request_json()
                if path == UPLOAD:
                    assert body["filename"] in {"owned-share.tar.gz", "source-plugin.tar.gz"}
                    assert body["mime_type"] == "application/gzip" and 0 < body["size_bytes"] < 1_000_000
                    assert body.get("plugin_id") in {None, REMOTE_ID}
                    fixture.uploaded = None
                    self.backend("upload_url", {"file_id": "file_owned", "etag": '"url_etag_owned"',
                        "upload_url": f"https://127.0.0.1:{fixture.objects.server_port}/upload/owned"}, body, 201)
                else:
                    assert body["file_id"] == "file_owned" and body["etag"] == '"url_etag_owned"'
                    assert fixture.uploaded is not None
                    response = {"plugin_id": REMOTE_ID, "share_url": "https://synthetic.invalid/share/owned",
                                "can_publish_to_workspace": True}
                    def finalize():
                        fixture.db["version"] = fixture.db["version"] + 1 if path == MUTATE else 1
                        fixture.db["exists"] = True
                        fixture.db["marker"] = fixture.uploaded["marker.txt"]
                        if "discoverability" in body:
                            fixture.db["discoverability"] = body["discoverability"]
                        if "share_targets" in body:
                            fixture.db["principals"] = fixture.principals(body["share_targets"])
                        fixture.persist()
                    self.backend("finalize", response, body, 200, finalize)

            def do_PUT(self):
                parsed = urlparse(self.path)
                if self.server is fixture.objects and parsed.path == "/upload/owned" and not parsed.query:
                    assert isinstance(self.connection, ssl.SSLSocket)
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size < 1_000_000
                    archive_bytes = self.rfile.read(size)
                    entries = {}
                    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
                        for item in archive.getmembers():
                            assert not Path(item.name).is_absolute() and ".." not in Path(item.name).parts
                            assert item.isdir() or item.isfile()
                            if item.isfile():
                                assert item.name in {".codex-plugin/plugin.json", "marker.txt"}
                                entries[item.name] = archive.extractfile(item).read().decode()
                    assert set(entries) == {".codex-plugin/plugin.json", "marker.txt"}
                    assert json.loads(entries[".codex-plugin/plugin.json"])["name"] == NAME
                    override = fixture.state().get("overrides", {}).get("blob_upload", {})
                    status = override.get("status", 201)
                    fixture.record("blob_upload", path=parsed.path, status=status, size=size, files=entries,
                                   mime_type=self.headers.get("Content-Type"), blob_type=self.headers.get("x-ms-blob-type"),
                                   tls_version=self.connection.version(),
                                   authorization_absent=self.headers.get("Authorization") is None,
                                   account_absent=self.headers.get("chatgpt-account-id") is None)
                    if status in [200, 201]:
                        fixture.uploaded = entries
                    self.respond(status, b"", etag='"blob_etag_deliberately_different"')
                elif self.server is fixture.backend and parsed.path == TARGETS:
                    body = self.request_json()
                    principals = fixture.principals(body["targets"])
                    def update_targets():
                        fixture.db.update(discoverability=body["discoverability"], principals=principals)
                        fixture.persist()
                    self.backend("targets", {"principals": principals,
                                 "discoverability": body["discoverability"]}, body, effect=update_targets)
                else:
                    self.forbidden()

            def do_DELETE(self):
                if self.server is fixture.backend and self.path == MUTATE:
                    def delete():
                        fixture.db["exists"] = False
                        fixture.persist()
                    self.backend("delete", None, status=204, effect=delete)
                else:
                    self.forbidden()

        self.backend = Server(("127.0.0.1", 0), Handler)
        self.objects = Server(("127.0.0.1", 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(root / "tls/server.pem", root / "tls/server.key")
        self.objects.socket = tls.wrap_socket(self.objects.socket, server_side=True)
        self.threads = []
        for server in [self.backend, self.objects]:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)

    def state(self):
        return json.loads((self.root / "share-state.json").read_text())

    def persist(self):
        shared.atomic_json(self.root / "share-db.json", self.db)

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            shared.atomic_json(self.root / "journal.json", self.journal)

    @staticmethod
    def principals(targets):
        return [{"principal_type": "user", "principal_id": "owner-1", "role": "owner", "name": "Owned owner"},
                *[{**target, "name": "Owned " + target["principal_id"]} for target in targets]]

    def row(self):
        row = {"id": REMOTE_ID, "name": NAME, "scope": "WORKSPACE",
               "discoverability": self.db["discoverability"],
               "creator_account_user_id": "owner-1", "creator_name": "Owned owner",
               "share_url": "https://synthetic.invalid/share/owned", "share_principals": self.db["principals"],
               "can_publish_to_workspace": True, "installation_policy": "AVAILABLE",
               "must_show_installation_interstitial": False, "authentication_policy": "ON_USE",
               "release": {"version": f'{self.db["version"]}.0.0', "display_name": "Owned share λ",
                           "description": "Owned metadata only", "skills": [],
                           "interface": {"short_description": "Owned description", "capabilities": ["Inspect"]},
                           "bundle_download_url": f"https://127.0.0.1:{self.objects.server_port}/bundles/owned.tar.gz"}}
        override = deepcopy(self.state().get("row", {}))
        release = override.pop("release", {})
        row.update(override)
        row["release"].update(release)
        return row

    def close(self):
        for server in [self.backend, self.objects]:
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(5)
            assert not thread.is_alive(), "owned share HTTP/TLS peer did not stop"


def isolated(args):
    root, binary = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == shared.BINARY_SHA256
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    namespace = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    routes += json.loads(subprocess.check_output(["ip", "-j", "-6", "route", "show", "table", "all"]))
    assert namespace != args.parent_netns and [link["ifname"] for link in links] == ["lo"]
    assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
    shared.generate_certificates(root)
    fixture = Fixture(root, {"parent": args.parent_netns, "child": namespace,
                             "interfaces": ["lo"], "default_route": False})
    native, reader = None, None

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        # Reuse only the existing synthetic auth/config primitive, never its server.
        environment = shared.Fixture.configure(fixture, args.auth, args.trust_env)
        with open(root / "native-stderr.log", "w") as stderr:
            native = subprocess.Popen([str(binary), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=root / "workspace", env=environment, text=True, bufsize=1)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), trust_env=args.trust_env)

        def output():
            for line in native.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        configured = False
        for line in sys.stdin:
            wire = json.loads(line)
            assert wire.get("method") in METHODS, "unapproved app-server method"
            if wire["method"].startswith("plugin/") and not configured:
                path = root / "codex/config.toml"
                contents = path.read_text()
                for name, enabled in [("plugins", args.plugins == "enabled"),
                                      ("plugin_sharing", args.sharing == "enabled")]:
                    assert contents.splitlines().count(name + " = false") == 1
                    contents = contents.replace("\n" + name + " = false\n",
                                                "\n" + name + " = " + str(enabled).lower() + "\n")
                temporary = path.with_suffix(".pending")
                temporary.write_text(contents)
                temporary.replace(path)
                configured = True
                fixture.record("share_requests_configured", plugins=args.plugins, sharing=args.sharing)
            fixture.record("native_input", method=wire["method"])
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if native is not None:
            native.stdin.close()
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
        if reader is not None:
            reader.join(5)
            assert not reader.is_alive(), "owned share output bridge did not stop"
        fixture.close()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--auth", choices=["chatgpt", "none", "apikey"], default="chatgpt")
    parser.add_argument("--trust-env", choices=["CODEX_CA_CERTIFICATE", "SSL_CERT_FILE"], default="CODEX_CA_CERTIFICATE")
    parser.add_argument("--plugins", choices=["enabled", "disabled"], default="enabled")
    parser.add_argument("--sharing", choices=["enabled", "disabled"], default="enabled")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    assert hashlib.sha256(args.codex.resolve(strict=True).read_bytes()).hexdigest() == shared.BINARY_SHA256
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip", "openssl"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
