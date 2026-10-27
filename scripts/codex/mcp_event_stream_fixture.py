#!/usr/bin/env python3
"""One owned Apps MCP HTTP/SSE dependency; never an app-server peer."""
import argparse
import base64
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import select
import signal
import socket
import sys
import threading
import time
from urllib.parse import urlparse


MCP_PATH = "/api/codex/ps/mcp"
EVENT_NAME = "owned.updated"
EVENT_DATA = {"value": "λ🙂", "nested": [1, None, False], "marker": "OWNED_NATIVE_EVENT"}
MAX_BYTES = 65_536


def encoded(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")


def print_message(value):
    line = json.dumps(value, ensure_ascii=False)
    assert len(line.encode()) <= MAX_BYTES, "Owned fixture control response limit"
    print(line, flush=True)


class Fixture:
    def __init__(self, root):
        self.root = root
        self.lock = threading.RLock()
        self.closing = threading.Event()
        self.requests = []
        self.errors = []
        self.stream = None
        self.actions = queue.Queue(maxsize=4)
        self.closed = False
        class Server(ThreadingHTTPServer):
            daemon_threads = False

        self.server = Server(("127.0.0.1", 0), self.handler())
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       kwargs={"poll_interval": 0.05})
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"
        self.configure()
        self.thread.start()

    def handler(self):
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value, session=False):
                body = json.dumps(value).encode()
                assert len(body) <= MAX_BYTES, "Owned MCP response limit"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                if session:
                    self.send_header("Mcp-Session-Id", "owned-event-session")
                self.end_headers()
                self.wfile.write(body)
                self.close_connection = True

            def do_GET(self):
                path = urlparse(self.path).path
                if path == "/api/codex/wham/accounts/check":
                    self.reply(200, {"accounts": [{"id": "owned-event-account",
                        "workspace_backend_origin": fixture.base_url,
                        "account_routing_override": "NO_CONSTRAINT"}]})
                elif path in {"/api/codex/wham/config/bundle", "/api/codex/wham/settings/user"}:
                    self.reply(200, {})
                elif path == MCP_PATH:
                    self.reply(405, {})
                else:
                    self.reply(404, {})

            def do_DELETE(self):
                self.reply(405, {})

            def do_POST(self):
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    assert urlparse(self.path).path == MCP_PATH, "Unexpected owned HTTP route"
                    assert 0 < size <= MAX_BYTES, "Owned MCP request limit"
                    body = self.rfile.read(size)
                    assert len(body) == size, "Incomplete owned MCP body"
                    message = json.loads(body)
                    method = message["method"]
                    with fixture.lock:
                        assert len(fixture.requests) < 64, "Owned MCP request count limit"
                        fixture.requests.append(message)
                    if method == "initialize":
                        self.reply(200, {"jsonrpc": "2.0", "id": message["id"], "result": {
                            "protocolVersion": "2025-06-18", "capabilities": {},
                            "serverInfo": {"name": "owned-event-peer", "version": "1.0.0"}}},
                            session=True)
                    elif method == "notifications/initialized":
                        self.reply(202, {})
                    elif method == "tools/list":
                        self.reply(200, {"jsonrpc": "2.0", "id": message["id"],
                                         "result": {"tools": []}})
                    elif method == "ping":
                        self.reply(200, {"jsonrpc": "2.0", "id": message["id"], "result": {}})
                    elif method == "events/stream":
                        self.event_stream(message)
                    else:
                        raise AssertionError("Unexpected owned MCP method")
                except Exception as failure:
                    with fixture.lock:
                        fixture.errors.append(type(failure).__name__)
                    self.close_connection = True

            def event_stream(self, message):
                with fixture.lock:
                    assert fixture.stream is None, "Unexpected second owned stream"
                    fixture.stream = {"requestId": message["id"], "params": message["params"],
                        "sent": [], "peerClosed": False, "finished": False}
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.flush()
                deadline = time.monotonic() + 45
                try:
                    while not fixture.closing.is_set():
                        assert time.monotonic() < deadline, "Owned MCP stream deadline"
                        readable, _, _ = select.select([self.connection], [], [], 0)
                        if readable:
                            try:
                                eof = self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b""
                            except BlockingIOError:
                                eof = False
                            except ConnectionResetError:
                                eof = True
                            if eof:
                                with fixture.lock:
                                    fixture.stream["peerClosed"] = True
                                break
                        try:
                            kind = fixture.actions.get(timeout=0.01)
                        except queue.Empty:
                            continue
                        metadata = {"io.modelcontextprotocol/subscriptionId": message["id"],
                                    "provider": "owned-events"}
                        params = {"_meta": metadata}
                        if kind == "active":
                            params["status"] = "active"
                        else:
                            params.update(name=EVENT_NAME, data=EVENT_DATA)
                        notification = {"jsonrpc": "2.0", "method": "notifications/events/" + kind,
                                        "params": params}
                        body = json.dumps(notification, ensure_ascii=False)
                        assert len(body.encode()) <= 4096, "Owned event body limit"
                        self.wfile.write(("event: message\ndata: " + body + "\n\n").encode())
                        self.wfile.flush()
                        with fixture.lock:
                            fixture.stream["sent"].append(notification)
                finally:
                    with fixture.lock:
                        fixture.stream["finished"] = True
                    self.close_connection = True

        return Handler

    def configure(self):
        codex = self.root / "codex"
        catalog = codex / "models.json"
        catalog.write_text(json.dumps({"models": [{"slug": "owned-event-model",
            "display_name": "Owned unused event model", "supported_reasoning_levels": [],
            "shell_type": "unified_exec", "visibility": "list", "supported_in_api": True,
            "priority": 1, "model_messages": {"instructions_template": "Owned inert MCP event fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]}))
        (codex / "config.toml").write_text(f'''model = "owned-event-model"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{self.base_url}/api/codex"
openai_base_url = "{self.base_url}/v1"
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[memories]
generate_memories = false
use_memories = false
[skills.bundled]
enabled = false
[features]
apps = true
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
memories = false
shell_snapshot = false
hooks = false
''')
        # Fixed synthetic startup data only. No credential/header behavior is
        # inspected, varied, recorded or asserted by this ordinary I/O fixture.
        token = ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
            "email": "owned-event@synthetic.invalid", "exp": int(time.time()) + 86400,
            "https://api.openai.com/auth": {"chatgpt_account_id": "owned-event-account",
                "chatgpt_user_id": "owned-event-user", "chatgpt_plan_type": "pro"}}), "c3ludGhldGlj"])
        (codex / "auth.json").write_text(json.dumps({"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
            "tokens": {"id_token": token, "access_token": "synthetic-owned-event-access",
                "refresh_token": "synthetic-owned-event-refresh", "account_id": "owned-event-account"},
            "last_refresh": datetime.now(timezone.utc).isoformat()}))

    def snapshot(self):
        with self.lock:
            result = {"requests": self.requests, "stream": self.stream, "errors": self.errors,
                "listenerClosed": self.server.socket.fileno() == -1,
                "threadAlive": self.thread.is_alive()}
            return json.loads(json.dumps(result))

    def close(self):
        if self.closed:
            return
        self.closing.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        assert not self.thread.is_alive(), "Owned HTTP server thread did not stop"
        self.closed = True


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    root = parser.parse_args().root.resolve(strict=True)
    fixture = Fixture(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        print_message({"pid": os.getpid(), "baseUrl": fixture.base_url})
        while True:
            line = sys.stdin.buffer.readline(4097)
            if not line:
                break
            assert 0 < len(line) <= 4096, "Owned fixture control request limit"
            request = json.loads(line)
            operation = request["op"]
            if operation in {"active", "event"}:
                fixture.actions.put_nowait(operation)
                result = {"queued": operation}
            elif operation == "state":
                result = fixture.snapshot()
            elif operation == "close":
                fixture.close()
                result = fixture.snapshot()
            else:
                raise AssertionError("Unexpected owned fixture control")
            print_message({"id": request["id"], "result": result})
            if operation == "close":
                break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
