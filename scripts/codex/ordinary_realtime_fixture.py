#!/usr/bin/env python3
"""Finite loopback WebSocket peer for an ordinary native realtime start/stop.

Only functional paths and WebSocket messages enter the journal. This peer never
implements app-server requests, produces model output, or journals HTTP headers.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import socketserver
import struct
import sys
import threading
import time


MODEL = "owned-v432-realtime-model"
PROMPT = "Owned local realtime start"
ACK = {"type": "session.updated", "session": {
    "id": "owned-v432-peer-session", "instructions": PROMPT}}
MAX_FRAME = 65_536
MAX_FRAMES = 32
MAX_JOURNAL = 2_097_152
MAX_HEADERS = 8192


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    assert len(encoded) <= MAX_JOURNAL, "Owned realtime journal overflow"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


class PeerHandler(socketserver.BaseRequestHandler):
    def handle(self):
        fixture = self.server.fixture
        self.websocket = False
        self.request.settimeout(0.2)
        with fixture.lock:
            fixture.sockets.add(self.request)
        try:
            self.handle_request(fixture)
        except Exception as failure:
            if not fixture.stopping.is_set():
                fixture.fail(type(failure).__name__)
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.request.close()
            with fixture.lock:
                fixture.sockets.discard(self.request)
                if self.websocket:
                    fixture.state["activeConnections"] = 0
                fixture.save_locked()

    def read_exact(self, count, fixture, deadline):
        assert 0 <= count <= MAX_FRAME
        result = bytearray()
        while len(result) < count:
            if fixture.stopping.is_set():
                raise EOFError("Owned peer stopping")
            assert time.monotonic() < deadline, "Owned realtime socket deadline"
            try:
                chunk = self.request.recv(count - len(result))
            except socket.timeout:
                continue
            if not chunk:
                if not result:
                    return None
                raise EOFError("Owned incomplete frame")
            result.extend(chunk)
        return bytes(result)

    def handle_request(self, fixture):
        # Parse a bounded HTTP upgrade in memory; retain only method/path.
        header = bytearray()
        deadline = time.monotonic() + 5
        while not header.endswith(b"\r\n\r\n"):
            assert len(header) < MAX_HEADERS, "Owned HTTP header limit"
            byte = self.read_exact(1, fixture, deadline)
            if byte is None:
                raise EOFError("Owned incomplete HTTP request")
            header.extend(byte)
        lines = bytes(header).decode("iso-8859-1").split("\r\n")
        method, path, version = lines[0].split(" ")
        assert version == "HTTP/1.1"
        fields = {}
        for line in lines[1:]:
            if line:
                name, value = line.split(":", 1)
                fields[name.lower()] = value.strip()

        if method != "GET" or path != f"/v1/realtime?model={MODEL}":
            with fixture.lock:
                if method == "POST" and path == "/v1/responses":
                    fixture.state["responsesRequests"] += 1
                fixture.state["otherHttp"].append({"method": method, "path": path})
                fixture.save_locked()
            self.request.sendall(b"HTTP/1.1 500 Unexpected fixture request\r\n"
                                 b"Content-Length: 0\r\nConnection: close\r\n\r\n")
            raise ValueError("Unexpected ordinary peer path")

        assert fields.get("upgrade", "").lower() == "websocket"
        assert "upgrade" in fields.get("connection", "").lower()
        key = fields["sec-websocket-key"]
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        self.request.sendall(b"HTTP/1.1 101 Switching Protocols\r\n"
                             b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                             b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        # No header value is retained by the fixture state or error reporting.
        del fields, header, lines, key, accept
        with fixture.lock:
            fixture.state["paths"].append(path)
            assert len(fixture.state["paths"]) == 1, "Extra owned realtime connection"
            fixture.state["activeConnections"] = 1
            self.websocket = True
            fixture.save_locked()

        deadline = time.monotonic() + 25
        while not fixture.stopping.is_set():
            first = self.read_exact(2, fixture, deadline)
            if first is None:
                return
            assert first[0] & 0x80 and not first[0] & 0x70, "Owned unfragmented frame required"
            opcode = first[0] & 0x0F
            assert first[1] & 0x80, "Owned client frame must be masked"
            size = first[1] & 0x7F
            if size == 126:
                size = struct.unpack("!H", self.read_exact(2, fixture, deadline))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.read_exact(8, fixture, deadline))[0]
            assert size <= MAX_FRAME, "Owned WebSocket frame overflow"
            if opcode >= 8:
                assert size <= 125
            mask = self.read_exact(4, fixture, deadline)
            payload = self.read_exact(size, fixture, deadline)
            assert payload is not None
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            fixture.record_frame()
            if opcode == 8:
                self.send_frame(fixture, 8, payload)
                return
            if opcode == 9:
                self.send_frame(fixture, 10, payload)
                continue
            if opcode == 10:
                continue
            assert opcode == 1, "Unexpected owned realtime frame opcode"
            message = json.loads(payload.decode("utf-8"))
            assert isinstance(message, dict) and message.get("type") == "session.update"
            assert message["session"]["type"] == "realtime"
            assert message["session"]["instructions"] == PROMPT
            assert message["session"]["output_modalities"] == ["text"]
            with fixture.lock:
                fixture.state["messages"].append(message)
                assert len(fixture.state["messages"]) == 1, "Extra owned session.update"
                fixture.save_locked()
            self.send_frame(fixture, 1, json.dumps(ACK, separators=(",", ":")).encode())
            with fixture.lock:
                fixture.state["sent"].append(ACK)
                fixture.save_locked()

    def send_frame(self, fixture, opcode, payload):
        assert len(payload) <= MAX_FRAME
        fixture.record_frame()
        if len(payload) < 126:
            header = bytes([0x80 | opcode, len(payload)])
        elif len(payload) <= 65_535:
            header = bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload))
        else:
            header = bytes([0x80 | opcode, 127]) + struct.pack("!Q", len(payload))
        self.request.sendall(header + payload)


class PeerServer(socketserver.TCPServer):
    allow_reuse_address = False

    def process_request(self, request, address):
        fixture = self.fixture
        with fixture.lock:
            full = len(fixture.handlers) >= 2
            fixture.state["requestCount"] += 1
            full = full or fixture.state["requestCount"] > 4
            fixture.save_locked()
            if not full and not fixture.stopping.is_set():
                worker = threading.Thread(target=self.run_request,
                    args=(request, address), name="owned-realtime-handler", daemon=False)
                fixture.handlers.add(worker)
            else:
                worker = None
        if worker is None:
            self.shutdown_request(request)
            if not fixture.stopping.is_set():
                fixture.fail("OwnedHandlerLimit")
        else:
            worker.start()

    def run_request(self, request, address):
        try:
            self.finish_request(request, address)
        except Exception as failure:
            if not self.fixture.stopping.is_set():
                self.fixture.fail(type(failure).__name__)
        finally:
            self.shutdown_request(request)
            with self.fixture.lock:
                self.fixture.handlers.discard(threading.current_thread())


class OrdinaryRealtimePeer:
    def __init__(self, root):
        self.root = root
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.sockets = set()
        self.handlers = set()
        self.state = {"paths": [], "messages": [], "sent": [], "frameCount": 0,
                      "responsesRequests": 0, "otherHttp": [],
                      "activeConnections": 0, "requestCount": 0, "errors": []}
        self.server = PeerServer(("127.0.0.1", 0), PeerHandler)
        self.server.fixture = self
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.05),
            name="owned-ordinary-realtime", daemon=False)
        with self.lock:
            self.save_locked()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def save_locked(self):
        write_json(self.root / "peer.json", self.state)

    def record_frame(self):
        with self.lock:
            self.state["frameCount"] += 1
            assert self.state["frameCount"] <= MAX_FRAMES, "Owned WebSocket frame count overflow"
            self.save_locked()

    def fail(self, kind):
        with self.lock:
            assert len(self.state["errors"]) < 8
            self.state["errors"].append(kind)
            self.save_locked()

    def config(self):
        catalog = self.root / "codex/models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary realtime fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned ordinary realtime instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        (self.root / "codex/config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
experimental_realtime_ws_base_url = "{self.url}/v1"
experimental_realtime_ws_model = "{MODEL}"
experimental_realtime_ws_backend_prompt = ""
experimental_realtime_ws_startup_context = ""
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[memories]
generate_memories = false
use_memories = false
[features]
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = false
realtime_conversation = true
[model_providers.fixture]
name = "Owned ordinary realtime provider"
base_url = "{self.url}/v1"
wire_api = "responses"
env_key = "SAMGITA_ORDINARY_REALTIME_FIXTURE_KEY"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def close(self):
        self.stopping.set()
        # Close sockets before joining bounded handlers. The second slot lets an
        # unintended Responses request be observed while the WS is still open.
        with self.lock:
            sockets = list(self.sockets)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        if self.thread.ident is not None:
            self.server.shutdown()
        with self.lock:
            sockets = list(self.sockets)
            handlers = list(self.handlers)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        for handler in handlers:
            handler.join(timeout=2)
            assert not handler.is_alive(), "Owned realtime handler did not stop"
        self.server.server_close()
        assert self.server.socket.fileno() == -1, "Owned realtime listener did not close"
        if self.thread.ident is not None:
            self.thread.join(timeout=2)
        assert not self.thread.is_alive(), "Owned realtime server thread did not stop"
        with self.lock:
            assert not self.sockets, "Owned realtime handler socket did not close"
            assert not self.handlers, "Owned realtime handler thread did not stop"
            self.save_locked()
        write_json(self.root / "peer-closed.json", {
            "activeSockets": len(self.sockets), "handlerThreads": len(self.handlers),
            "threadAlive": self.thread.is_alive(),
            "serverClosed": self.server.socket.fileno() == -1})


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    root = parser.parse_args().root.resolve(strict=True)
    peer = OrdinaryRealtimePeer(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        peer.config()
        peer.thread.start()
        print(json.dumps({"url": peer.url, "pid": os.getpid()}), flush=True)
        sys.stdin.buffer.read(1)
    finally:
        peer.close()


if __name__ == "__main__":
    main()
