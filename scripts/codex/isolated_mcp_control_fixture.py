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
OAUTH_RECOVERY_ACCESS = "synthetic-owned-mcp-oauth-recovered-access"
ACCOUNT = "isolated-auth-account"
CLIENT = "owned-mcp-client"
EVENT_PATH = "/api/codex/ps/mcp"
CALLBACK_PATH = "/callback/owned-mcp"
OAUTH_MISSING_METADATA = "/oauth/.well-known/owned-missing-authorization-server"
DCR_CLIENT = "owned-dcr-client"
CIMD_CLIENT = "https://chatgpt.com/oauth/codex/client.json"
OAUTH_SELECTOR_PROFILES = {"oauth-cimd", "oauth-auto-fallback",
                           "oauth-cimd-no-advertisement", "oauth-cimd-no-none"}
UNCONFIGURED_OAUTH_PROFILES = {"oauth-dcr"} | OAUTH_SELECTOR_PROFILES
PROFILES = {"status", "oauth", "events", "form-bool"} | UNCONFIGURED_OAUTH_PROFILES
MCP_PATHS = {"/inventory/a", "/inventory/a-failed", "/inventory/a-held", "/inventory/a-v2",
             "/inventory/b", "/inventory/b-v2", "/oauth/mcp", EVENT_PATH}
INVENTORY_STARTUP_ERROR = "owned-inventory-initialize-rejected"
AUTH_METADATA = {"/.well-known/oauth-authorization-server/oauth/mcp",
                 "/oauth/mcp/.well-known/oauth-authorization-server",
                 "/.well-known/oauth-authorization-server"}
RESOURCE_METADATA = {"/.well-known/oauth-protected-resource/oauth/mcp",
                     "/oauth/mcp/.well-known/oauth-protected-resource"}
