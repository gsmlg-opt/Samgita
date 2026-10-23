#!/usr/bin/env python3
"""Owned synthetic remote-control dependency around unmodified native Codex.

Only the pinned child writes app-server JSONL. This peer implements fixed
remote-control HTTP routes and the WS handshake/ping/close layer; it never
creates app-server messages or sends relay client_message envelopes.
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
import shlex
import signal
import socket
import sqlite3
import struct
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs, quote, unquote, urlparse


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
ACCESS = "synthetic-owned-remote-control-access"
REFRESH = "synthetic-owned-remote-control-refresh"
API_KEY = "sk-synthetic-owned-remote-control-api"
SERVER_TOKENS = ["synthetic-owned-remote-control-server-v1", "synthetic-owned-remote-control-server-v2"]
PAIRING = "synthetic-owned-remote-pairing"
MANUAL = "SYNTHETIC-MANUAL"
ACCOUNT = "isolated-auth-account"
ENVIRONMENT = "owned-environment"
ENCODED_ENVIRONMENT = "owned/环境 λ"
SERVER = "owned-server"
INSTALLATION = "11111111-2222-4333-8444-555555555555"
EXPIRES = "2036-01-01T00:00:00Z"
PREFIX = "/backend-api/wham/remote/control"
ALLOWED_METHODS = {"initialize", "initialized", "thread/loaded/list",
                   "remoteControl/enable", "remoteControl/disable", "remoteControl/status/read",
                   "remoteControl/pairing/start", "remoteControl/pairing/status",
                   "remoteControl/client/list", "remoteControl/client/revoke"}


def atomic_json(path, value):
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_text(json.dumps(value, ensure_ascii=False))
    pending.replace(path)


def synthetic_token():
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
        "email": "remote-control@synthetic.invalid", "exp": int(time.time()) + 3600,
        "https://api.openai.com/auth": {"chatgpt_account_id": ACCOUNT,
            "chatgpt_user_id": "isolated-auth-user", "chatgpt_plan_type": "pro"}}), "c3ludGhldGlj"])


def isolation(args):
    current = os.readlink("/proc/self/ns/net")
    user = os.readlink("/proc/self/ns/user")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"], timeout=5))
    routes6 = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"], timeout=5))
    assert current != args.parent_netns and user != args.parent_userns, "BLOCKED_ENV: private namespaces required"
    assert os.getuid() == 0 and [row["ifname"] for row in links] == ["lo"], "BLOCKED_ENV: loopback-only namespace required"
    for row in routes + routes6:
        assert row.get("dst") != "default" and row.get("dev") == "lo"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent": args.parent_netns, "child": current, "parent_user": args.parent_userns,
            "child_user": user, "interfaces": ["lo"], "default_route": False, "ipv6_default_route": False}


def frame(payload, opcode):
    size = len(payload)
    assert size <= 125, "Only bounded control frames are authorized"
    return bytes([128 | opcode, size]) + payload


def read_exact(peer, size, closing):
    data = b""
    while len(data) < size and not closing.is_set():
        try:
            chunk = peer.recv(size - len(data))
        except socket.timeout:
            continue
        if not chunk:
            return None
        data += chunk
    return data if len(data) == size else None


def read_frame(peer, closing):
    head = read_exact(peer, 2, closing)
    if head is None:
        return None
    assert head[0] & 128 and head[1] & 128, "Expected a complete masked native frame"
    size = head[1] & 127
    if size in (126, 127):
        count = 2 if size == 126 else 8
        raw = read_exact(peer, count, closing)
        if raw is None:
            return None
        size = struct.unpack("!H" if count == 2 else "!Q", raw)[0]
    assert size <= 1_048_576, "Native frame exceeds owned limit"
    mask = read_exact(peer, 4, closing)
    payload = read_exact(peer, size, closing)
    if mask is None or payload is None:
        return None
    return head[0] & 15, bytes(value ^ mask[index % 4] for index, value in enumerate(payload))


class Fixture:
    def __init__(self, args, proof):
        self.args, self.root = args, args.root
        self.lock, self.closing = threading.RLock(), threading.Event()
        path = self.root / "journal.json"
        self.journal = json.loads(path.read_text()) if path.exists() else {"namespaces": [], "events": []}
        self.generation = 1 + sum(event["event"] == "native_started" for event in self.journal["events"])
        self.journal["namespaces"].append({**proof, "generation": self.generation})
        self.plans, self.peers, self.next_peer = {}, {}, 0
        self.active_token = SERVER_TOKENS[0]
        self.secrets = [ACCESS, REFRESH, API_KEY, PAIRING, MANUAL, *SERVER_TOKENS]
        self.clients = [{"client_id": "owned-phone", "display_name": "Owned λ phone", "device_type": "phone",
                         "platform": "synthetic", "os_version": "1", "device_model": "owned", "app_version": "2",
                         "last_seen_at": "2026-06-14T00:00:00Z"}, {"client_id": "owned/client λ"}]
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = False

            def handle_error(self, _request, _address):
                fixture.record("fixture_error", error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value, raw=None):
                body = (raw.encode() if raw is not None else json.dumps(value, ensure_ascii=False).encode())
                if status == 204:
                    body = b""
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                try:
                    self.wfile.write(body)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def reject(self):
                fixture.record("unexpected_http", method=self.command, path=urlparse(self.path).path)
                self.reply(403, {"error": "unapproved owned operation"})

            def do_GET(self):
                parsed = urlparse(self.path)
                startup = {"/backend-api/wham/config/bundle", "/backend-api/wham/accounts/check", "/backend-api/wham/settings/user"}
                if parsed.path in startup and not parsed.query:
                    body = {}
                    if parsed.path.endswith("/accounts/check"):
                        body = {"accounts": [{"id": ACCOUNT, "workspace_backend_origin": "https://synthetic.invalid",
                                              "account_routing_override": "NO_CONSTRAINT"}]}
                    elif parsed.path.endswith("/settings/user"):
                        body = {"commit_attribution_enabled": False}
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, body)
                elif parsed.path == PREFIX + "/server" and not parsed.query:
                    self.websocket()
                else:
                    self.remote_request()

            def do_POST(self):
                self.remote_request()

            def do_DELETE(self):
                self.remote_request()

            def remote_request(self):
                parsed = urlparse(self.path)
                resource, ids = fixture.route(self.command, parsed.path)
                if resource is None or parsed.fragment:
                    self.reject()
                    return
                if self.headers.get("Transfer-Encoding"):
                    fixture.record("forbidden_body", reason="chunked request")
                    self.reply(413, {})
                    return
                size = int(self.headers.get("Content-Length", "0"))
                if size < 0 or size > 16_384:
                    fixture.record("forbidden_body", reason="unbounded request")
                    self.reply(413, {})
                    return
                body = json.loads(self.rfile.read(size)) if size else None
                query = parse_qs(parsed.query, keep_blank_values=True)
                verified, details = fixture.validate(resource, body, query, ids)
                account = self.headers.get("chatgpt-account-id") == ACCOUNT
                token = fixture.active_token if resource in {"pair", "pair_status"} else ACCESS
                bearer = self.headers.get("Authorization") == "Bearer " + token
                host = self.headers.get("Host") == urlparse(fixture.endpoint).netloc
                content = resource in {"list", "revoke"} or self.headers.get("Content-Type") == "application/json"
                installation = resource not in {"enroll", "refresh"} or self.headers.get("x-codex-installation-id") == INSTALLATION
                selected = fixture.response(resource)
                fixture.record("http", resource=resource, method=self.command, path=parsed.path,
                    query=query, status=selected.get("status", 200), body_verified=verified and content and installation,
                    host_verified=host, account_verified=account, bearer_verified=bearer,
                    bearer_slot=(SERVER_TOKENS.index(token) + 1) if token in SERVER_TOKENS else 0, **details)
                if not (verified and content and installation and host and bearer and (account or resource in {"pair", "pair_status"})):
                    fixture.record("forbidden_body", resource=resource)
                    self.reply(403, {"error": "owned request verification failed"})
                    return
                if selected.get("hold"):
                    deadline = time.monotonic() + 12
                    while not (fixture.root / ("release-" + selected["hold"])).exists():
                        if fixture.closing.wait(0.01):
                            return
                        assert time.monotonic() < deadline, "Owned response release deadline"
                default = fixture.default_response(resource, body, query)
                value = selected.get("body", default)
                if selected.get("body_patch"):
                    value = {**value, **selected["body_patch"]}
                status = selected.get("status", 200)
                if 200 <= status < 300 and resource in {"enroll", "refresh"}:
                    assert value["remote_control_token"] in SERVER_TOKENS
                    fixture.active_token = value["remote_control_token"]
                if 200 <= status < 300 and resource == "revoke":
                    with fixture.lock:
                        fixture.clients = [client for client in fixture.clients if client["client_id"] != ids[1]]
                self.reply(status, value, selected.get("raw_response"))
                fixture.record("response_sent", resource=resource)

            def websocket(self):
                headers = self.headers
                token = fixture.active_token
                valid = (headers.get("Upgrade", "").lower() == "websocket"
                    and headers.get("Sec-WebSocket-Version") == "13"
                    and headers.get("Authorization") == "Bearer " + token
                    and headers.get("Host") == urlparse(fixture.endpoint).netloc
                    and headers.get("x-codex-server-id") == SERVER
                    and headers.get("x-codex-installation-id") == INSTALLATION
                    and headers.get("x-codex-name") == base64.b64encode(socket.gethostname().strip().encode()).decode()
                    and headers.get("x-codex-protocol-version") == "3"
                    and headers.get("x-codex-subscribe-cursor") is None
                    and headers.get("x-codex-host-device-kind") is None)
                fixture.record("http", resource="websocket", method="GET", path=urlparse(self.path).path,
                    status=101 if valid else 403, body_verified=True, host_verified=valid,
                    account_verified=False, bearer_verified=valid, bearer_slot=SERVER_TOKENS.index(token) + 1)
                if not valid:
                    fixture.record("forbidden_websocket", reason="handshake headers")
                    self.reply(403, {})
                    return
                key = headers.get("Sec-WebSocket-Key", "")
                assert len(base64.b64decode(key, validate=True)) == 16
                accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                self.send_response(101)
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", accept)
                self.end_headers()
                self.wfile.flush()
                self.connection.settimeout(0.2)
                with fixture.lock:
                    fixture.next_peer += 1
                    identity = fixture.next_peer
                    fixture.peers[identity] = self.connection
                fixture.record("websocket_connected", connection=identity, headers_verified=valid,
                               bearer_slot=SERVER_TOKENS.index(token) + 1)
                try:
                    while not fixture.closing.is_set():
                        incoming = read_frame(self.connection, fixture.closing)
                        if incoming is None:
                            break
                        opcode, payload = incoming
                        if opcode == 8:
                            self.connection.sendall(frame(payload, 8))
                            break
                        if opcode == 9:
                            self.connection.sendall(frame(payload, 10))
                            fixture.record("websocket_ping", connection=identity)
                        elif opcode != 10:
                            fixture.record("forbidden_websocket", reason="unexpected native data", opcode=opcode)
                            break
                except (ConnectionError, OSError):
                    pass
                finally:
                    with fixture.lock:
                        fixture.peers.pop(identity, None)
                    fixture.record("websocket_closed", connection=identity)
                    self.close_connection = True

            do_PUT = reject
            do_PATCH = reject
            do_HEAD = reject

        # Each generation has its own network namespace; preserving the URL is
        # required to test the native SQLite enrollment lookup across restart.
        self.server = Server(("127.0.0.1", 32145), Handler)
        self.endpoint = "http://127.0.0.1:32145"
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.05), daemon=True)
        self.thread.start()
        self.record("isolation_ready", auth=args.auth)

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, "generation": self.generation, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    @staticmethod
    def route(method, path):
        fixed = {("POST", PREFIX + "/server/enroll"): "enroll",
                 ("POST", PREFIX + "/server/refresh"): "refresh",
                 ("POST", PREFIX + "/server/pair"): "pair",
                 ("POST", PREFIX + "/server/pair/status"): "pair_status"}
        if (method, path) in fixed:
            return fixed[(method, path)], []
        for environment in [ENVIRONMENT, ENCODED_ENVIRONMENT]:
            base = PREFIX + "/environments/" + quote(environment, safe="") + "/clients"
            if method == "GET" and path == base:
                return "list", [environment]
            if method == "DELETE" and path.startswith(base + "/"):
                encoded = path[len(base) + 1:]
                if unquote(encoded) in {"owned-phone", "owned/client λ"} and quote(unquote(encoded), safe="") == encoded:
                    return "revoke", [environment, unquote(encoded)]
        return None, []

    @staticmethod
    def validate(resource, body, query, ids):
        if resource == "enroll":
            expected = {"name": socket.gethostname().strip(), "os": "linux", "arch": "x86_64",
                        "app_server_version": "0.163.0", "installation_id": INSTALLATION}
            return body == expected and not query, {"installation_verified": body == expected}
        if resource == "refresh":
            return body == {"server_id": SERVER, "installation_id": INSTALLATION} and not query, {}
        if resource == "pair":
            valid = isinstance(body, dict) and set(body) == {"manual_code"} and isinstance(body["manual_code"], bool)
            return valid and not query, {"manual_code": body.get("manual_code") if isinstance(body, dict) else None}
        if resource == "pair_status":
            pairing = body == {"pairing_code": PAIRING}
            manual = body == {"manual_pairing_code": MANUAL}
            return (pairing or manual) and not query, {"code_kind": "pairing" if pairing else "manual" if manual else "invalid"}
        valid_query = (set(query) <= {"cursor", "limit", "order"}
            and all(len(values) == 1 for values in query.values())
            and query.get("cursor", ["owned-next"])[0] in {"owned-next", "owned-first λ"}
            and query.get("limit", ["1"])[0] in {str(i) for i in range(1, 101)}
            and query.get("order", ["asc"])[0] in {"asc", "desc"})
        return body is None and (valid_query if resource == "list" else not query), {
            "encoded_path_verified": bool(ids), "environment_id": ids[0]}

    def response(self, resource):
        path = self.root / "responses.json"
        configured = json.loads(path.read_text()) if path.exists() else {}
        state = configured.get(resource)
        if state is None:
            return {}
        with self.lock:
            revision, count = self.plans.get(resource, (None, 0))
            if revision != state["revision"]:
                count = 0
            self.plans[resource] = (state["revision"], count + 1)
            if count >= len(state["replies"]):
                self.record("unexpected_request", resource=resource)
                return {"status": 500, "body": {"error": "owned reply plan exhausted"}}
            return state["replies"][count]

    def default_response(self, resource, body, query):
        if resource in {"enroll", "refresh"}:
            return {"server_id": SERVER, "environment_id": ENVIRONMENT,
                    "remote_control_token": SERVER_TOKENS[resource == "refresh"], "expires_at": EXPIRES}
        if resource == "pair":
            return {"pairing_code": PAIRING, "manual_pairing_code": MANUAL if body["manual_code"] else None,
                    "server_id": SERVER, "environment_id": ENVIRONMENT, "expires_at": EXPIRES}
        if resource == "pair_status":
            return {"claimed": False}
        if resource == "list":
            with self.lock:
                clients = list(self.clients)
            if query.get("cursor") == ["owned-first λ"]:
                return {"items": clients[:1], "cursor": "owned-next"}
            if query.get("cursor") == ["owned-next"]:
                return {"items": clients[1:], "cursor": None}
            return {"items": clients, "cursor": None}
        return {}

    def configure(self):
        codex = self.root / "codex"
        catalog = codex / "models.json"
        atomic_json(catalog, {"models": [{"slug": "mock-model", "display_name": "No inference authorized",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1, "support_verbosity": False,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "truncation_policy": {"mode": "bytes", "limit": 10000}, "experimental_supported_tools": []}]})
        canary = self.root / "command-canary.sh"
        canary.write_text("#!/bin/sh\n: > " + shlex.quote(str(self.root / "forbidden-execution")) + "\nexit 97\n")
        canary.chmod(0o700)
        backend = "ftp://127.0.0.1:32145/backend-api/" if self.args.invalid_url else self.endpoint + "/backend-api/"
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
sqlite_home = {json.dumps(str(codex))}
cli_auth_credentials_store = "file"
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
chatgpt_base_url = "{backend}"
openai_base_url = "{self.endpoint}/v1"
[analytics]
enabled = false
[features]
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
codex_hooks = false
[model_providers.fixture]
name = "Owned remote control, no inference"
base_url = "{self.endpoint}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        installation = codex / "installation_id"
        if not installation.exists():
            installation.write_text(INSTALLATION)
        assert installation.read_text().strip() == INSTALLATION
        if self.args.auth != "no_auth" and not (codex / "auth.json").exists():
            identity = synthetic_token()
            value = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                     "tokens": {"id_token": identity, "access_token": ACCESS,
                                "refresh_token": REFRESH, "account_id": ACCOUNT},
                     "last_refresh": datetime.now(timezone.utc).isoformat()}
            if self.args.auth == "api_key":
                value = {"auth_mode": "apikey", "OPENAI_API_KEY": API_KEY, "tokens": None, "last_refresh": None}
            atomic_json(codex / "auth.json", value)
            (codex / "auth.json").chmod(0o600)
        auth_path = codex / "auth.json"
        if auth_path.exists():
            tokens = json.loads(auth_path.read_text()).get("tokens") or {}
            self.secrets.extend(tokens[key] for key in ["id_token", "access_token", "refresh_token"] if key in tokens)
        environment = {"HOME": str(self.root / "home"), "CODEX_HOME": str(codex), "SHELL": str(canary),
            "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"], "NO_COLOR": "1", "RUST_LOG": "off",
            "NO_PROXY": "*", "no_proxy": "*", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "CODEX_REFRESH_TOKEN_URL_OVERRIDE": self.endpoint + "/forbidden-refresh"}
        launch = self.root / "launch.json"
        if not launch.exists() or json.loads(launch.read_text()).get("force_disabled", True):
            environment["CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED"] = "1"
        return environment

    def close_backend(self):
        self.closing.set()
        with self.lock:
            peers = list(self.peers.values())
        for peer in peers:
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(0.3)
        assert not self.thread.is_alive() and not self.peers, "Owned backend did not stop"

    def snapshot(self):
        path = self.root / "codex" / "state_5.sqlite"
        if not path.exists():
            return [], True
        with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=1) as db:
            db.row_factory = sqlite3.Row
            rows = [dict(row) for row in db.execute("SELECT server_id, environment_id, websocket_url, account_id, app_server_client_name, remote_control_enabled FROM remote_control_enrollments")]
        for row in rows:
            value = row["remote_control_enabled"]
            row["remote_control_enabled"] = None if value is None else bool(value)
        files = [path, Path(str(path) + "-wal"), Path(str(path) + "-shm")]
        tokens_absent = all(not any(secret.encode() in file.read_bytes() for secret in self.secrets)
                            for file in files if file.exists())
        return rows, tokens_absent


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture, native, reader = None, None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args, isolation(args))
        environment = fixture.configure()
        with (args.root / f"native-stderr-{fixture.generation}.log").open("w") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, cwd=args.root / "workspace",
                env=environment, text=True, bufsize=1)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=SHA256,
                       environment_keys=sorted(environment))

        def output():
            for line in native.stdout:
                wire = json.loads(line)
                method = wire.get("method")
                fields = {"method": method, "id": wire.get("id"), "result": "result" in wire, "error": "error" in wire}
                if method == "remoteControl/status/changed":
                    fields["status"] = wire["params"]["status"]
                if method and ("id" in wire or method.startswith(("turn/", "item/", "thread/"))):
                    fixture.record("forbidden_output")
                fixture.record("native_output", **fields)
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        for line in sys.stdin:
            assert len(line.encode()) <= 16_384, "Oversized native input"
            wire = json.loads(line)
            if wire.get("method") not in ALLOWED_METHODS:
                fixture.record("forbidden_native")
                raise AssertionError("Unapproved native method")
            fixture.record("native_input", method=wire["method"], id=wire.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.closing.set()
        if native is not None:
            native.stdin.close()
            try:
                native.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=0.3)
        if reader is not None:
            reader.join(0.3)
            assert not reader.is_alive(), "Owned stdout reader did not stop"
        if fixture is not None:
            fixture.close_backend()
            rows, tokens_absent = fixture.snapshot()
            texts = [(args.root / "journal.json").read_text(),
                     (args.root / f"native-stderr-{fixture.generation}.log").read_text()]
            redacted = all(secret not in text for secret in fixture.secrets for text in texts)
            fixture.record("native_closed", native_reaped=native is not None and native.returncode is not None,
                reader_stopped=reader is not None and not reader.is_alive(), backend_stopped=not fixture.thread.is_alive(),
                enrollments=rows, sqlite_tokens_absent=tokens_absent, redaction_checked=redacted,
                canary_absent=not (args.root / "forbidden-execution").exists())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--auth", required=True, choices=["chatgpt", "no_auth", "api_key"])
    parser.add_argument("--invalid-url", action="store_true")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
    assert all((args.root / name).is_dir() for name in ["home", "codex", "workspace", "tmp"])
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"]), "BLOCKED_ENV: Linux unshare/ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork", "--kill-child=TERM",
            sys.executable, __file__, *sys.argv[1:], "--inside", "--parent-netns", os.readlink("/proc/self/ns/net"),
            "--parent-userns", os.readlink("/proc/self/ns/user")])
    isolated(args)


if __name__ == "__main__":
    main()
