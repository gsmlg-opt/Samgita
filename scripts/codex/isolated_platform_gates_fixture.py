#!/usr/bin/env python3
"""Owned Linux gates around stock Codex; only native Codex emits RPC frames.

No turns, commands, host credentials, browser, system configuration or external
routes are available. A loopback HTTP dependency denies every request.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
REFRESH = "owned-platform-synthetic-refresh"
ACCOUNT = "owned-platform-account"
MEMBERSHIP = "owned-platform-account-user"
MAX_WIRE = 262_144
VERIFY = {"challenge": "AQ", "title": "Owned verification probe", "description": ""}
ALLOWED = {"initialize", "initialized", "userVerification/status",
           "userVerification/enroll", "userVerification/delete", "userVerification/verify",
           "userVerification/cancel", "windowsSandbox/readiness", "windowsSandbox/setupStart"}


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def synthetic_token(access):
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    claims = {"chatgpt_account_id": ACCOUNT, "chatgpt_user_id": "owned-platform-user",
              "chatgpt_plan_type": "pro"}
    if access:
        claims["chatgpt_account_user_id"] = MEMBERSHIP
    return ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
        "email": "platform@synthetic.invalid", "exp": int(time.time()) + 3600,
        "https://api.openai.com/auth": claims}), "c3ludGhldGlj"])


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes += json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent and [link["ifname"] for link in links] == ["lo"]
    for route in routes:
        assert route.get("dev") == "lo" and route.get("dst") != "default"
        assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback
    return {"parent": parent, "child": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


class Fixture:
    def __init__(self, args, proof):
        self.args, self.lock = args, threading.RLock()
        self.journal = {"namespace": proof, "events": []}
        self.closing = threading.Event()
        self.peer_sockets, self.peer_threads = set(), set()
        self.secrets = [REFRESH]
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            block_on_close = False

            def process_request_thread(self, request, client_address):
                worker = threading.current_thread()
                with fixture.lock:
                    if fixture.closing.is_set():
                        request.close()
                        return
                    fixture.peer_sockets.add(request)
                    fixture.peer_threads.add(worker)
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    with fixture.lock:
                        fixture.peer_sockets.discard(request)
                        fixture.peer_threads.discard(worker)

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="http-worker",
                                   error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(0.25)

            def log_message(self, *_args):
                pass

            def deny(self):
                known = {"/api/codex/config/bundle", "/api/codex/accounts/check",
                         "/api/codex/settings/user"}
                path = urlparse(self.path).path
                # Never persist headers, queries, bodies or unapproved path text.
                fixture.record("http_denied", method=self.command, status=403,
                               path=path if path in known else "[unapproved]")
                body = b'{"error":"owned fixture denies all HTTP"}'
                self.send_response(403)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            do_GET = deny
            do_POST = deny
            do_PUT = deny
            do_PATCH = deny
            do_DELETE = deny
            do_HEAD = deny
            do_OPTIONS = deny
            do_CONNECT = deny

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 200
            self.journal["events"].append({"event": event, **fields})
            write_json(self.args.root / "journal.json", self.journal)

    def configure(self):
        root, codex = self.args.root, self.args.root / "codex"
        endpoint = f"http://127.0.0.1:{self.server.server_port}"
        catalog = codex / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "No inference authorized",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
chatgpt_base_url = "{endpoint}"
openai_base_url = "{endpoint}/v1"
[analytics]
enabled = false
[features]
apps = false
plugins = false
hooks = false
recommended_plugins = false
shell_snapshot = false
shell_tool = false
unified_exec = false
[model_providers.fixture]
name = "Owned platform gates, no inference"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        if self.args.auth == "synthetic":
            identity, access = synthetic_token(False), synthetic_token(True)
            self.secrets += [identity, access]
            write_json(codex / "auth.json", {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                "tokens": {"id_token": identity, "access_token": access,
                           "refresh_token": REFRESH, "account_id": ACCOUNT},
                "last_refresh": datetime.now(timezone.utc).isoformat()})
            (codex / "auth.json").chmod(0o600)
        self.config_bytes = (codex / "config.toml").read_bytes()
        self.auth_bytes = (codex / "auth.json").read_bytes() if self.args.auth == "synthetic" else None
        self.record("configuration_ready", auth=self.args.auth,
                    selected_workspace_claim_matches=self.args.auth == "synthetic",
                    access_account_user_claim_present=self.args.auth == "synthetic")
        return {"HOME": str(root / "home"), "CODEX_HOME": str(codex),
            "TMPDIR": str(root / "tmp"), "PATH": os.environ["PATH"],
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "CODEX_REFRESH_TOKEN_URL_OVERRIDE": endpoint + "/forbidden-refresh",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}

    def validate_input(self, value):
        assert set(value) <= {"id", "method", "params", "jsonrpc"}
        method, params = value.get("method"), value.get("params")
        assert method in ALLOWED
        if "id" in value:
            request_id = value["id"]
            assert request_id == 100 or (
                isinstance(request_id, str) and request_id.startswith("owned-platform-")
                and len(request_id) <= 80)
        if method == "initialize":
            assert params["clientInfo"] == {"name": "samgita_platform_gates", "version": "1"}
            assert params["capabilities"] == {"experimentalApi": self.args.experimental == "yes"}
            assert set(params) == {"clientInfo", "capabilities"}
        elif method in {"initialized", "windowsSandbox/readiness"}:
            assert params is None
        elif method == "userVerification/cancel":
            assert params in [{"requestId": 100}, {"requestId": "100"}, {"requestId": 404}]
        elif method == "userVerification/verify":
            assert params in [VERIFY, {**VERIFY, "challenge": "!"}, {**VERIFY, "challenge": "AQ=="}]
        elif method == "windowsSandbox/setupStart":
            assert params in [{"mode": "elevated"}, {"mode": "unelevated"}]
        else:
            assert params == {}


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = Fixture(args, isolation(args.parent_netns))
    fixture.thread.start()
    native, reader = None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        environment = fixture.configure()
        with (args.root / "native-stderr.log").open("wb") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=SHA256,
                       inherited_host_credentials=False, inherited_host_bus=False)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n")
                    assert all(secret.encode() not in line for secret in fixture.secrets)
                    value = json.loads(line)
                    if "error" in value:
                        # Fixed synthetic inputs only; retain no error.data or credentials.
                        error = value["error"]
                        fixture.record("native_error", code=error["code"], message=error["message"])
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 64 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            value = json.loads(line)
            fixture.validate_input(value)
            fixture.record("native_input", method=value["method"], id=value.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        deadline = time.monotonic() + 0.75

        def remaining(cap):
            return max(0.0, min(cap, deadline - time.monotonic()))

        fixture.closing.set()
        with fixture.lock:
            peers = list(fixture.peer_sockets)
        for peer in peers:
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        fixture.server.shutdown()
        fixture.server.server_close()
        if native is not None:
            try:
                native.stdin.close()
            except OSError:
                pass
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=remaining(0.25))
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=remaining(0.15))
        if reader:
            reader.join(remaining(0.15))
            assert not reader.is_alive()
        with fixture.lock:
            workers = list(fixture.peer_threads)
        for worker in workers:
            worker.join(remaining(0.1))
            assert not worker.is_alive()
        fixture.thread.join(remaining(0.1))
        assert not fixture.thread.is_alive()
        codex = args.root / "codex"
        assert (codex / "config.toml").read_bytes() == fixture.config_bytes
        if fixture.auth_bytes is None:
            assert not (codex / "auth.json").exists()
        else:
            assert (codex / "auth.json").read_bytes() == fixture.auth_bytes
        fixture.record("configuration_unchanged", config_bytes=True, auth_bytes=True)
        checked = [(args.root / name).read_bytes() for name in ["native-stderr.log", "journal.json"]]
        clean = all(secret.encode() not in data for secret in fixture.secrets for data in checked)
        fixture.record("secret_scan", passed=clean)
        assert clean
        assert time.monotonic() <= deadline, "owned cleanup exceeded 0.75 second total budget"
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--auth", required=True, choices=["none", "synthetic"])
    parser.add_argument("--experimental", required=True, choices=["yes", "no"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
    assert all((args.root / name).is_dir() and not (args.root / name).is_symlink()
               for name in ["home", "codex", "workspace", "tmp"])
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter fixture"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, "-I", __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