APPS_RESOURCE_METADATA = {"/.well-known/oauth-protected-resource/api/codex/ps/mcp",
                          "/api/codex/ps/mcp/.well-known/oauth-protected-resource",
                          "/.well-known/oauth-protected-resource"}
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
        self.inventory_health = None
        self.oauth_discovery = "valid"
        self.oauth_access_revoked, self.oauth_recovery_issued = False, False
        self.registration = None
        self.oauth_client_id = (DCR_CLIENT if profile in {"oauth-dcr", "oauth-auto-fallback"}
                                else CIMD_CLIENT if profile in OAUTH_SELECTOR_PROFILES else CLIENT)
        self.callback_path = "/callback" if profile in UNCONFIGURED_OAUTH_PROFILES else CALLBACK_PATH
        self.initialize_held = threading.Event()
        self.initialize_release = threading.Event()
        self.initialize_finished = threading.Event()
        self.apps_hold_enabled = False
        self.apps_initialize_held = threading.Event()
        self.apps_initialize_release = threading.Event()
        self.apps_initialize_finished = threading.Event()
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
                written = True
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    written = False
                self.close_connection = True
                return written

            def do_GET(self):
                path = urlparse(self.path).path
                if path == OAUTH_MISSING_METADATA:
                    with fixture.lock:
                        written = self.reply(404, {"error": "owned named issuer has no metadata"})
                        fixture.record("named_issuer_metadata_fault", path=path, status=404,
                                       response_written=written)
                elif path in AUTH_METADATA:
                    fixture.record("oauth_metadata", path=path)
                    metadata = {"issuer": fixture.oauth_url,
                        "authorization_endpoint": fixture.endpoint + "/oauth/authorize",
                        "token_endpoint": fixture.endpoint + "/oauth/token",
                        "authorization_response_iss_parameter_supported": True,
                        "response_types_supported": ["code"],
                        "grant_types_supported": ["authorization_code"],
                        "code_challenge_methods_supported": ["S256"],
                        "token_endpoint_auth_methods_supported": ["none"],
                        "scopes_supported": ["read:owned", "inspect:owned"]}
                    if fixture.profile == "oauth-dcr":
                        metadata.update({"registration_endpoint": fixture.endpoint + "/oauth/register",
                                         "client_id_metadata_document_supported": True})
                        fixture.record("oauth_dcr_metadata", cimd_advertised=True, dcr_advertised=True)
                    elif fixture.profile in OAUTH_SELECTOR_PROFILES:
                        cimd = fixture.profile not in {"oauth-auto-fallback", "oauth-cimd-no-advertisement"}
                        public_none = fixture.profile != "oauth-cimd-no-none"
                        metadata.update({"registration_endpoint": fixture.endpoint + "/oauth/register",
                                         "client_id_metadata_document_supported": cimd,
                                         "token_endpoint_auth_methods_supported": ["none"] if public_none else ["private_key_jwt"]})
                        fixture.record("oauth_selector_metadata", cimd_advertised=cimd,
                                       public_none=public_none, dcr_advertised=True)
                    self.reply(200, metadata)
                elif fixture.profile == "events" and path in APPS_RESOURCE_METADATA:
                    # The pin deliberately treats loopback Apps as ordinary OAuth.
                    # Its resource has a distinct URL from the existing OAuth peer.
                    resource = fixture.endpoint + EVENT_PATH
                    fixture.record("apps_resource_metadata", path=path, resource=resource)
                    self.reply(200, {"resource": resource,
                        "authorization_servers": [fixture.oauth_url],
                        "scopes_supported": ["read:owned", "inspect:owned"]})
                elif path in RESOURCE_METADATA:
                    with fixture.lock:
                        discovery = fixture.oauth_discovery
                    fixture.record("resource_metadata", path=path, discovery=discovery)
                    issuer = fixture.endpoint + OAUTH_MISSING_METADATA if discovery == "missing-metadata" else fixture.oauth_url
                    self.reply(200, {"resource": fixture.oauth_url,
                        "authorization_servers": [issuer],
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
                if path == "/oauth/register":
                    self.register(body)
                elif path == "/oauth/token":
                    self.token(body)
                elif path in MCP_PATHS:
                    self.mcp(path, json.loads(body))
                else:
                    fixture.record("forbidden_http", method="POST", path=path)
                    self.reply(404, {"error": "no inference or command route"})

            def register(self, body):
                assert fixture.profile in {"oauth-dcr", "oauth-auto-fallback"} and fixture.registration is None
                assert self.headers.get("Authorization") is None
                assert self.headers.get("Content-Type", "").split(";")[0] == "application/json"
                request = json.loads(body)
                assert isinstance(request.get("redirect_uris"), list) and len(request["redirect_uris"]) == 1
                redirect = urlparse(request["redirect_uris"][0])
                assert redirect.scheme == "http" and redirect.hostname == "127.0.0.1"
                assert redirect.port and redirect.path == "/callback"
                assert not redirect.username and not redirect.password and not redirect.query and not redirect.fragment
                assert request == {"client_name": "Codex", "redirect_uris": [redirect.geturl()],
                    "grant_types": ["authorization_code", "refresh_token"], "token_endpoint_auth_method": "none",
                    "response_types": ["code"], "scope": "read:owned inspect:owned", "application_type": "native"}
                fixture.registration = request
                fixture.record("client_registered", client_id=DCR_CLIENT, request=request)
                self.reply(201, {"client_id": DCR_CLIENT, "client_name": "Codex",
                                 "redirect_uris": request["redirect_uris"]})

            def token(self, body):
                values = parse_qs(body.decode(), strict_parsing=True)
                with fixture.lock:
                    auth = fixture.authorization
                    assert auth is not None, "token exchange without owned callback"
                    assert values.get("grant_type") == ["authorization_code"]
                    assert values.get("client_id") == [fixture.oauth_client_id]
                    if fixture.profile in OAUTH_SELECTOR_PROFILES:
                        assert "client_secret" not in values and self.headers.get("Authorization") is None
                        if fixture.profile == "oauth-auto-fallback":
                            assert fixture.registration is not None and fixture.oauth_client_id == DCR_CLIENT
                        else:
                            assert fixture.registration is None and fixture.oauth_client_id == CIMD_CLIENT
                        fixture.record("selector_token_verified", client_id=fixture.oauth_client_id,
                                       no_client_secret=True, no_authorization=True)
                    assert values.get("code") == ["owned-code"]
                    assert values.get("redirect_uri") == [auth["redirect_uri"]]
                    verifier = values["code_verifier"][0]
                    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
                    assert challenge == auth["code_challenge"]
                    access_generation = 2 if fixture.oauth_access_revoked else 1
                    access_token = OAUTH_RECOVERY_ACCESS if access_generation == 2 else OAUTH_ACCESS
                    if access_generation == 2:
                        fixture.oauth_recovery_issued = True
                    fixture.record("token_exchange", client_verified=True, redirect_verified=True,
                                   pkce_verified=True, accepted=True, access_generation=access_generation)
                self.reply(200, {"access_token": access_token, "token_type": "Bearer",
                                 "scope": "read:owned inspect:owned"})

            def mcp(self, path, message):
                method, identity = message.get("method"), message.get("id")
                with fixture.lock:
                    initial_bearer = self.headers.get("Authorization") == "Bearer " + OAUTH_ACCESS
                    recovery_bearer = self.headers.get("Authorization") == "Bearer " + OAUTH_RECOVERY_ACCESS
                    revoked_bearer = initial_bearer and fixture.oauth_access_revoked
                    oauth_bearer = ((initial_bearer and not fixture.oauth_access_revoked) or
                                    (recovery_bearer and fixture.oauth_recovery_issued))
                    access_generation = 1 if initial_bearer else 2 if recovery_bearer else None
                apps_bearer = self.headers.get("Authorization") == "Bearer " + ACCESS
                inventory_bearer = self.headers.get("Authorization") == "Bearer synthetic-owned-inventory"
                fixture.record("mcp", path=path, method=method, id=identity,
                    params=message.get("params"), session=self.headers.get("Mcp-Session-Id"),
                    oauth_bearer_verified=oauth_bearer, oauth_access_generation=access_generation,
                    apps_bearer_verified=apps_bearer,
                    inventory_bearer_verified=inventory_bearer,
                    account_verified=self.headers.get("ChatGPT-Account-ID") == ACCOUNT)
                if path == "/oauth/mcp" and not oauth_bearer:
                    with fixture.lock:
                        challenge = 'Bearer ' + ('error="invalid_token", ' if revoked_bearer else '')
                        written = self.reply(401, {"error": "synthetic OAuth required"}, {
                            "WWW-Authenticate": challenge + 'resource_metadata="' + fixture.endpoint +
                            '/.well-known/oauth-protected-resource/oauth/mcp"'})
                        fixture.record("oauth_unauthenticated_response", path=path, method=method,
                            request_id=identity, status=401, challenge_present=True,
                            response_written=written)
                        if revoked_bearer:
                            fixture.record("oauth_revoked_access_response", path=path, method=method,
                                request_id=identity, access_generation=1, status=401,
                                challenge_present=True, response_written=written)
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
                    with fixture.lock:
                        hold_apps = path == EVENT_PATH and fixture.apps_hold_enabled
                    if hold_apps:
                        self.held_apps_initialize(message)
                        return
                    if path == "/inventory/a-held":
                        self.held_initialize(message)
                        return
                    if path == "/inventory/a-failed":
                        fixture.record("inventory_startup_rejected", path=path, request_id=identity)
                        self.reply(200, {"jsonrpc": "2.0", "id": identity,
                                        "error": {"code": -32603, "message": INVENTORY_STARTUP_ERROR}})
                        return
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

            def held_initialize(self, message):
                # Only this dependency's real initialize response is held. Native
                # Codex, not this fixture, produces the app-server runtime status.
                identity = message["id"]
                assert fixture.profile == "status" and not fixture.initialize_held.is_set()
                fixture.initialize_held.set()
                fixture.record("inventory_initialize_held", path="/inventory/a-held",
                               request_id=identity)
                try:
                    assert fixture.initialize_release.wait(5), "owned initialize release deadline"
                    if fixture.closing.is_set():
                        fixture.record("inventory_initialize_abandoned", request_id=identity)
                        return
                    fixture.record("inventory_initialize_response_attempted", request_id=identity)
                    result = {"protocolVersion": "2025-06-18",
                        "capabilities": fixture.capabilities("a-held"),
                        "serverInfo": {"name": "owned-a-held", "version": "1.0.0",
                            "title": "Owned a-held", "description": "Synthetic inventory λ",
                            "websiteUrl": "https://synthetic.invalid/owned"}}
                    try:
                        self.reply(200, {"jsonrpc": "2.0", "id": identity, "result": result},
                                   {"Mcp-Session-Id": "owned-session-a-held"})
                    except (BrokenPipeError, ConnectionResetError):
                        # Cancellation can close the peer before even the response
                        # headers are written. A successful write is not acceptance.
                        fixture.record("inventory_initialize_peer_closed", request_id=identity)
                finally:
                    fixture.record("inventory_initialize_finished", request_id=identity)
                    fixture.initialize_finished.set()
                    self.close_connection = True

            def held_apps_initialize(self, message):
                # A new thread owns a distinct real Apps client. Only this fixed
                # HTTP dependency response is held; no app-server frame is made.
                identity = message["id"]
                assert fixture.profile == "events" and fixture.apps_hold_enabled
                assert not fixture.apps_initialize_held.is_set(), "unexpected extra Apps initialize"
                fixture.apps_initialize_held.set()
                fixture.record("apps_initialize_held", path=EVENT_PATH, request_id=identity)
                try:
                    assert fixture.apps_initialize_release.wait(5), "owned Apps initialize release deadline"
                    if fixture.closing.is_set():
                        fixture.record("apps_initialize_abandoned", request_id=identity)
                        return
                    fixture.record("apps_initialize_response_attempted", request_id=identity)
                    result = {"protocolVersion": "2025-06-18",
                        "capabilities": fixture.capabilities("mcp"),
                        "serverInfo": {"name": "owned-mcp", "version": "1.0.0",
                            "title": "Owned mcp", "description": "Synthetic inventory λ",
                            "websiteUrl": "https://synthetic.invalid/owned"}}
                    try:
                        written = self.reply(200, {"jsonrpc": "2.0", "id": identity, "result": result},
                                             {"Mcp-Session-Id": "owned-session-mcp"})
                        fixture.record("apps_initialize_response_written", request_id=identity,
                                       response_written=written)
                    except (BrokenPipeError, ConnectionResetError):
                        fixture.record("apps_initialize_peer_closed", request_id=identity)
                finally:
                    fixture.record("apps_initialize_finished", request_id=identity)
                    fixture.apps_initialize_finished.set()
                    self.close_connection = True

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
            alpha = {"startup-failed": "a-failed", "startup-held": "a-held",
                     "healthy": "a-v2"}.get(self.inventory_health, "a")
            for name, path in [("alpha", alpha), ("beta", suffix)]:
                disabled = "enabled = false\n" if name == "alpha" and self.inventory_health == "disabled" else ""
                config += f'''[mcp_servers.{name}]
url = "{self.endpoint}/inventory/{path}?secret=owned-query-canary"
{disabled}startup_timeout_sec = 5
http_headers = {{ Authorization = "Bearer synthetic-owned-inventory" }}
'''
        elif self.profile in ({"oauth"} | UNCONFIGURED_OAUTH_PROFILES):
            config += f'''[mcp_servers.oauth]
url = "{self.oauth_url}"
startup_timeout_sec = 5
'''
            if self.profile == "oauth":
                config += f'''[mcp_servers.oauth.oauth]
client_id = "{CLIENT}"
callback_url = "http://127.0.0.1{CALLBACK_PATH}"
'''
        elif self.profile == "form-bool":
            journal = self.root / "form-peer.jsonl"
            if not journal.exists():
                journal.touch(exist_ok=False)
            args = [str(Path(__file__).resolve()), "--form-peer", str(journal)]
            config += ("[mcp_servers.form]\ncommand = " + json.dumps(sys.executable)
                       + "\nargs = " + json.dumps(args)
                       + "\nstartup_timeout_sec = 5\ntool_timeout_sec = 10\n")
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
        assert query["client_id"] == [self.oauth_client_id] and query["response_type"] == ["code"]
        assert query["code_challenge_method"] == ["S256"]
        redirect = urlparse(query["redirect_uri"][0])
        assert redirect.scheme == "http" and redirect.hostname == "127.0.0.1"
        assert redirect.port and redirect.path == self.callback_path
        assert not redirect.username and not redirect.password and not redirect.query and not redirect.fragment
        if self.profile in {"oauth-dcr", "oauth-auto-fallback"}:
            assert self.registration is not None
            assert self.registration["redirect_uris"] == [query["redirect_uri"][0]]
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
        elif operation == "inventory-health":
            assert self.profile == "status"
            assert message["variant"] in {"startup-failed", "startup-held", "healthy", "disabled"}
            self.inventory_health = message["variant"]
            self.configure(message["generation"])
            self.record("inventory_health_changed", variant=self.inventory_health,
                        generation=self.generation)
        elif operation == "inventory-startup-state":
            assert self.profile == "status" and self.inventory_health == "startup-held"
            result = {"held": self.initialize_held.is_set(),
                      "released": self.initialize_release.is_set(),
                      "finished": self.initialize_finished.is_set()}
        elif operation == "inventory-startup-release":
            assert self.profile == "status" and self.inventory_health == "startup-held"
            assert self.initialize_held.is_set() and not self.initialize_release.is_set()
            self.record("inventory_initialize_release_requested")
            self.initialize_release.set()
            assert self.initialize_finished.wait(5), "owned initialize handler completion deadline"
            result = {"held": True, "released": True, "finished": True}
        elif operation == "apps-startup-hold":
            assert self.profile == "events" and not self.apps_hold_enabled
            with self.lock:
                assert any(event["event"] == "mcp" and event.get("path") == EVENT_PATH
                           and event.get("method") == "tools/list"
                           for event in self.journal["events"]), "prime Apps natively before hold"
                self.apps_hold_enabled = True
                self.record("apps_initialize_hold_armed", path=EVENT_PATH)
            result = {"armed": True}
        elif operation == "apps-startup-state":
            assert self.profile == "events" and self.apps_hold_enabled
            result = {"armed": True, "held": self.apps_initialize_held.is_set(),
                      "released": self.apps_initialize_release.is_set(),
                      "finished": self.apps_initialize_finished.is_set()}
        elif operation == "apps-startup-release":
            assert self.profile == "events" and self.apps_hold_enabled
            assert self.apps_initialize_held.is_set() and not self.apps_initialize_release.is_set()
            self.record("apps_initialize_release_requested")
            self.apps_initialize_release.set()
            assert self.apps_initialize_finished.wait(5), "owned Apps handler completion deadline"
            result = {"armed": True, "held": True, "released": True, "finished": True}
        elif operation == "malformed-config":
            assert self.profile == "status"
            (self.root / "codex/config.toml").write_text("[owned invalid config\n")
            self.record("config_malformed")
        elif operation == "oauth-revoke-access":
            assert self.profile == "oauth"
            with self.lock:
                assert not self.oauth_access_revoked and not self.oauth_recovery_issued
                assert any(event["event"] == "mcp" and event.get("path") == "/oauth/mcp"
                           and event.get("method") == "initialize"
                           and event.get("oauth_bearer_verified") is True
                           and event.get("oauth_access_generation") == 1
                           for event in self.journal["events"]), "prime owned OAuth natively before revocation"
                self.oauth_access_revoked = True
                self.record("oauth_access_revoked", access_generation=1)
            result = {"revoked_generation": 1}
        elif operation == "oauth-discovery":
            assert self.profile == "oauth"
            assert message["variant"] in {"valid", "missing-metadata"}
            with self.lock:
                self.oauth_discovery = message["variant"]
                self.record("oauth_discovery_changed", variant=self.oauth_discovery)
            result = {"variant": self.oauth_discovery}
        elif operation == "callback":
            assert self.profile in ({"oauth"} | UNCONFIGURED_OAUTH_PROFILES)
            result = self.complete_callback(message["url"], message["variant"])
        elif operation == "selector-listeners":
            assert self.profile in OAUTH_SELECTOR_PROFILES
            ports = []
            for table in ["/proc/net/tcp", "/proc/net/tcp6"]:
                for row in Path(table).read_text().splitlines()[1:]:
                    fields = row.split()
                    if fields[3] == "0A":
                        ports.append(int(fields[1].rsplit(":", 1)[1], 16))
            result = {"listening_ports": sorted(ports)}
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
        self.initialize_release.set()
        self.apps_initialize_release.set()
        self.stop_native()
        for stream in self.streams.values():
            stream["cancelled"].set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned MCP HTTP listener did not stop"
        self.record("fixture_closed")
        self.closed = True


def form_peer(journal):
    """One inert tool; native emits all app-server messages, never this peer."""
    journal = Path(journal).resolve()
    assert journal.name == "form-peer.jsonl" and journal.parent.is_dir()
    pending, calls = None, 0

    def record(row):
        with journal.open("a", encoding="utf-8") as target:
            target.write(json.dumps(row, ensure_ascii=False) + "\n")

    def send(message):
        message = {"jsonrpc": "2.0", **message}
        record({"direction": "out", "message": message})
        print(json.dumps(message), flush=True)

    def result(identity, value):
        send({"id": identity, "result": value})

    record({"peer_started": os.getpid()})
    try:
        for line in sys.stdin:
            assert len(line.encode()) <= 65_536, "oversized owned form input"
            message = json.loads(line)
            record({"direction": "in", "message": message})
            method, identity = message.get("method"), message.get("id")
            if method == "initialize":
                assert message["params"]["protocolVersion"] == "2025-06-18"
                assert message["params"]["capabilities"]["extensions"] == {"openai/form": {}}
                result(identity, {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                    "serverInfo": {"name": "owned-bool-form", "version": "1.0.0"}})
            elif method == "notifications/initialized":
                assert identity is None
            elif method == "tools/list":
                result(identity, {"tools": [{"name": "confirm", "description": "Owned bool translation form",
                    "inputSchema": {"type": "object", "properties": {}},
                    "annotations": {"readOnlyHint": True, "destructiveHint": False}}]})
            elif method == "resources/list":
                result(identity, {"resources": []})
            elif method == "resources/templates/list":
                result(identity, {"resourceTemplates": []})
            elif method == "tools/call":
                calls += 1
                assert calls == 1 and pending is None
                assert message["params"]["name"] == "confirm" and message["params"]["arguments"] == {}
                pending = identity
                send({"id": "owned-bool-form", "method": "openai/form", "params": {
                    "message": "Owned bool translation form", "_meta": {"fixture/request": "bool-translation"},
                    "requestedSchema": {"type": "object", "properties": {
                        "labels": {"type": "array", "items": {"type": "string"}}},
                        "required": ["labels"], "additionalProperties": False}}})
            elif identity == "owned-bool-form":
                assert pending is not None and "error" not in message
                assert message["result"] == {"action": "accept", "content": {"labels": ["owned-λ"]},
                    "_meta": {"fixture/response": "explicit-owned-decision"}}
                record({"decision_observed": "accept"})
                result(pending, {"content": [{"type": "text", "text": "Owned explicit form decision observed"}],
                                 "isError": False})
                pending = None
            elif method == "ping":
                result(identity, {})
            else:
                record({"forbidden_form": True, "method": method})
                raise AssertionError("unapproved owned form method")
    finally:
        record({"peer_closed": True})


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--form-peer":
        form_peer(sys.argv[2])
        return
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
