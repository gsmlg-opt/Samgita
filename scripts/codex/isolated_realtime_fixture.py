#!/usr/bin/env python3
"""Owned loopback realtime backend, never a Codex app-server emulator.

Only stdlib is used. stdin commands explicitly emit synthetic backend events or
close a selected WebSocket; journals separate handshakes, native frames and
control completion. Responses requests are counted and rejected, never answered.
"""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import struct
import sys
import threading


TOKEN = "SYNTHETIC_REALTIME_ONLY"


def frame(payload, opcode=1):
    size = len(payload)
    if size < 126:
        return bytes([128 | opcode, size]) + payload
    if size < 65536:
        return bytes([128 | opcode, 126]) + struct.pack("!H", size) + payload
    return bytes([128 | opcode, 127]) + struct.pack("!Q", size) + payload


def read_frame(stream):
    head = stream.read(2)
    if not head:
        return None
    if len(head) != 2 or not head[0] & 128 or not head[1] & 128:
        raise ValueError("Expected complete masked client frame")
    size = head[1] & 127
    if size == 126:
        size = struct.unpack("!H", stream.read(2))[0]
    elif size == 127:
        size = struct.unpack("!Q", stream.read(8))[0]
    if size > 4194304:
        raise ValueError("Fixture frame limit")
    key = stream.read(4)
    payload = stream.read(size)
    if len(key) != 4 or len(payload) != size:
        raise ValueError("Incomplete fixture frame")
    return head[0] & 15, bytes(value ^ key[index % 4] for index, value in enumerate(payload))


class RealtimeFixture:
    def __init__(self, args):
        self.root = Path(args.codex_home).parent
        self.requests_file = Path(args.requests_file)
        self.requests = []
        self.journal = []
        self.lock = threading.Lock()
        self.peers = {}
        self.next_id = 0
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                data = self.rfile.read(min(size, 4194304))
                with fixture.lock:
                    fixture.requests.append({"path": self.path, "body": data.decode()})
                    fixture.atomic(fixture.requests_file, fixture.requests)
                self.send_error(500, "No model calls authorized in realtime profile")

            def do_GET(self):
                if self.headers.get("Upgrade", "").lower() != "websocket":
                    self.send_error(404)
                    return
                accept = base64.b64encode(hashlib.sha1((self.headers["Sec-WebSocket-Key"] +
                    "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                with fixture.lock:
                    fixture.next_id += 1
                    identity = fixture.next_id
                    peer = {"socket": self.connection, "lock": threading.Lock()}
                    fixture.peers[identity] = peer
                fixture.record("handshake", connection=identity, path=self.path,
                               authorization=self.headers.get("Authorization"),
                               headers={name.lower(): value for name, value in self.headers.items()
                                        if name.lower() in {"x-session-id", "x-codex-session-id",
                                                            "originator"}})
                self.send_response(101)
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", accept)
                self.end_headers()
                self.wfile.flush()
                try:
                    while True:
                        incoming = read_frame(self.rfile)
                        if incoming is None or incoming[0] == 8:
                            return
                        opcode, payload = incoming
                        if opcode == 9:
                            fixture.send(identity, payload, 10)
                        elif opcode == 1:
                            message = json.loads(payload)
                            fixture.record("native_frame", connection=identity, message=message)
                            if message["type"] == "session.update":
                                fixture.send_json(identity, {"type": "session.updated", "session": {
                                    "id": f"synthetic-backend-{identity}",
                                    "instructions": message["session"]["instructions"]}})
                        else:
                            raise ValueError("Unsupported client frame")
                except (ConnectionError, OSError, ValueError) as error:
                    fixture.record("peer_end", connection=identity, detail=type(error).__name__)
                finally:
                    with fixture.lock:
                        fixture.peers.pop(identity, None)
                    fixture.record("peer_closed", connection=identity)
                    self.close_connection = True

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.atomic(self.requests_file, [])
        self.record("ready")
        endpoint = f"http://127.0.0.1:{self.server.server_port}"
        Path(args.codex_home, "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
chatgpt_base_url = "{endpoint}"
openai_base_url = "{endpoint}/v1"
experimental_realtime_ws_base_url = "ws://127.0.0.1:{self.server.server_port}"
experimental_realtime_ws_backend_prompt = "Synthetic configured prompt"
experimental_realtime_ws_startup_context = "Synthetic startup context"
experimental_realtime_ws_model = "synthetic-configured-realtime"
[realtime]
version = "v2"
type = "conversational"
[features]
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned no-inference realtime fixture"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
experimental_bearer_token = "{TOKEN}"
request_max_retries = 0
stream_max_retries = 0
''')

    @staticmethod
    def atomic(path, value):
        pending = path.with_suffix(".pending")
        pending.write_text(json.dumps(value))
        pending.replace(path)

    def record(self, event, **fields):
        with self.lock:
            self.journal.append({"event": event, **fields})
            self.atomic(self.root / "realtime-journal.json", self.journal)

    def send(self, identity, payload, opcode=1):
        with self.lock:
            peer = self.peers[identity]
        with peer["lock"]:
            peer["socket"].sendall(frame(payload, opcode))

    def send_json(self, identity, value):
        self.send(identity, json.dumps(value).encode())

    def control(self, command):
        identity = command.get("connection")
        if command["action"] == "emit":
            for event in command["events"]:
                self.send_json(identity, event)
        elif command["action"] == "close":
            self.send(identity, struct.pack("!H", 1000), 8)
        elif command["action"] != "barrier":
            raise ValueError("Unknown fixture control")
        self.record("control_completed", id=command["id"])

    def close(self):
        with self.lock:
            peers = list(self.peers.values())
        for peer in peers:
            try:
                peer["socket"].shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--requests-file", required=True)
    fixture = RealtimeFixture(parser.parse_args())
    fixture.thread.start()
    print(json.dumps({"url": f"http://127.0.0.1:{fixture.server.server_port}"}), flush=True)
    try:
        for line in sys.stdin:
            fixture.control(json.loads(line))
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
