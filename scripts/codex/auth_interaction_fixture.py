#!/usr/bin/env python3
"""Loopback Responses HTTP/WS backend for synthetic auth and attestation tests.

No real JWT issuer, account or credential is used. The fixture observes only
synthetic token generation metadata and the explicitly supplied test attestation.
"""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import struct
import threading

from model_fixture import response_events


def token_generation(authorization):
    token = authorization.removeprefix("Bearer ")
    try:
        payload = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["email"]
    except (ValueError, KeyError, IndexError):
        return "absent"


def frame(payload, opcode=1):
    size = len(payload)
    if size < 126:
        return bytes([128 + opcode, size]) + payload
    if size < 65_536:
        return bytes([128 + opcode, 126]) + struct.pack("!H", size) + payload
    return bytes([128 + opcode, 127]) + struct.pack("!Q", size) + payload


def read_frame(stream):
    head = stream.read(2)
    if not head:
        return None
    if len(head) != 2 or not head[0] & 128:
        raise ValueError("Fixture expects a complete unfragmented client frame")
    size = head[1] & 127
    if size == 126:
        size = struct.unpack("!H", stream.read(2))[0]
    elif size == 127:
        size = struct.unpack("!Q", stream.read(8))[0]
    if size > 4_194_304:
        raise ValueError("Fixture frame limit")
    masked = bool(head[1] & 128)
    key = stream.read(4) if masked else b""
    payload = stream.read(size)
    if len(payload) != size:
        raise ValueError("Incomplete fixture frame")
    if masked:
        payload = bytes(value ^ key[index % 4] for index, value in enumerate(payload))
    return head[0] & 15, payload


class AuthFixture:
    def __init__(self, scenario, requests_file):
        self.scenario = scenario
        self.requests_file = Path(requests_file)
        self.journal = []
        self.lock = threading.Lock()
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def json_response(self, status, value):
                body = json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                if self.close_connection:
                    self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.headers.get("Upgrade", "").lower() == "websocket":
                    self.websocket()
                elif self.path.endswith("/accounts/check"):
                    self.json_response(200, {"accounts": [{
                        "id": "synthetic-account", "workspace_backend_origin": "https://synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]})
                elif self.path.endswith("/wham/settings/user"):
                    self.json_response(200, {"commit_attribution_enabled": False})
                else:
                    self.json_response(404, {"error": "Synthetic route absent"})

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                if self.path != "/v1/responses" or not 0 < size <= 4_194_304:
                    # Do not parse an unread rejected request body as a new HTTP request.
                    self.close_connection = True
                    self.json_response(404, {"error": "Synthetic route absent"})
                    return
                request = json.loads(self.rfile.read(size))
                generation = token_generation(self.headers.get("Authorization", ""))
                status = 401 if generation == "old@synthetic.invalid" else 200
                fixture.record({"transport": "http", "generation": generation,
                                "status": status, "request": request})
                if status == 401:
                    self.json_response(401, {"error": {"message": "Synthetic expired token"}})
                    return
                events = fixture.events(request)
                body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                               for event in events).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def websocket(self):
                key = self.headers["Sec-WebSocket-Key"]
                accept = base64.b64encode(hashlib.sha1(
                    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                attestation = self.headers.get("x-oai-attestation")
                fixture.record({"transport": "handshake", "attestation": attestation,
                                "generation": token_generation(
                                    self.headers.get("Authorization", ""))})
                self.send_response(101)
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", accept)
                self.end_headers()
                self.wfile.flush()
                self.connection.settimeout(15)
                try:
                    self.websocket_messages()
                except (ConnectionError, TimeoutError, ValueError):
                    pass
                finally:
                    self.close_connection = True

            def websocket_messages(self):
                while True:
                    incoming = read_frame(self.rfile)
                    if incoming is None or incoming[0] == 8:
                        return
                    opcode, payload = incoming
                    if opcode == 9:
                        self.wfile.write(frame(payload, 10))
                        self.wfile.flush()
                        continue
                    if opcode != 1:
                        raise ValueError("Unsupported fixture frame")
                    request = json.loads(payload)
                    fixture.record({"transport": "websocket", "request": request})
                    for event in fixture.events(request):
                        self.wfile.write(frame(json.dumps(event).encode()))
                    self.wfile.flush()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def record(self, entry):
        with self.lock:
            self.journal.append(entry)
            temporary = self.requests_file.with_suffix(".partial")
            temporary.write_text(json.dumps(self.journal))
            temporary.replace(self.requests_file)

    def events(self, request):
        events = response_events(len(self.journal), {
            "type": "message", "role": "assistant", "id": "synthetic-auth-message",
            "content": [{"type": "output_text", "text": "Synthetic authenticated fixture answer"}],
        })
        return [events[0], events[-1]] if request.get("generate") is False else events

    def config(self, codex_home):
        body = f'''model = "mock-model"
model_provider = "fixture"
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
chatgpt_base_url = "{self.url}/backend-api"
openai_base_url = "{self.url}/v1"
[features]
shell_snapshot = false
[model_providers.fixture]
name = "Synthetic authenticated loopback fixture"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = {str(self.scenario == "attestation").lower()}
request_max_retries = 0
stream_max_retries = 0
'''
        Path(codex_home, "config.toml").write_text(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["refresh", "attestation"], required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    parser.add_argument("--workspace")
    args = parser.parse_args()
    fixture = AuthFixture(args.scenario, args.requests_file)
    fixture.config(args.codex_home)
    fixture.thread.start()
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.server.shutdown()
        fixture.server.server_close()
        fixture.thread.join(timeout=5)


if __name__ == "__main__":
    main()
