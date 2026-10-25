#!/usr/bin/env python3
"""Owned resources-only Apps peer; only immutable Codex emits app-server frames."""
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

NATIVE_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
URI = "test://codex/resource"
PRIVATE_URI = "test://codex/private"
MCP_PATH = "/backend-api/ps/mcp"
MAX_BODY = 1_048_576
ALLOWED_METHODS = {
    "initialize", "initialized", "server/diagnostics", "thread/start", "thread/read",
    "thread/loaded/list", "thread/archive", "mcpServer/resource/read",
}
DENIED = {
    "code": -32042, "message": "resource authorization required",
    "data": {"fixture": "target-policy", "requiredConnector": "calendar",
             "requiredLink": "link_calendar"},
}


def request_scope(params):
    meta = params.get("_meta") or {}
    assert isinstance(meta, dict), "Invalid MCP metadata"
    scope = {key: meta[key] for key in ("connector_id", "link_id") if key in meta}
    if "x-codex-turn-metadata" in meta:
        turn = meta["x-codex-turn-metadata"]
        assert isinstance(turn, dict) and set(turn) == {"mcp_request_meta"}
        request = turn["mcp_request_meta"]
        assert isinstance(request, dict) and set(request) == {"selected_connector_ids"}
        scope["legacy_selected_connector_ids"] = request["selected_connector_ids"]
    return scope


def permitted_result(uri, scope):
    # A fixed peer policy supplies an independent oracle; never echo arbitrary inputs.
    if scope == {"connector_id": "calendar", "link_id": "link_calendar"}:
        return "Owned linked calendar resource\n"
    if uri != URI:
        return None
    if scope == {}:
        return "Owned generic resource\n"
    if scope == {"connector_id": "calendar", "link_id": None}:
        return "Owned public calendar resource\n"
    if scope == {"legacy_selected_connector_ids": ["calendar"]}:
        return "Owned legacy filtered resource\n"
    return None


class TargetFixture(AppsFixture):
    def __init__(self, root, namespace):
        self.root = root
        self.scenario = "enabled"
        self.product_sku = "codex"
        self.lock = threading.Lock()
        self.http_context = threading.local()
        self.journal = {"namespace": namespace, "events": []}
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None):
                data = b"" if value is None else json.dumps(value).encode()
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def do_GET(self):
                path = urlparse(self.path).path
                fixture.http_context.request = (self.command, path)
                if path == MCP_PATH:
                    self.reply(405)
                elif path == "/backend-api/wham/config/bundle":
                    self.reply(200, {})
                elif path == "/backend-api/wham/accounts/check":
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
                path = urlparse(self.path).path
                fixture.http_context.request = (self.command, path)
                assert path == MCP_PATH, "Forbidden model or other HTTP operation"
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size <= MAX_BODY, "Owned HTTP body bound"
                body = json.loads(self.rfile.read(size))
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
                result = fixture.mcp_response(method, body.get("params", {}))
                slot = "error" if result is DENIED else "result"
                self.reply(200, {"jsonrpc": "2.0", "id": body["id"], slot: result})

            def do_DELETE(self):
                path = urlparse(self.path).path
                fixture.http_context.request = (self.command, path)
                assert path == MCP_PATH
                self.reply(204)

        class OwnedServer(ThreadingHTTPServer):
            daemon_threads = True

            def handle_error(self, _request, _client_address):
                error_type, _, trace = sys.exc_info()
                while trace.tb_next is not None:
                    trace = trace.tb_next
                method, path = getattr(fixture.http_context, "request", (None, None))
                fixture.record("fatal", stage="http-handler", method=method, path=path,
                               source_line=trace.tb_lineno, error_type=error_type.__name__)

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
            pending = self.root / "target-journal.pending"
            pending.write_text(data)
            pending.replace(self.root / "target-journal.json")

    def configure(self):
        environment = super().configure()
        config = self.root / "codex/config.toml"
        config.write_text(
            'approval_policy = "on-request"\nsandbox_mode = "read-only"\n'
            'analytics.enabled = false\nmcp_oauth_credentials_store = "file"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + config.read_text()
        )
        environment.update({
            "CODEX_DISABLE_REMOTE_CONTROL": "1", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
        })
        return environment

    def mcp_response(self, method, params):
        if method == "initialize":
            self.record("negotiated", requested=params["protocolVersion"], selected="2025-06-18")
            return {
                "protocolVersion": "2025-06-18", "capabilities": {"resources": {}},
                "serverInfo": {"name": "owned-target-resources", "version": "1"},
            }
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": []}
        if method == "resources/list":
            return {"resources": []}
        if method == "resources/templates/list":
            return {"resourceTemplates": []}
        assert method == "resources/read", "Forbidden model/tool or MCP operation"
        assert params["uri"] in {URI, PRIVATE_URI}, "Unexpected resource URI reached peer"
        scope = request_scope(params)
        text = permitted_result(params["uri"], scope)
        fixture_result = "accepted" if text is not None else "denied"
        self.record("resource_read", uri=params["uri"], scope=scope, result=fixture_result)
        if text is None:
            return DENIED
        return {"contents": [{"uri": params["uri"], "mimeType": "text/plain", "text": text}]}


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
    fixture = TargetFixture(root, {
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

        def output():
            for line in native.stdout:
                # Forward exact immutable-native output; never synthesize protocol frames.
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        while True:
            line = sys.stdin.buffer.readline(MAX_BODY + 1)
            if not line:
                break
            assert len(line) <= MAX_BODY and line.endswith(b"\n"), "Native input bound"
            wire = json.loads(line)
            assert wire.get("method") in ALLOWED_METHODS, "Forbidden app-server operation"
            fixture.record("native_input", method=wire["method"])
            if wire["method"] == "mcpServer/resource/read":
                params = wire["params"]
                fixture.record(
                    "resource_request_shape", target_present="target" in params,
                    target_null="target" in params and params["target"] is None,
                    thread_present="threadId" in params, origin_present="originCallId" in params,
                )
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
