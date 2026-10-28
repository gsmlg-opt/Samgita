#!/usr/bin/env python3
"""Ordinary local Apps/MCP/model inputs; no app-server emulator or command tool.

One process, one synchronous HTTP server, no children or helper threads. Synthetic
runtime identity is setup only: no credential/header inspection or auth assertions.
"""
import argparse
import base64
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
from urllib.parse import urlparse

MAX_BODY = 1_048_576
MAX_HTTP = 128
CONNECTOR = "owned_inventory"
TOOL = "owned_inventory_lookup"
CALL_ID = "owned-app-context-call-532"
LINK = "owned-link-532"
URI = "ui://owned/inventory-panel.html"
APP_NAME = "owned_inventory"
MARKER = "Owned ordinary persisted Apps context λ🙂"
ANSWER = "Owned inventory metadata recorded λ"
ARGUMENTS = {"query": "ordinary lamps λ", "link_id": LINK}
RESULT = {"content": [{"type": "text", "text": "Owned inventory result β🙂"}],
          "structuredContent": {"items": ["lamp-532"], "source": CONNECTOR},
          "isError": False}
MCP_PATH = "/backend-api/ps/mcp"


def encoded(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")


def write_json(path, value):
    data = json.dumps(value, ensure_ascii=False).encode()
    assert len(data) <= MAX_BODY, "Owned fixture file bound"
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_bytes(data)
    pending.replace(path)


def descriptor():
    return {"name": TOOL, "description": "Owned inventory metadata lookup",
            "inputSchema": {"type": "object"},
            "annotations": {"readOnlyHint": True, "destructiveHint": False},
            "_meta": {"connector_id": CONNECTOR, "connector_name": APP_NAME,
                      "link_id": LINK, "ui": {"resourceUri": URI},
                      "openai/outputTemplate": URI,
                      "_codex_apps": {
                          "resource_uri": f"/{CONNECTOR}/{LINK}/{TOOL}",
                          "contains_mcp_source": True}}}


class Fixture:
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.models = []
        self.tools = []
        self.events = []
        self.http_count = 0
        self.journal = self.root / "ordinary-app-context-journal.json"
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None, content_type="application/json"):
                data = b"" if value is None else (
                    value if isinstance(value, bytes) else json.dumps(value).encode())
                assert len(data) <= MAX_BODY, "Owned reply bound"
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def do_GET(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                path = urlparse(self.path).path
                if path == MCP_PATH:
                    self.reply(405)
                elif path == "/backend-api/wham/config/bundle":
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

            def do_POST(self):
                path = urlparse(self.path).path
                try:
                    owner.http_count += 1
                    assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= MAX_BODY, "Owned input bound"
                    body = json.loads(self.rfile.read(size))
                    if path == "/v1/responses":
                        item = owner.model_response(body)
                        index = len(owner.models)
                        response_id = f"owned-app-context-response-{index}"
                        events = [
                            {"type": "response.created", "response": {"id": response_id}},
                            {"type": "response.output_item.done", "item": item},
                            {"type": "response.completed", "response": {"id": response_id,
                                "usage": {"input_tokens": 0, "input_tokens_details": None,
                                          "output_tokens": 0, "output_tokens_details": None,
                                          "total_tokens": 0}}}]
                        data = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                                       for event in events).encode()
                        self.reply(200, data, "text/event-stream")
                    elif path == MCP_PATH:
                        assert body.get("jsonrpc") == "2.0"
                        method = body.get("method")
                        if method == "notifications/initialized":
                            assert "id" not in body
                            self.reply(202)
                        else:
                            assert "id" in body, "Owned MCP request identity"
                            result = owner.mcp_response(method, body.get("params", {}))
                            self.reply(200, {"jsonrpc": "2.0", "id": body["id"],
                                             "result": result})
                    else:
                        owner.record("unexpected_http", method="POST", path=path)
                        self.reply(404, {})
                except Exception:
                    owner.record("fatal", stage="ordinary-http-handler", path=path)
                    self.reply(500, {"error": "owned ordinary fixture failed"})

            def do_DELETE(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                if urlparse(self.path).path == MCP_PATH:
                    self.reply(200, {})
                else:
                    owner.record("unexpected_http", method="DELETE", path=urlparse(self.path).path)
                    self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 256, "Owned fixture event bound"
        self.events.append({"event": event, **fields})
        write_json(self.journal, {"events": self.events})

    def model_response(self, request):
        assert request["model"] == "mock-model"
        assert any(part.get("text") == MARKER
                   for item in request.get("input", []) if item.get("role") == "user"
                   for part in item.get("content", []) if isinstance(part, dict))
        step = len(self.models)
        assert step < 2, "Owned model request bound"
        outputs = [item["call_id"] for item in request.get("input", [])
                   if item.get("type") == "function_call_output"]
        assert outputs == ([] if step == 0 else [CALL_ID])
        assert len(self.tools) == step, "Owned continuation effect count"
        self.models.append(request)
        write_json(self.args.requests_file, self.models)
        self.record("model", sequence=step + 1, output_call_ids=outputs)
        if step == 0:
            return {"type": "function_call", "namespace": "mcp__codex_apps__" + CONNECTOR,
                    "name": "_lookup", "call_id": CALL_ID,
                    "arguments": json.dumps(ARGUMENTS)}
        return {"type": "message", "role": "assistant", "id": "owned-app-context-final-532",
                "content": [{"type": "output_text", "text": ANSWER}]}

    def mcp_response(self, method, params):
        if method == "initialize":
            self.record("mcp_initialized", version="2025-06-18")
            return {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}, "resources": {}},
                    "serverInfo": {"name": "owned-ordinary-app-context", "version": "1"}}
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [descriptor()]}
        if method == "resources/list":
            return {"resources": []}
        if method == "resources/templates/list":
            return {"resourceTemplates": []}
        if method == "tools/call":
            assert self.tools == [], "Owned single metadata call"
            assert params["name"] == TOOL and params["arguments"] == ARGUMENTS
            thread = params.get("_meta", {}).get("threadId")
            assert isinstance(thread, str) and thread
            self.tools.append(CALL_ID)
            self.record("tool_call", call_id=CALL_ID, tool=TOOL,
                        arguments=ARGUMENTS, thread_id=thread)
            return RESULT
        self.record("unexpected_mcp", method=method)
        raise AssertionError("Unexpected ordinary dependency method")

    def configure(self):
        codex = self.args.codex_home
        catalog = codex / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary Apps context",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned synthetic inventory metadata only."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        endpoint = f"http://127.0.0.1:{self.http.server_port}"
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{endpoint}/backend-api"
openai_base_url = "{endpoint}/v1"
[features]
apps = true
plugins = false
recommended_plugins = false
shell_snapshot = false
memories = false
[memories]
generate_memories = false
use_memories = false
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[model_providers.fixture]
name = "Owned ordinary context input"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        # Inert synthetic runtime setup. No identity outcome is inspected/tested.
        token = ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
            "email": "owned-context@synthetic.invalid", "exp": 4_102_444_800,
            "https://api.openai.com/auth": {"chatgpt_account_id": "owned-app-context-account",
                "chatgpt_user_id": "owned-app-context-user", "chatgpt_plan_type": "pro"}}),
            "b3duZWQtc3ludGhldGlj"])
        write_json(codex / "auth.json", {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
            "tokens": {"id_token": token, "access_token": "owned-context-synthetic-access",
                       "refresh_token": "owned-context-synthetic-refresh",
                       "account_id": "owned-app-context-account"},
            "last_refresh": datetime.now(timezone.utc).isoformat()})
        write_json(self.args.requests_file, [])

    def close(self):
        self.http.server_close()
        self.record("fixture_closed", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-app-context"])
    args = parser.parse_args()
    fixture = Fixture(args)

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
