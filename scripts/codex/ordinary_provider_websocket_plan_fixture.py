#!/usr/bin/env python3
"""Finite ordinary Responses WebSocket dependency.

Stock Codex emits app-server messages. This peer supplies one generate=false
prewarm, one assistant response and quota metadata; no account or model engine.
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
import traceback

MAX_FRAME = 262_144
MAX_HEADERS = 8192
MAX_JOURNAL = 2_097_152
ACCEPT_POLL_SECONDS = 0.05
CLEANUP_SECONDS = 0.75
MODEL = "mock-model"
INPUT = "Owned ordinary provider WebSocket quota metadata λ🙂"
ANSWER = "Owned provider WebSocket quota response β🙂"
PREWARM_ID = "owned-provider-plan-prewarm"
RESPONSE_ID = "owned-provider-plan-response"
ITEM_ID = "owned-provider-plan-message"
RATE = {
    "type": "codex.rate_limits", "plan_type": "pro",
    "metered_limit_name": "owned-provider-plan",
    "rate_limits": {
        "primary": {"used_percent": 12.5, "window_minutes": 60, "reset_at": 1_704_069_000},
        "secondary": {"used_percent": 73.4, "window_minutes": 10_080, "reset_at": 1_704_673_800},
    },
}


def write_json(path, value):
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    assert len(data) <= MAX_JOURNAL, "Owned provider journal bound"
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_bytes(data)
    pending.replace(path)


class PeerHandler(socketserver.BaseRequestHandler):
    def handle(self):
        peer = self.server.peer
        self.websocket = False
        try:
            self.request.settimeout(0.2)
            self.exchange(peer)
        except Exception as error:
            if not peer.stopping.is_set():
                line = traceback.extract_tb(error.__traceback__)[-1].lineno
                peer.fail(f"{type(error).__name__}:line{line}")
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.request.close()
            with peer.lock:
                peer.sockets.discard(self.request)
                if self.websocket:
                    peer.state["activeConnections"] = 0
                    peer.state["connectionClosures"] += 1
                peer.save_locked()
            if self.websocket and not peer.stopping.is_set():
                print(json.dumps({"event": "provider_closed"}), flush=True)

    def read_exact(self, size, peer, deadline):
        assert 0 <= size <= MAX_FRAME
        data = bytearray()
        while len(data) < size:
            if peer.stopping.is_set():
                raise EOFError("Owned provider stopping")
            assert time.monotonic() < deadline, "Owned provider socket deadline"
            try:
                part = self.request.recv(size - len(data))
            except socket.timeout:
                continue
            if not part:
                if not data:
                    return None
                raise EOFError("Owned incomplete provider frame")
            data.extend(part)
        return bytes(data)

    def exchange(self, peer):
        header = bytearray()
        deadline = time.monotonic() + 5
        while not header.endswith(b"\r\n\r\n"):
            assert len(header) < MAX_HEADERS, "Owned upgrade request bound"
            byte = self.read_exact(1, peer, deadline)
            if byte is None:
                raise EOFError("Owned incomplete upgrade")
            header.extend(byte)
        lines = bytes(header).decode("iso-8859-1").split("\r\n")
        method, path, version = lines[0].split(" ")
        with peer.lock:
            peer.state["http"].append({"method": method, "path": path})
            peer.save_locked()
        if (method, path, version) != ("GET", "/v1/responses", "HTTP/1.1"):
            self.request.sendall(b"HTTP/1.1 500 Unexpected fixture request\r\n"
                                 b"Content-Length: 0\r\nConnection: close\r\n\r\n")
            raise ValueError("Unexpected ordinary provider route")
        fields = {}
        for line in lines[1:]:
            if line:
                name, value = line.split(":", 1)
                fields[name.lower()] = value.strip()
        # Required transport framing only. No credential/header value enters
        # the journal and no identity, permission or header outcome is tested.
        assert fields.get("upgrade", "").lower() == "websocket"
        assert "upgrade" in fields.get("connection", "").lower()
        key = fields["sec-websocket-key"]
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        self.request.sendall(b"HTTP/1.1 101 Switching Protocols\r\n"
                             b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                             b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        del header, lines, fields, key, accept
        with peer.lock:
            peer.state["connections"] += 1
            assert peer.state["connections"] == 1, "Extra provider connection"
            peer.state["activeConnections"] = 1
            self.websocket = True
            peer.save_locked()

        deadline = time.monotonic() + 35
        while not peer.stopping.is_set():
            first = self.read_exact(2, peer, deadline)
            if first is None:
                return
            assert first[0] & 0x80 and not first[0] & 0x70, "Owned unfragmented provider frame"
            opcode = first[0] & 0x0F
            assert first[1] & 0x80, "Owned native client frame is masked"
            size = first[1] & 0x7F
            if size == 126:
                size = struct.unpack("!H", self.read_exact(2, peer, deadline))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.read_exact(8, peer, deadline))[0]
            assert size <= MAX_FRAME, "Owned provider frame bound"
            if opcode >= 8:
                assert size <= 125
            mask = self.read_exact(4, peer, deadline)
            payload = self.read_exact(size, peer, deadline)
            assert payload is not None
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            peer.frame_received()
            if opcode == 8:
                self.send_frame(peer, 8, payload)
                return
            if opcode == 9:
                self.send_frame(peer, 10, payload)
                continue
            if opcode == 10:
                continue
            assert opcode == 1, "Unexpected ordinary provider opcode"
            raw = payload.decode("utf-8")
            request = json.loads(raw)
            assert request["type"] == "response.create" and request["model"] == MODEL
            with peer.lock:
                index = len(peer.state["requests"])
            assert index < 2, "Extra ordinary response request"
            markers = [part.get("text") for item in request["input"] if item.get("role") == "user"
                       for part in item.get("content", []) if part.get("type") == "input_text"
                       and part.get("text") == INPUT]
            if index == 0:
                assert request.get("generate") is False and markers == []
                kind = "prewarm"
                events = [
                    {"type": "response.created", "response": {"id": PREWARM_ID}},
                    {"type": "response.completed", "response": {"id": PREWARM_ID,
                        "usage": {"input_tokens": 0, "input_tokens_details": None,
                                  "output_tokens": 0, "output_tokens_details": None,
                                  "total_tokens": 0}}},
                ]
            else:
                assert "generate" not in request and markers == [INPUT]
                assert request.get("previous_response_id") in [None, PREWARM_ID]
                kind = "generation"
                events = [
                    {"type": "response.created", "response": {"id": RESPONSE_ID}},
                    RATE,
                    {"type": "response.output_item.done", "item": {
                        "id": ITEM_ID, "type": "message", "role": "assistant",
                        "content": [{"type": "output_text", "text": ANSWER}]}},
                    {"type": "response.completed", "response": {"id": RESPONSE_ID,
                        "usage": {"input_tokens": 7, "input_tokens_details": None,
                                  "output_tokens": 3, "output_tokens_details": None,
                                  "total_tokens": 10}}},
                ]
            with peer.lock:
                peer.state["requests"].append({"kind": kind, "raw": raw, "request": request})
                peer.save_locked()
                write_json(peer.args.requests_file, peer.state["requests"])
            for event in events:
                raw = json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode()
                self.send_frame(peer, 1, raw)
            print(json.dumps({"event": "prewarm_served" if index == 0 else "generation_served"}), flush=True)

    def send_frame(self, peer, opcode, payload):
        assert len(payload) <= MAX_FRAME
        if len(payload) < 126:
            header = bytes([0x80 | opcode, len(payload)])
        elif len(payload) <= 65_535:
            header = bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload))
        else:
            header = bytes([0x80 | opcode, 127]) + struct.pack("!Q", len(payload))
        frame = header + payload
        self.request.sendall(frame)
        with peer.lock:
            peer.state["sentFrames"] += 1
            assert peer.state["sentFrames"] <= 10, "Owned sent frame count bound"
            if opcode == 1:
                peer.state["sent"].append({"raw": payload.decode("utf-8"),
                                          "frame": base64.b64encode(frame).decode()})
            peer.save_locked()


class PeerServer(socketserver.TCPServer):
    allow_reuse_address = False

    def process_request(self, request, address):
        peer = self.peer
        with peer.lock:
            peer.state["httpCount"] += 1
            full = len(peer.handlers) >= 2 or peer.state["httpCount"] > 2
            peer.save_locked()
            if not full and not peer.stopping.is_set():
                worker = threading.Thread(target=self.run_request, args=(request, address),
                    name="owned-provider-plan-handler", daemon=False)
                peer.handlers.add(worker)
                # Registration and start share the admission lock. Once the
                # accept loop joins, no registered worker can be unstarted.
                peer.sockets.add(request)
                try:
                    worker.start()
                except Exception:
                    peer.handlers.discard(worker)
                    peer.sockets.discard(request)
                    self.shutdown_request(request)
                    raise
            else:
                worker = None
        if worker is None:
            self.shutdown_request(request)
            if not peer.stopping.is_set():
                peer.fail("OwnedProviderHandlerLimit")

    def run_request(self, request, address):
        try:
            self.finish_request(request, address)
        finally:
            self.shutdown_request(request)
            with self.peer.lock:
                self.peer.handlers.discard(threading.current_thread())


class ProviderPeer:
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.sockets = set()
        self.handlers = set()
        self.state = {"pid": os.getpid(), "http": [], "httpCount": 0,
                      "connections": 0, "activeConnections": 0, "connectionClosures": 0,
                      "receivedFrames": 0, "sentFrames": 0, "requests": [], "sent": [], "errors": []}
        self.server = PeerServer(("127.0.0.1", 0), PeerHandler)
        self.server.peer = self
        self.server.socket.settimeout(ACCEPT_POLL_SECONDS)
        self.thread = threading.Thread(target=self.accept_loop,
                                       name="owned-provider-plan-server", daemon=False)
        self.save_locked()

    def accept_loop(self):
        # No BaseServer.serve_forever/shutdown handshake: even an idle accept
        # checks stopping every50ms. Only this thread admits handler workers.
        while not self.stopping.is_set():
            try:
                request, address = self.server.get_request()
            except socket.timeout:
                continue
            except OSError:
                if self.stopping.is_set():
                    return
                raise
            # If stop raced with accept, process_request rejects/closes the
            # socket under the same admission lock instead of starting a worker.
            self.server.process_request(request, address)

    def save_locked(self):
        write_json(self.root / "provider-websocket-plan-peer.json", self.state)

    def fail(self, error):
        with self.lock:
            assert len(self.state["errors"]) < 8
            self.state["errors"].append(error)
            self.save_locked()

    def frame_received(self):
        with self.lock:
            self.state["receivedFrames"] += 1
            assert self.state["receivedFrames"] <= 6, "Owned received frame count bound"
            self.save_locked()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def configure(self):
        catalog = self.args.codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": MODEL, "display_name": "Owned ordinary provider WebSocket model",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned ordinary provider metadata response."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        (self.args.codex_home / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
[features]
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = false
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
name = "Owned ordinary provider WebSocket dependency"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = true
request_max_retries = 0
stream_max_retries = 0
''')
        write_json(self.args.requests_file, [])

    def close(self):
        deadline = time.monotonic() + CLEANUP_SECONDS
        self.stopping.set()
        # Socket close does not wait for handler threads. The accept-loop join
        # fences all accepted-but-not-yet-admitted sockets before the snapshot.
        self.server.server_close()
        if self.thread.ident is not None:
            self.thread.join(timeout=max(deadline - time.monotonic(), 0))
        assert not self.thread.is_alive(), "Owned provider listener thread did not stop"
        assert self.lock.acquire(timeout=max(deadline - time.monotonic(), 0)), \
            "Owned provider cleanup snapshot lock deadline"
        try:
            sockets = list(self.sockets)
            handlers = list(self.handlers)
        finally:
            self.lock.release()
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        for handler in handlers:
            handler.join(timeout=max(deadline - time.monotonic(), 0))
            assert not handler.is_alive(), "Owned provider handler did not stop"
        assert self.lock.acquire(timeout=max(deadline - time.monotonic(), 0)), \
            "Owned provider cleanup final lock deadline"
        try:
            assert not self.sockets and not self.handlers, "Owned provider runtime not closed"
            self.save_locked()
            write_json(self.root / "provider-websocket-plan-closed.json", {
                "activeSockets": len(self.sockets), "handlerThreads": len(self.handlers),
                "threadAlive": self.thread.is_alive(), "serverClosed": self.server.socket.fileno() == -1})
            assert time.monotonic() <= deadline, "Owned provider cleanup deadline"
        finally:
            self.lock.release()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-provider-websocket-plan"])
    peer = ProviderPeer(parser.parse_args())

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        peer.configure()
        peer.thread.start()
        print(json.dumps({"url": peer.url}), flush=True)
        sys.stdin.buffer.read(1)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        peer.close()


if __name__ == "__main__":
    main()
