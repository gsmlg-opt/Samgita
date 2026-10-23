#!/usr/bin/env python3
"""Owned authenticated metadata and HTTPS bundles for immutable native Codex.

No app-server messages are synthesized. No model, hook or MCP execution route is
provided. All network interfaces and destinations are inside a private netns.
"""
import argparse
from datetime import datetime, timezone
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
from urllib.parse import parse_qs, unquote, urlparse

from isolated_auth_fixture import token

BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
ACCESS_TOKEN = "synthetic-remote-plugin-access"
ACCOUNT_ID = "isolated-auth-account"
REMOTE_ID = "plugins~Plugin_fixture_remote"
ALLOWED_METHODS = {"initialize", "initialized", "thread/loaded/list",
                   "plugin/skill/read", "plugin/reconcile"}


def atomic_json(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def generate_certificates(root):
    tls = root / "tls"
    tls.mkdir(exist_ok=True)
    if (tls / "server.pem").exists():
        return
    commands = [
        ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
         "-subj", "/CN=Owned synthetic remote plugin CA", "-addext", "basicConstraints=critical,CA:TRUE",
         "-keyout", str(tls / "ca.key"), "-out", str(tls / "ca.pem")],
        ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
         "-subj", "/CN=127.0.0.1", "-keyout", str(tls / "server.key"),
         "-out", str(tls / "server.csr")],
        ["x509", "-req", "-in", str(tls / "server.csr"), "-CA", str(tls / "ca.pem"),
         "-CAkey", str(tls / "ca.key"), "-CAcreateserial", "-days", "1", "-sha256",
         "-extfile", str(tls / "extensions.cnf"), "-out", str(tls / "server.pem")],
    ]
    (tls / "extensions.cnf").write_text(
        "subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
    for command in commands:
        subprocess.run(["openssl", *command], check=True, timeout=15,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for key in tls.glob("*.key"):
        key.chmod(0o600)


def bundle_bytes(spec):
    if spec.get("invalid_archive"):
        return b"synthetic-not-a-gzip-archive"
    name = spec.get("name", "fixture-remote")
    marker = spec.get("marker", "synthetic-first-bundle")
    files = {".codex-plugin/plugin.json": json.dumps({"name": name}), "marker.txt": marker}
    capabilities = spec.get("capabilities", ["skills"])
    if "skills" in capabilities:
        files["skills/inspect/SKILL.md"] = "---\nname: inspect\ndescription: Synthetic remote metadata\n---\nOwned synthetic skill\n"
    if "mcps" in capabilities:
        files[".mcp.json"] = json.dumps({"mcpServers": {"synthetic": {
            "command": "/nonexistent/samgita-disabled-fixture", "enabled": False}}})
    if "apps" in capabilities:
        files[".app.json"] = json.dumps({"apps": {"synthetic": {"id": "connector_synthetic"}}})
    if "hooks" in capabilities:
        files["hooks/hooks.json"] = json.dumps({"hooks": {"UserPromptSubmit": [{"hooks": [{
            "type": "command", "command": "/nonexistent/samgita-disabled-fixture"}]}]}})
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for path, value in files.items():
            # No traversal/symlink/hardlink fixture is admitted by this bounded profile.
            assert not Path(path).is_absolute() and ".." not in Path(path).parts
            body = value.encode()
            entry = tarfile.TarInfo(path)
            entry.mode, entry.size = 0o644, len(body)
            archive.addfile(entry, io.BytesIO(body))
    return output.getvalue()


class Fixture:
    def __init__(self, root, namespace):
        self.root = root
        self.lock = threading.Lock()
        journal = root / "journal.json"
        self.journal = json.loads(journal.read_text()) if journal.exists() else {"events": []}
        self.journal["namespace"] = namespace
        fixture = self

        class Server(ThreadingHTTPServer):
            # server_close joins owned request threads; each connection is bounded.
            daemon_threads = False

            def handle_error(self, _request, _client):
                fixture.record("fixture_error", stage="http-handler", error=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def send_bytes(self, status, body, content_type="application/json"):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
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

            def reply(self, status, value):
                self.send_bytes(status, json.dumps(value).encode())

            def do_GET(self):
                parsed = urlparse(self.path)
                state = json.loads((fixture.root / "remote-state.json").read_text())
                if parsed.path.startswith("/bundles/"):
                    self.bundle(parsed, state)
                elif parsed.path in {"/backend-api/ps/plugins/installed",
                                     f"/backend-api/ps/plugins/{REMOTE_ID}/skills/inspect"}:
                    self.plugin(parsed, state)
                elif parsed.path in {"/backend-api/wham/config/bundle",
                                      "/backend-api/wham/accounts/check", "/backend-api/wham/settings/user"}:
                    body = {"accounts": [{"id": ACCOUNT_ID,
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]} if parsed.path.endswith("accounts/check") else {}
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, body)
                else:
                    fixture.record("forbidden_http", method="GET", path=parsed.path)
                    self.reply(404, {"error": "forbidden synthetic route"})

            def plugin(self, parsed, state):
                bearer = self.headers.get("Authorization") == f"Bearer {ACCESS_TOKEN}"
                account = self.headers.get("chatgpt-account-id") == ACCOUNT_ID
                resource = "installed" if parsed.path.endswith("/installed") else "skill"
                selected = state[resource]
                status = selected.get("status", 200)
                fixture.record(resource, path=parsed.path, query=parse_qs(parsed.query),
                               status=status, bearer_verified=bearer, account_verified=account)
                if not (bearer and account):
                    self.reply(401, {"error": "synthetic header mismatch"})
                elif status != 200:
                    self.reply(status, {"error": "synthetic backend failure"})
                elif "raw" in selected:
                    self.send_bytes(200, selected["raw"].encode())
                elif resource == "skill":
                    self.reply(200, selected["body"])
                else:
                    rows = [fixture.installed(row) for row in selected.get("plugins", [])]
                    self.reply(200, {"plugins": rows, "pagination": {"next_page_token": None}})

            def bundle(self, parsed, state):
                assert isinstance(self.connection, ssl.SSLSocket), "bundles must use HTTPS"
                key = unquote(parsed.path.removeprefix("/bundles/"))
                spec = state["bundles"][key]
                status = spec.get("status", 200)
                fixture.record("bundle", key=key, status=status, tls_version=self.connection.version(),
                               authorization_absent=self.headers.get("Authorization") is None,
                               account_absent=self.headers.get("chatgpt-account-id") is None)
                self.send_bytes(status, bundle_bytes(spec) if status == 200 else b"synthetic bundle failure", "application/gzip")

            def do_POST(self):
                fixture.record("forbidden_http", method="POST", path=urlparse(self.path).path)
                self.reply(405, {"error": "no model or mutation endpoint"})

        self.backend = Server(("127.0.0.1", 0), Handler)
        self.bundles = Server(("127.0.0.1", 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(root / "tls/server.pem", root / "tls/server.key")
        self.bundles.socket = tls.wrap_socket(self.bundles.socket, server_side=True)
        self.threads = []
        for server in [self.backend, self.bundles]:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    def installed(self, row):
        release = {"version": row.get("version", "1.0.0"), "display_name": "Synthetic plugin",
                   "description": "Owned metadata only", "interface": {},
                   "bundle_download_url": f"https://127.0.0.1:{self.bundles.server_port}/bundles/{row.get('bundle', 'first')}"}
        release.update(row.get("release", {}))
        return {"id": row.get("id", REMOTE_ID), "name": row.get("name", "fixture-remote"),
                "scope": "GLOBAL", "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
                "release": release, "enabled": row.get("enabled", True)}

    def configure(self, auth, trust_env):
        codex = self.root / "codex"
        endpoint = f"http://127.0.0.1:{self.backend.server_port}"
        catalog = codex / "catalog.json"
        atomic_json(catalog, {"models": [{"slug": "mock-model", "display_name": "Metadata only",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No model turns in this fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "{endpoint}/backend-api"
openai_base_url = "{endpoint}/v1"
[features]
plugins = false
remote_plugin = false
plugin_sharing = false
apps = false
codex_hooks = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "No-inference owned fixture"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        auth_path = codex / "auth.json"
        if auth == "none":
            auth_path.unlink(missing_ok=True)
        else:
            credentials = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                "tokens": {"id_token": token(), "access_token": ACCESS_TOKEN,
                           "refresh_token": "synthetic-remote-plugin-refresh", "account_id": ACCOUNT_ID},
                "last_refresh": datetime.now(timezone.utc).isoformat()}
            if auth == "apikey":
                credentials = {"auth_mode": "apikey", "OPENAI_API_KEY": "sk-synthetic-plugin-only"}
            atomic_json(auth_path, credentials)
            auth_path.chmod(0o600)
        self.record("plugin_startup_disabled")
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(codex),
                "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"],
                "NO_COLOR": "1", "RUST_LOG": "off", "NO_PROXY": "*", "no_proxy": "*",
                "CODEX_DISABLE_REMOTE_CONTROL": "1", "CODEX_REFRESH_TOKEN_URL_OVERRIDE": endpoint + "/forbidden-refresh",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
                trust_env: str(self.root / "tls/ca.pem")}

    def close(self):
        for server in [self.backend, self.bundles]:
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(5)
            assert not thread.is_alive(), "owned HTTP/TLS peer did not stop"


def isolated(args):
    root, binary = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == BINARY_SHA256
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    namespace = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert namespace != args.parent_netns and [link["ifname"] for link in links] == ["lo"]
    assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
    generate_certificates(root)
    fixture = Fixture(root, {"parent": args.parent_netns, "child": namespace,
                             "interfaces": ["lo"], "default_route": False})
    native, reader = None, None
    plugins_enabled = False

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        environment = fixture.configure(args.auth, args.trust_env)
        with open(root / "native-stderr.log", "w") as stderr:
            native = subprocess.Popen([str(binary), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=root / "workspace", env=environment, text=True, bufsize=1)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), trust_env=args.trust_env,
                       trust_file=str(root / "tls/ca.pem"))

        def output():
            for line in native.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        for line in sys.stdin:
            wire = json.loads(line)
            assert wire.get("method") in ALLOWED_METHODS, "unapproved app-server method"
            if wire["method"].startswith("plugin/") and not plugins_enabled:
                # Native initialization has completed. Per-request config reload sees
                # the enabled feature, without racing the startup materializer.
                path = root / "codex/config.toml"
                contents = path.read_text()
                assert contents.splitlines().count("plugins = false") == 1
                temporary = path.with_suffix(".pending")
                temporary.write_text(contents.replace("\nplugins = false\n", "\nplugins = true\n"))
                temporary.replace(path)
                plugins_enabled = True
                fixture.record("plugin_requests_enabled", before_method=wire["method"])
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
            assert not reader.is_alive(), "owned output bridge did not stop"
        fixture.close()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--auth", choices=["chatgpt", "none", "apikey"], default="chatgpt")
    parser.add_argument("--trust-env", choices=["CODEX_CA_CERTIFICATE", "SSL_CERT_FILE"], default="CODEX_CA_CERTIFICATE")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    assert hashlib.sha256(args.codex.resolve(strict=True).read_bytes()).hexdigest() == BINARY_SHA256
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip", "openssl"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
