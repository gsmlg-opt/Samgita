#!/usr/bin/env python3
"""Owned loopback model and Apps MCP dependencies; only native Codex emits frames."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
from urllib.parse import urlparse

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts/codex"))
from isolated_apps_fixture import Fixture as AppsFixture
from model_fixture import response_events

NATIVE_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
URI = "ui://widget/checkout-session.html"
MARKER = "OWNED_MCP_ORIGIN_V43"
CALLS = [("owned-origin-best-buy", "best_buy"), ("owned-origin-walmart", "walmart")]
MCP_PATH = "/backend-api/ps/mcp"
ALLOWED_METHODS = {
    "initialize", "initialized", "server/diagnostics", "thread/start",
    "thread/read", "thread/loaded/list", "turn/start", "mcpServer/resource/read",
}
MAX_BODY = 1_048_576


def arguments(connector):
    return {"query": "lamps", "link_id": "link_" + connector}


def descriptor(connector):
    return {
        "name": connector + "_product_search", "description": "Owned read-only product search",
        "inputSchema": {"type": "object"},
        "annotations": {"readOnlyHint": True, "destructiveHint": False},
        "_meta": {
            "connector_id": connector, "connector_name": connector,
            "link_id": "link_" + connector, "ui": {"resourceUri": URI},
            "openai/outputTemplate": URI,
            "_codex_apps": {
                "resource_uri": f"/{connector}/link_{connector}/{connector}_product_search",
                "contains_mcp_source": True,
            },
        },
    }


def result(connector):
    return {
        "content": [{"type": "text", "text": "Owned origin tool " + connector}],
        "structuredContent": {"connector": connector, "products": []},
        "isError": False,
    }


class OriginFixture(AppsFixture):
    def __init__(self, root, namespace):
        self.root = root
        self.scenario = "enabled"
        self.product_sku = "codex"
        self.lock = threading.Lock()
        self.http_context = threading.local()
        self.journal = {"namespace": namespace, "events": []}
        self.model_requests = []
        self.tool_calls = []
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None, content_type="application/json"):
                body = b"" if value is None else (
                    value if isinstance(value, bytes) else json.dumps(value).encode()
                )
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)
                self.close_connection = True

            def do_GET(self):
                path = urlparse(self.path).path
                fixture.http_context.request = (self.command, path)
                if path == MCP_PATH:
                    self.reply(405)
                elif path == "/backend-api/wham/config/bundle":
                    self.reply(200, {})
                elif path == "/backend-api/wham/accounts/check":
                    # Same isolated synthetic account used by AppsFixture.configure.
                    self.reply(200, {"accounts": [{
                        "id": "isolated-auth-account",
                        "workspace_backend_origin": "https://synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT",
                    }]})
                elif path == "/backend-api/wham/settings/user":
                    self.reply(200, {"commit_attribution_enabled": False})
                else:
                    fixture.record("fatal", stage="unexpected-get", path=path)
                    self.reply(404, {})

            def do_POST(self):
                fixture.http_context.request = (self.command, urlparse(self.path).path)
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size <= MAX_BODY, "Owned HTTP body bound"
                body = json.loads(self.rfile.read(size))
                path = urlparse(self.path).path
                if path == "/v1/responses":
                    item = fixture.model_response(body)
                    index = len(fixture.model_requests)
                    events = "".join(
                        f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                        for event in response_events(index, item)
                    ).encode()
                    self.reply(200, events, "text/event-stream")
                    return
                assert path == MCP_PATH, "Unexpected owned POST route"
                assert self.headers.get("Authorization") is None, "MCP received bearer"
                assert self.headers.get("chatgpt-account-id") is None, "MCP received account"
                assert self.headers.get("X-OpenAI-Product-Sku") == "codex", "MCP SKU"
                assert body.get("jsonrpc") == "2.0"
                method = body.get("method")
                fixture.record("mcp", method=method, bearer_absent=True, account_absent=True)
                if method == "notifications/initialized":
                    assert "id" not in body
                    self.reply(202)
                    return
                assert "id" in body, "Unexpected MCP notification"
                reply = fixture.mcp_response(method, body.get("params", {}))
                self.reply(200, {"jsonrpc": "2.0", "id": body["id"], "result": reply})

            def do_DELETE(self):
                fixture.http_context.request = (self.command, urlparse(self.path).path)
                assert urlparse(self.path).path == MCP_PATH
                self.reply(204)

        class OwnedServer(ThreadingHTTPServer):
            daemon_threads = True

            def handle_error(self, _request, _client_address):
                error_type, _, trace = sys.exc_info()
                while trace.tb_next is not None:
                    trace = trace.tb_next
                method, path = getattr(fixture.http_context, "request", (None, None))
                fixture.record("fatal", stage="http-handler",
                               method=method, path=path, source_line=trace.tb_lineno,
                               error_type=error_type.__name__)

        self.http = OwnedServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.record("http_ready")

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 512, "Owned journal row bound"
            self.journal["events"].append({"event": event, **fields})
            data = json.dumps(self.journal)
            assert len(data.encode()) <= MAX_BODY, "Owned journal byte bound"
            pending = self.root / "origin-journal.pending"
            pending.write_text(data)
            pending.replace(self.root / "origin-journal.json")

    def configure(self):
        environment = super().configure()
        codex = self.root / "codex"
        config = codex / "config.toml"
        config.write_text(
            'approval_policy = "on-request"\nsandbox_mode = "read-only"\n'
            'analytics.enabled = false\n'
            'mcp_oauth_credentials_store = "file"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + config.read_text().replace("requires_openai_auth = true",
                                         "requires_openai_auth = false")
        )
        catalog = codex / "models.json"
        data = json.loads(catalog.read_text())
        data["models"][0]["model_messages"]["instructions_template"] = (
            "Owned synthetic app resource provenance qualification."
        )
        catalog.write_text(json.dumps(data))
        environment.update({
            "CODEX_DISABLE_REMOTE_CONTROL": "1", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
        })
        return environment

    def model_response(self, request):
        assert request["model"] == "mock-model"
        assert any(
            part.get("text") == MARKER
            for item in request.get("input", []) if item.get("role") == "user"
            for part in item.get("content", []) if isinstance(part, dict)
        ), "Unexpected model prompt"
        step = len(self.model_requests)
        assert step < 3, "Unexpected model request"
        outputs = [item["call_id"] for item in request.get("input", [])
                   if item.get("type") == "function_call_output"]
        assert outputs == [identity for identity, _ in CALLS[:step]], "Native output call binding"
        assert len(self.tool_calls) == step, "Unexpected native tool effect count"
        self.model_requests.append(request)
        pending = self.root / "model-requests.pending"
        pending.write_text(json.dumps(self.model_requests))
        pending.replace(self.root / "model-requests.json")
        self.record("model", sequence=step + 1, output_call_ids=outputs)
        if step < 2:
            identity, connector = CALLS[step]
            return {
                "type": "function_call", "namespace": "mcp__codex_apps__" + connector,
                "name": "_product_search", "call_id": identity,
                "arguments": json.dumps(arguments(connector)),
            }
        return {
            "type": "message", "role": "assistant", "id": "owned-origin-final",
            "content": [{"type": "output_text", "text": "Owned origin tools completed"}],
        }

    def mcp_response(self, method, params):
        if method == "initialize":
            self.record("negotiated", requested=params["protocolVersion"],
                        selected="2025-06-18")
            return {
                "protocolVersion": "2025-06-18", "capabilities": {"tools": {}, "resources": {}},
                "serverInfo": {"name": "owned-origin-apps", "version": "1"},
            }
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [descriptor(connector) for _, connector in CALLS]}
        if method == "resources/list":
            return {"resources": []}
        if method == "resources/templates/list":
            return {"resourceTemplates": []}
        if method == "tools/call":
            index = len(self.tool_calls)
            assert index < 2, "Unexpected additional tool effect"
            _, connector = CALLS[index]
            assert params["name"] == connector + "_product_search"
            assert params["arguments"] == arguments(connector)
            thread_id = params.get("_meta", {}).get("threadId")
            assert isinstance(thread_id, str) and thread_id, "Missing native tool thread"
            self.tool_calls.append(connector)
            self.record("tool_call", connector=connector, arguments=params["arguments"],
                        thread_id=thread_id, sequence=index + 1)
            return result(connector)
        if method == "resources/read":
            assert params["uri"] == URI, "Unexpected resource URI reached peer"
            meta = params["_meta"]
            scope = meta["x-codex-turn-metadata"]["mcp_request_meta"]
            assert set(scope) == {"selected_connector_ids", "link_id"}, "Unexpected app scope"
            selected = scope["selected_connector_ids"]
            assert len(selected) == 1 and selected[0] in {"best_buy", "walmart"}
            connector = selected[0]
            assert scope["link_id"] == "link_" + connector, "Wrong native account link"
            assert isinstance(meta["threadId"], str) and meta["threadId"]
            self.record("resource_read", uri=URI, thread_id=meta["threadId"],
                        connector=connector, link_id=scope["link_id"])
            return {"contents": [{"uri": URI, "mimeType": "text/html",
                                  "text": "<html>" + connector + "</html>"}]}
        raise AssertionError("Unexpected MCP method: " + str(method))


def inside(args):
    root = args.root.resolve(strict=True)
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace != args.parent_netns, "BLOCKED_ENV: namespace unchanged"
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert [link["ifname"] for link in links] == ["lo"], "BLOCKED_ENV: nonloopback interface"
    assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    fixture = OriginFixture(root, {
        "parent": args.parent_netns, "child": namespace,
        "interfaces": ["lo"], "default_route": False,
    })
    native = None
    reader = None

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        environment = fixture.configure()
        with (root / "native-stderr.log").open("w") as stderr:
            native = subprocess.Popen(
                [str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=root / "workspace", env=environment, text=True, bufsize=1,
            )
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid())

        def forward_native():
            for line in native.stdout:
                # Pass through immutable native output; never manufacture frames.
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=forward_native, daemon=True)
        reader.start()
        while True:
            line = sys.stdin.buffer.readline(MAX_BODY + 1)
            if not line:
                break
            assert len(line) <= MAX_BODY and line.endswith(b"\n"), "Native input bound"
            wire = json.loads(line)
            assert wire.get("method") in ALLOWED_METHODS, "Forbidden app-server operation"
            fixture.record("native_input", method=wire["method"])
            native.stdin.write(line.decode())
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
            assert not reader.is_alive(), "Native output reader did not stop"
        fixture.close()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.codex = args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == NATIVE_SHA
    if not args.inside:
        assert sys.platform == "linux" and shutil.which("unshare") and shutil.which("ip"), (
            "BLOCKED_ENV: Linux/unshare/ip required"
        )
        os.execvp("unshare", [
            "unshare", "--user", "--map-root-user", "--net", "--fork", "--kill-child=TERM",
            sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net"),
        ])
    inside(args)


if __name__ == "__main__":
    main()
