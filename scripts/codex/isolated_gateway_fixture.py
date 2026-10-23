#!/usr/bin/env python3
"""Real pinned gateway OAuth RPCs with an owned, failing loopback issuer.

Only native Codex writes app-server frames. No successful token, credential
store, browser process, provider turn, host bus or external route is available.
"""
import argparse
import base64
import hashlib
from http.client import HTTPConnection
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
from urllib.parse import parse_qs, urlencode, urlparse


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
CANARY = "OWNED_GATEWAY_ISSUER_PRIVATE_CANARY"
CHANGED = "account/gatewayOAuth/changed"
MAX_WIRE = 262_144
ALLOWED = {"initialize", "initialized", "account/gatewayOAuth/read",
           "account/gatewayOAuth/login", "account/gatewayOAuth/cancel", "model/list"}


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


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
        self.challenge, self.redirect = None, None
        self.handoffs, self.exchanges = 0, 0
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
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, body):
                wire = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(wire)))
                self.send_header("X-Request-ID", CANARY)
                self.end_headers()
                self.wfile.write(wire)

            def do_GET(self):
                fixture.record("unexpected_http", method="GET", path=urlparse(self.path).path)
                self.reply(404, {})

            def do_POST(self):
                try:
                    assert args.scenario == "token-failure" and self.path == "/token"
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 8192
                    assert self.headers.get("Authorization") is None
                    assert self.headers.get("ChatGPT-Account-ID") is None
                    assert self.headers.get("Host") == f"127.0.0.1:{fixture.server.server_port}"
                    assert self.headers.get_content_type() == "application/x-www-form-urlencoded"
                    form = parse_qs(self.rfile.read(size).decode(), keep_blank_values=True)
                    assert form["grant_type"] == ["authorization_code"]
                    assert form["code"] == ["owned-accepted-code"]
                    assert form["client_id"] == ["owned-gateway-client"]
                    assert form["redirect_uri"] == [fixture.redirect]
                    assert set(form) == {"grant_type", "code", "client_id", "redirect_uri", "code_verifier"}
                    challenge = base64.urlsafe_b64encode(hashlib.sha256(
                        form["code_verifier"][0].encode()).digest()).decode().rstrip("=")
                    assert challenge == fixture.challenge
                    fixture.exchanges += 1
                    assert fixture.exchanges == 1
                    fixture.record("token_exchange", pkce_verified=True, body_verified=True,
                                   authorization_absent=True, host_verified=True)
                    self.reply(400, {"error": "invalid_grant", "error_description": CANARY})
                except (BrokenPipeError, ConnectionResetError):
                    fixture.record("peer_closed")
                except Exception as error:
                    fixture.record("fixture_error", stage="token", error_type=type(error).__name__)
                    self.reply(400, {})

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 160
            self.journal["events"].append({"event": event, **fields})
            write_json(self.args.root / "journal.json", self.journal)

    def native_output(self, value):
        params = value.get("params", {})
        url = params.get("authUrl") if value.get("method") == CHANGED else None
        if not url:
            assert CANARY not in json.dumps(value)
            return
        assert self.args.scenario in ["cancel", "token-failure"]
        assert params == {"providerId": "gateway", "status": "started", "authUrl": url, "error": None}
        parsed = urlparse(url)
        assert parsed.scheme == "http" and parsed.netloc == f"127.0.0.1:{self.server.server_port}"
        assert parsed.path == "/authorize" and not parsed.fragment
        query = parse_qs(parsed.query, keep_blank_values=True)
        assert query["issuer_secret"] == [CANARY]
        assert query["client_id"] == ["owned-gateway-client"]
        assert query["response_type"] == ["code"] and query["code_challenge_method"] == ["S256"]
        self.redirect, self.challenge = query["redirect_uri"][0], query["code_challenge"][0]
        callback = urlparse(self.redirect)
        assert callback.scheme == "http" and callback.hostname == "127.0.0.1"
        assert callback.port and not callback.username and not callback.password
        assert callback.path == "/callback" and not callback.query and not callback.fragment
        assert len(query["state"][0]) >= 16
        self.handoffs += 1
        assert self.handoffs <= (2 if self.args.scenario == "cancel" else 1)
        self.record("auth_handoff", index=self.handoffs, native_callback_verified=True)
        if self.args.scenario == "token-failure":
            callback_path = callback.path + "?" + urlencode({
                "code": "owned-accepted-code", "state": query["state"][0]})
            connection = HTTPConnection("127.0.0.1", callback.port, timeout=5)
            connection.connect()
            peer = connection.sock
            with self.lock:
                if self.closing.is_set():
                    connection.close()
                    return
                self.peer_sockets.add(peer)
            try:
                connection.request("GET", callback_path)
                response = connection.getresponse()
                assert response.status == 200
                assert len(response.read(65537)) <= 65536
            finally:
                with self.lock:
                    self.peer_sockets.discard(peer)
                connection.close()
            self.record("native_callback", status=200, state_from_native=True)


def configure(args, endpoint):
    gateway = "" if args.scenario == "no-gateway" else f'''
[model_providers.gateway.gateway_oauth]
authorization_url = "{endpoint}/authorize?issuer_secret={CANARY}"
token_url = "{endpoint}/token"
client_id = "owned-gateway-client"
delivery = {{ kind = "header", name = "X-Gateway-Authorization" }}
'''
    (args.root / "codex/config.toml").write_text(f'''model_provider = "gateway"
model = "mock-model"
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
[analytics]
enabled = false
[features]
secret_auth_storage = true
apps = false
plugins = false
hooks = false
recommended_plugins = false
shell_snapshot = false
shell_tool = false
unified_exec = false
[model_providers.gateway]
name = "Owned gateway"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = {str(args.scenario == "primary-required").lower()}
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
{gateway}''')


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = Fixture(args, isolation(args.parent_netns))
    fixture.thread.start()
    configure(args, f"http://127.0.0.1:{fixture.server.server_port}")
    native, reader = None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        environment = {"HOME": str(args.root / "home"), "CODEX_HOME": str(args.root / "codex"),
            "TMPDIR": str(args.root / "tmp"), "PATH": os.environ["PATH"],
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
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
                    value = json.loads(line)
                    # Forward the real handoff before driving its real callback.
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
                    fixture.native_output(value)
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 30 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            value = json.loads(line)
            assert value.get("method") in ALLOWED
            method, params = value["method"], value.get("params")
            if method == "initialize":
                capabilities = params["capabilities"]
                assert capabilities.get("explicitGatewayOauth") is True
                assert capabilities.get("experimentalApi", False) is False
                assert capabilities.get("optOutNotificationMethods", []) == (
                    [CHANGED] if args.scenario == "opt-out" else [])
            elif method == "model/list":
                assert args.scenario == "cancel" and params == {}
            else:
                assert params is None
            fixture.record("native_input", method=method, id=value.get("id"))
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
        checked = [(args.root / name).read_bytes() for name in ["native-stderr.log", "journal.json"]]
        fixture.record("secret_scan", passed=all(CANARY.encode() not in data for data in checked))
        assert not (args.root / "codex/secrets/gateway_oauth.age").exists()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True,
                        choices=["no-gateway", "primary-required", "opt-out", "cancel", "token-failure"])
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
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
