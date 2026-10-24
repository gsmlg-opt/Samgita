#!/usr/bin/env python3
"""Owned isolated MCP/OAuth/gateway around pinned native Codex.

No app-server response is synthesized. The only HTTP routes are fixed synthetic
OAuth, inventory and hosted-Apps MCP routes inside a private network namespace.
The stdin control protocol cannot execute commands or fetch arbitrary URLs.
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
import queue
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
ACCESS = "synthetic-owned-apps-access"
OAUTH_ACCESS = "synthetic-owned-mcp-oauth-access"
ACCOUNT = "isolated-auth-account"
CLIENT = "owned-mcp-client"
EVENT_PATH = "/api/codex/ps/mcp"
CALLBACK_PATH = "/callback/owned-mcp"
PROFILES = {"status", "oauth", "events"}
MCP_PATHS = {"/inventory/a", "/inventory/b", "/inventory/b-v2", "/oauth/mcp", EVENT_PATH}
AUTH_METADATA = {"/.well-known/oauth-authorization-server/oauth/mcp",
                 "/oauth/mcp/.well-known/oauth-authorization-server",
                 "/.well-known/oauth-authorization-server"}
RESOURCE_METADATA = {"/.well-known/oauth-protected-resource/oauth/mcp",
                     "/oauth/mcp/.well-known/oauth-protected-resource"}
STARTUP_PATHS = {"/api/codex/wham/config/bundle", "/api/codex/wham/accounts/check",
                 "/api/codex/wham/settings/user"}


def atomic_json(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value, ensure_ascii=False))
    temporary.replace(path)


def encoded(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")


def synthetic_id_token():
    return ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
        "email": "owned-mcp@synthetic.invalid", "exp": int(time.time()) + 3600,
        "https://api.openai.com/auth": {"chatgpt_account_id": ACCOUNT,
            "chatgpt_user_id": "isolated-auth-user", "chatgpt_plan_type": "pro"}}), "c3ludGhldGlj"])


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"], timeout=5))
    routes6 = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent and [row["ifname"] for row in links] == ["lo"]
    for row in routes + routes6:
        assert row.get("dst") != "default" and row.get("dev") == "lo"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent_namespace": parent, "namespace": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args):
        return None


class Fixture:
    def __init__(self, root, binary, profile, proof):
        self.root, self.binary, self.profile, self.proof = root, binary, profile, proof
        self.lock, self.closing = threading.RLock(), threading.Event()
        self.closed = False
        self.journal = {"events": []}
        self.streams, self.next_stream = {}, 0
        self.authorization, self.callback = None, None
        self.native, self.native_pids, self.generation = None, [], 1
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

            def reply(self, status, value, headers=None):
                body = json.dumps(value, ensure_ascii=False).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def do_GET(self):
                path = urlparse(self.path).path
                if path in AUTH_METADATA:
                    fixture.record("oauth_metadata", path=path)
                    self.reply(200, {"issuer": fixture.oauth_url,
                        "authorization_endpoint": fixture.endpoint + "/oauth/authorize",
                        "token_endpoint": fixture.endpoint + "/oauth/token",
                        "authorization_response_iss_parameter_supported": True,
                        "response_types_supported": ["code"],
                        "grant_types_supported": ["authorization_code"],
                        "code_challenge_methods_supported": ["S256"],
                        "token_endpoint_auth_methods_supported": ["none"],
                        "scopes_supported": ["read:owned", "inspect:owned"]})
                elif path in RESOURCE_METADATA:
                    fixture.record("resource_metadata", path=path)
                    self.reply(200, {"resource": fixture.oauth_url,
                        "authorization_servers": [fixture.oauth_url],
                        "scopes_supported": ["read:owned", "inspect:owned"]})
                elif path in STARTUP_PATHS:
                    fixture.record("startup_metadata", path=path)
                    body = {"accounts": [{"id": ACCOUNT,
                        "workspace_backend_origin": "https://synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]} if path.endswith("accounts/check") else {}
                    self.reply(200, body)
                elif path in MCP_PATHS:
                    # Streamable HTTP's optional independent GET stream is unsupported.
                    fixture.record("mcp_get", path=path)
                    self.reply(405, {"error": "only owned POST streams are supported"})
                else:
                    fixture.record("forbidden_http", method="GET", path=path)
                    self.reply(404, {"error": "unapproved owned route"})

            def do_DELETE(self):
                path = urlparse(self.path).path
                if path in MCP_PATHS:
                    fixture.record("mcp_delete", path=path)
                    self.reply(405, {})
                else:
                    fixture.record("forbidden_http", method="DELETE", path=path)
                    self.reply(404, {})

            def do_POST(self):
                path = urlparse(self.path).path
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65_536:
                    fixture.record("forbidden_body", path=path)
                    self.reply(413, {})
                    return
                body = self.rfile.read(size)
                if path == "/oauth/token":
                    self.token(body)
                elif path in MCP_PATHS:
                    self.mcp(path, json.loads(body))
                else:
                    fixture.record("forbidden_http", method="POST", path=path)
                    self.reply(404, {"error": "no inference or command route"})

            def token(self, body):
                values = parse_qs(body.decode(), strict_parsing=True)
                with fixture.lock:
                    auth = fixture.authorization
                    assert auth is not None, "token exchange without owned callback"
                    assert values.get("grant_type") == ["authorization_code"]
                    assert values.get("client_id") == [CLIENT]
                    assert values.get("code") == ["owned-code"]
                    assert values.get("redirect_uri") == [auth["redirect_uri"]]
                    verifier = values["code_verifier"][0]
                    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
                    assert challenge == auth["code_challenge"]
                    fixture.record("token_exchange", client_verified=True, redirect_verified=True,
                                   pkce_verified=True, accepted=True)
                self.reply(200, {"access_token": OAUTH_ACCESS, "token_type": "Bearer",
                                 "scope": "read:owned inspect:owned"})

            def mcp(self, path, message):
                method, identity = message.get("method"), message.get("id")
                oauth_bearer = self.headers.get("Authorization") == "Bearer " + OAUTH_ACCESS
                apps_bearer = self.headers.get("Authorization") == "Bearer " + ACCESS
                inventory_bearer = self.headers.get("Authorization") == "Bearer synthetic-owned-inventory"
                fixture.record("mcp", path=path, method=method, id=identity,
                    params=message.get("params"), session=self.headers.get("Mcp-Session-Id"),
                    oauth_bearer_verified=oauth_bearer, apps_bearer_verified=apps_bearer,
                    inventory_bearer_verified=inventory_bearer,
                    account_verified=self.headers.get("ChatGPT-Account-ID") == ACCOUNT)
                if path == "/oauth/mcp" and not oauth_bearer:
                    self.reply(401, {"error": "synthetic OAuth required"}, {
                        "WWW-Authenticate": 'Bearer resource_metadata="' + fixture.endpoint +
                        '/.well-known/oauth-protected-resource/oauth/mcp"'})
                    return
                if path == EVENT_PATH:
                    # Native intentionally withholds ambient ChatGPT auth from
                    # untrusted HTTP origins, including this owned loopback peer.
                    assert self.headers.get("Authorization") is None, "unexpected loopback authorization"
                    assert self.headers.get("ChatGPT-Account-ID") is None, "unexpected loopback account"
                elif path.startswith("/inventory/"):
                    assert inventory_bearer, "synthetic inventory bearer missing"
                if method == "events/stream":
                    assert path == EVENT_PATH and fixture.profile == "events"
                    self.stream(message)
                    return
                if identity is None:
                    if method == "notifications/cancelled":
                        cancelled = message.get("params", {}).get("requestId")
                        with fixture.lock:
                            for stream in fixture.streams.values():
                                if stream["request_id"] == cancelled:
                                    stream["cancelled"].set()
                                    fixture.record("stream_cancelled", stream=stream["number"],
                                                   request_id=cancelled)
                    else:
                        assert method == "notifications/initialized", "unapproved MCP notification"
                    self.reply(202, {})
                    return
                if method == "initialize":
                    label = path.rsplit("/", 1)[-1]
                    result = {"protocolVersion": "2025-06-18", "capabilities": fixture.capabilities(label),
                        "serverInfo": {"name": "owned-" + label, "version": "1.0.0",
                            "title": "Owned " + label, "description": "Synthetic inventory λ",
                            "websiteUrl": "https://synthetic.invalid/owned"}}
                    self.reply(200, {"jsonrpc": "2.0", "id": identity, "result": result},
                               {"Mcp-Session-Id": "owned-session-" + label})
                    return
                label = path.rsplit("/", 1)[-1]
                if method == "tools/list":
                    result = {"tools": [fixture.tool(label)] if path != EVENT_PATH else []}
                elif method == "resources/list":
                    result = {"resources": [{"uri": "fixture://" + label, "name": "Owned " + label,
                                             "mimeType": "text/plain", "description": "Owned resource"}]}
                elif method == "resources/templates/list":
                    result = {"resourceTemplates": [{"uriTemplate": "fixture://" + label + "/{key}",
                                "name": "Owned template " + label, "mimeType": "text/plain"}]}
                elif method == "ping":
                    result = {}
                else:
                    fixture.record("forbidden_mcp", path=path, method=method)
                    self.reply(200, {"jsonrpc": "2.0", "id": identity,
                                    "error": {"code": -32601, "message": "no execution route"}})
                    return
                self.reply(200, {"jsonrpc": "2.0", "id": identity, "result": result})

            def stream(self, message):
                with fixture.lock:
                    fixture.next_stream += 1
                    number = fixture.next_stream
                    stream = {"number": number, "request_id": message["id"],
                        "queue": queue.Queue(maxsize=16), "cancelled": threading.Event(),
                        "closed": threading.Event()}
                    fixture.streams[number] = stream
                    fixture.record("stream_opened", stream=number, request_id=message["id"],
                                   params=message.get("params"))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.flush()
                deadline = time.monotonic() + 45
                try:
                    while not fixture.closing.is_set() and not stream["cancelled"].is_set():
                        assert time.monotonic() < deadline, "owned stream fixture deadline"
                        # The pinned native HTTP adapter intercepts cancellation
                        # locally and drops this response instead of POSTing it.
                        # Peek only: never consume any bytes from the peer.
                        try:
                            readable, _, _ = select.select([self.connection], [], [], 0)
                            if readable and self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b"":
                                stream["cancelled"].set()
                                fixture.record("stream_transport_closed", stream=number,
                                    request_id=message["id"], reason="peer-eof")
                                break
                        except BlockingIOError:
                            pass
                        except ConnectionResetError:
                            stream["cancelled"].set()
                            fixture.record("stream_transport_closed", stream=number,
                                request_id=message["id"], reason="peer-reset")
                            break
                        try:
                            action = stream["queue"].get(timeout=0.05)
                        except queue.Empty:
                            continue
                        if action == "complete":
                            output = {"jsonrpc": "2.0", "id": message["id"], "result": {}}
                        else:
                            output = action
                        self.wfile.write(("event: message\ndata: " + json.dumps(output,
                            ensure_ascii=False) + "\n\n").encode())
                        self.wfile.flush()
                        fixture.record("stream_sent", stream=number, output=output)
                        if action == "complete":
                            break
                except (BrokenPipeError, ConnectionResetError):
                    fixture.record("stream_peer_closed", stream=number)
                finally:
                    stream["closed"].set()
                    fixture.record("stream_closed", stream=number)
                    self.close_connection = True

        self.server = Server(("127.0.0.1", 0), Handler)
        self.endpoint = "http://127.0.0.1:" + str(self.server.server_port)
        self.oauth_url = self.endpoint + "/oauth/mcp"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.configure(1)

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"seq": len(self.journal["events"]), "event": event, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    @staticmethod
    def capabilities(label):
        return {"tools": {}, "resources": {"subscribe": False, "listChanged": False},
                "extensions": {"owned/inventory": {"generation": label}}}

    @staticmethod
    def tool(label):
        return {"name": "inspect." + label, "description": "Inventory only λ",
            "inputSchema": {"type": "object", "properties": {"key": {"type": "string"}}},
            "annotations": {"readOnlyHint": True, "destructiveHint": False}}

    def configure(self, generation):
        assert generation in {1, 2}
        codex = self.root / "codex"
        catalog = codex / "models.json"
        atomic_json(catalog, {"models": [{"slug": "mock-model", "display_name": "No inference",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "MCP control only; no turns."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        config = f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
chatgpt_base_url = "{self.endpoint}/api/codex"
openai_base_url = "{self.endpoint}/v1"
[analytics]
enabled = false
[features]
apps = {str(self.profile == 'events').lower()}
plugins = false
remote_plugin = false
recommended_plugins = false
codex_hooks = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned no-inference fixture"
base_url = "{self.endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        if self.profile == "status":
            suffix = "b" if generation == 1 else "b-v2"
            for name, path in [("alpha", "a"), ("beta", suffix)]:
                config += f'''[mcp_servers.{name}]
url = "{self.endpoint}/inventory/{path}?secret=owned-query-canary"
startup_timeout_sec = 5
http_headers = {{ Authorization = "Bearer synthetic-owned-inventory" }}
'''
        elif self.profile == "oauth":
            config += f'''[mcp_servers.oauth]
url = "{self.oauth_url}"
startup_timeout_sec = 5
[mcp_servers.oauth.oauth]
client_id = "{CLIENT}"
callback_url = "http://127.0.0.1{CALLBACK_PATH}"
'''
        elif self.profile == "events":
            config += f'''[mcp_servers.inventory]
url = "{self.endpoint}/inventory/a"
startup_timeout_sec = 5
http_headers = {{ Authorization = "Bearer synthetic-owned-inventory" }}
'''
        temporary = codex / "config.pending"
        temporary.write_text(config)
        temporary.replace(codex / "config.toml")
        self.generation = generation
        if self.profile == "events":
            atomic_json(codex / "auth.json", {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                "tokens": {"id_token": synthetic_id_token(), "access_token": ACCESS,
                    "refresh_token": "synthetic-owned-refresh", "account_id": ACCOUNT},
                "last_refresh": datetime.now(timezone.utc).isoformat()})
            (codex / "auth.json").chmod(0o600)
        self.record("config_written", generation=generation, profile=self.profile)

    def environment(self):
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(self.root / "codex"),
            "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"], "NO_COLOR": "1",
            "RUST_LOG": "off", "CODEX_DISABLE_REMOTE_CONTROL": "1", "NO_PROXY": "*", "no_proxy": "*",
            "CODEX_REFRESH_TOKEN_URL_OVERRIDE": self.endpoint + "/forbidden-refresh",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}

    def start_native(self):
        path = self.root / "native.sock"
        path.unlink(missing_ok=True)
        with (self.root / "native-stderr.log").open("a") as stderr:
            self.native = subprocess.Popen([str(self.binary), "app-server", "--listen", "unix://" + str(path)],
                cwd=self.root / "workspace", env=self.environment(), stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=stderr)
        self.native_pids.append(self.native.pid)
        deadline = time.monotonic() + 5
        while not path.exists():
            assert self.native.poll() is None, "owned native startup exited"
            assert time.monotonic() < deadline, "owned native UDS startup deadline"
            time.sleep(0.01)
        atomic_json(self.root / "state.json", {**self.proof, "endpoint": self.endpoint,
            "oauth_url": self.oauth_url, "controller_pid": os.getpid(),
            "namespace_owner_pid": os.getppid(), "native_pid": self.native.pid,
            "native_pids": self.native_pids, "ready": True})
        self.record("native_started", pid=self.native.pid)

    def stop_native(self):
        if self.native is not None:
            if self.native.poll() is None:
                self.native.terminate()
            try:
                self.native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.native.kill()
                self.native.wait(timeout=5)
            self.record("native_stopped", pid=self.native.pid)
            self.native = None

    def complete_callback(self, authorization_url, variant):
        assert variant in {"success", "wrong-state", "wrong-issuer", "denied"}
        parsed = urlparse(authorization_url)
        assert parsed.scheme == "http" and parsed.netloc == urlparse(self.endpoint).netloc
        assert parsed.path == "/oauth/authorize" and not parsed.fragment
        query = parse_qs(parsed.query, strict_parsing=True)
        assert all(len(values) == 1 for values in query.values())
        assert query["client_id"] == [CLIENT] and query["response_type"] == ["code"]
        assert query["code_challenge_method"] == ["S256"]
        redirect = urlparse(query["redirect_uri"][0])
        assert redirect.scheme == "http" and redirect.hostname == "127.0.0.1"
        assert redirect.port and redirect.path == CALLBACK_PATH
        assert not redirect.username and not redirect.password and not redirect.query and not redirect.fragment
        self.authorization = {key: values[0] for key, values in query.items()}
        self.callback = (redirect.hostname, redirect.port)
        values = {"code": "owned-code", "state": query["state"][0], "iss": self.oauth_url}
        if variant == "wrong-state":
            values["state"] = "owned-state-mismatch"
        elif variant == "wrong-issuer":
            values["iss"] = "https://issuer-mismatch.synthetic.invalid"
        elif variant == "denied":
            values = {"error": "access_denied", "error_description": "Owned denial",
                      "state": query["state"][0]}
        callback_url = redirect._replace(query=urlencode(values)).geturl()
        opener = build_opener(ProxyHandler({}), NoRedirect())
        try:
            with opener.open(Request(callback_url, method="GET"), timeout=5) as response:
                status = response.status
                response.read(4096)
        except HTTPError as error:
            status = error.code
            error.close()
        self.record("callback_sent", variant=variant, http_status=status,
            pkce_present=True, client_verified=True, redirect_verified=True,
            requested_scopes=query.get("scope", [""])[0].split())
        return {"http_status": status}

    def control(self, message):
        assert isinstance(message, dict) and set(message) <= {"id", "op", "generation", "stream", "kind", "url", "variant"}
        identity, operation = message["id"], message["op"]
        assert isinstance(identity, str) and 0 < len(identity) <= 80
        result = {}
        if operation == "config":
            assert self.profile == "status"
            self.configure(message["generation"])
        elif operation == "malformed-config":
            assert self.profile == "status"
            (self.root / "codex/config.toml").write_text("[owned invalid config\n")
            self.record("config_malformed")
        elif operation == "callback":
            assert self.profile == "oauth"
            result = self.complete_callback(message["url"], message["variant"])
        elif operation == "probe-callback":
            assert self.callback is not None
            try:
                with socket.create_connection(self.callback, timeout=0.2):
                    result = {"callback_open": True}
            except OSError:
                result = {"callback_open": False}
        elif operation == "restart":
            self.stop_native()
            self.start_native()
        elif operation == "emit":
            assert self.profile == "events"
            stream = self.streams[message["stream"]]
            kind = message["kind"]
            assert kind in {"active", "event", "terminated", "wrong-id", "missing-id", "complete", "late"}
            if kind == "complete":
                output = "complete"
            else:
                metadata = {"io.modelcontextprotocol/subscriptionId": stream["request_id"],
                            "provider": "owned-events"}
                method = "notifications/events/" + (kind if kind in {"active", "terminated"} else "event")
                params = {"_meta": metadata}
                if kind == "active":
                    params["status"] = "active"
                elif kind not in {"terminated"}:
                    params.update({"name": "owned.updated", "data": {"value": "λ🙂", "nested": [1, None, False],
                                                                            "sentinel": kind}})
                if kind == "wrong-id":
                    metadata["io.modelcontextprotocol/subscriptionId"] = "owned-unrelated-request"
                elif kind == "missing-id":
                    metadata.pop("io.modelcontextprotocol/subscriptionId")
                elif kind == "late" and not stream["closed"].is_set():
                    stale = [row for number, row in self.streams.items()
                             if number < stream["number"] and row["cancelled"].is_set()]
                    assert stale, "late sentinel requires a previously cancelled owned stream"
                    metadata["io.modelcontextprotocol/subscriptionId"] = stale[-1]["request_id"]
                output = {"jsonrpc": "2.0", "method": method, "params": params}
            if stream["closed"].is_set() or stream["cancelled"].is_set():
                assert kind == "late", "only fixed late sentinel may target a closed stream"
                self.record("late_after_close", stream=stream["number"])
            else:
                stream["queue"].put_nowait(output)
        elif operation == "barrier":
            pass
        elif operation == "close":
            self.close()
        else:
            raise AssertionError("unapproved fixture control")
        self.record("control_done", id=identity, op=operation, result=result)

    def close(self):
        if self.closed:
            return
        self.closing.set()
        self.stop_native()
        for stream in self.streams.values():
            stream["cancelled"].set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned MCP HTTP listener did not stop"
        self.record("fixture_closed")
        self.closed = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--profile", required=True, choices=sorted(PROFILES))
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    root, binary = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == BINARY_SHA256
    assert all((root / directory).is_dir() for directory in ["home", "codex", "tmp", "workspace"])
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(root, binary, args.profile, isolation(args.parent_netns))
        fixture.start_native()
        for line in sys.stdin:
            assert len(line.encode()) <= 16_384, "oversized fixture control"
            fixture.control(json.loads(line))
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


if __name__ == "__main__":
    main()
