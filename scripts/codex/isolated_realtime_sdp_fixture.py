#!/usr/bin/env python3
"""Owned HTTP/WS dependencies for stock Codex realtime V1/V3 qualification.

Only the pinned native process writes app-server frames. The peer exchanges a
fixed synthetic offer/answer, accepts a control socket, and returns fixed text
and PCM bytes. It provides no media engine, inference, tools or external route.
"""
import argparse
import base64
from email.parser import BytesParser
from email.policy import default
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import traceback


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
TOKEN = "OWNED_SYNTHETIC_REALTIME_ONLY"
OFFER = "v=owned-synthetic-offer\r\n"
ANSWER = "v=owned-synthetic-answer\r\n"
CALL_ID = "rtc_owned_synthetic"
PROMPT = "Synthetic SDP prompt"
TEXT = "Synthetic realtime client text"
TRANSCRIPT = "Synthetic realtime peer transcript"
INITIAL = [{"role": "developer", "text": "Synthetic realtime initial context"}]
MAX_WIRE = 262_144
SCENARIOS = [f"{kind}-{version}" for kind in ["websocket", "webrtc", "existing"]
             for version in ["v1", "v3"]] + ["webrtc-default", "existing-default"]
SCENARIOS += ["websocket-v1-ingress", "websocket-v3-controls", "websocket-v3-utf8"]
ALLOWED = {"initialize", "initialized", "thread/start", "thread/realtime/start",
           "thread/realtime/appendText", "thread/realtime/stop"}


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes += json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent and [link["ifname"] for link in links] == ["lo"]
    for route in routes:
        assert route.get("dev") == "lo" and route.get("dst") != "default"
        assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback
    return {"parent": parent, "child": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


def frame(payload, opcode=1):
    assert len(payload) < 65536
    if len(payload) < 126:
        return bytes([128 | opcode, len(payload)]) + payload
    return bytes([128 | opcode, 126]) + struct.pack("!H", len(payload)) + payload


def read_exact(stream, size):
    result = bytearray()
    while len(result) < size:
        chunk = stream.read(size - len(result))
        if not chunk:
            raise EOFError("Peer closed")
        result.extend(chunk)
    return bytes(result)


def read_frame(stream):
    head = read_exact(stream, 2)
    assert head[0] & 128 and head[1] & 128 and not head[0] & 112
    size = head[1] & 127
    if size == 126:
        size = struct.unpack("!H", read_exact(stream, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", read_exact(stream, 8))[0]
    assert size <= 65536
    key, payload = read_exact(stream, 4), read_exact(stream, size)
    return head[0] & 15, bytes(value ^ key[index % 4] for index, value in enumerate(payload))


class Fixture:
    def __init__(self, args, proof):
        self.args, self.lock = args, threading.RLock()
        self.kind, requested, *extension = args.scenario.split("-")
        self.extension = extension[0] if extension else None
        self.session_id = ("owned-" + args.scenario.removeprefix("websocket-") if self.extension
                           else "owned-realtime-" + args.scenario)
        self.prompt = "Owned realtime controls prompt" if self.extension else PROMPT
        self.input_count = 0
        self.version = "v1" if requested == "default" else requested
        self.explicit_version = requested != "default"
        self.journal = {"namespace": proof, "events": []}
        self.closing = threading.Event()
        self.peer_sockets, self.peer_threads = set(), set()
        self.call_count, self.join_count, self.append_count = 0, 0, 0
        self.thread_id, self.thread_request = None, None
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            block_on_close = False

            def process_request_thread(self, request, client_address):
                worker = threading.current_thread()
                with fixture.lock:
                    if fixture.closing.is_set():
                        request.close()
                        return
                    fixture.peer_sockets.add(request)
                    fixture.peer_threads.add(worker)
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    with fixture.lock:
                        fixture.peer_sockets.discard(request)
                        fixture.peer_threads.discard(worker)

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="http-worker",
                                   error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, body=b"", content_type="application/json", location=None):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                if location:
                    self.send_header("Location", location)
                self.end_headers()
                self.wfile.write(body)
                self.wfile.flush()

            def validate_headers(self):
                assert self.headers.get("Host") == f"127.0.0.1:{fixture.server.server_port}"
                assert self.headers.get("Authorization") == f"Bearer {TOKEN}"
                assert self.headers.get("ChatGPT-Account-ID") is None
                assert self.headers.get("OpenAI-Alpha") == (
                    "quicksilver=v1" if fixture.version == "v1" else "quicksilver=v2")
                assert self.headers.get("x-session-id") == fixture.session_id

            def do_POST(self):
                try:
                    assert fixture.kind == "webrtc"
                    assert self.path == ("/v1/live" if fixture.version == "v3" else
                                         "/v1/realtime/calls?intent=quicksilver&architecture=avas")
                    self.validate_headers()
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 16384
                    content_type = self.headers.get("Content-Type")
                    assert content_type == "multipart/form-data; boundary=codex-realtime-call-boundary"
                    body = read_exact(self.rfile, size)
                    mime = BytesParser(policy=default).parsebytes(
                        f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode() + body)
                    assert mime.is_multipart() and not mime.defects
                    parts = list(mime.iter_parts())
                    assert len(parts) == 2
                    assert [part.get_param("name", header="content-disposition") for part in parts] == ["sdp", "session"]
                    assert [part.get_content_type() for part in parts] == ["application/sdp", "application/json"]
                    assert parts[0].get_payload(decode=True) == OFFER.encode()
                    session = json.loads(parts[1].get_payload(decode=True))
                    assert session == fixture.expected_session(model=True)
                    fixture.call_count += 1
                    assert fixture.call_count == 1
                    fixture.record("call_created", path=self.path, offer=OFFER, session=session,
                                   authorization_verified=True, host_verified=True)
                    self.reply(201, ANSWER.encode(), "application/sdp",
                               f"/v1/realtime/calls/{CALL_ID}")
                except (BrokenPipeError, ConnectionResetError):
                    if not fixture.closing.is_set():
                        fixture.record("fixture_error", stage="call-peer-closed")
                except Exception as error:
                    fixture.record("fixture_error", stage="call", error_type=type(error).__name__)
                    self.reply(400)

            def send_json(self, message):
                self.connection.sendall(frame(json.dumps(message).encode()))

            def do_GET(self):
                try:
                    assert self.headers.get("Upgrade", "").lower() == "websocket"
                    self.validate_headers()
                    assert self.path == fixture.expected_ws_path()
                    if fixture.kind == "webrtc":
                        assert fixture.call_count == 1
                    fixture.join_count += 1
                    assert fixture.join_count == 1
                    fixture.record("sideband_joined", path=self.path,
                                   authorization_verified=True, host_verified=True)
                    key = self.headers["Sec-WebSocket-Key"]
                    assert len(base64.b64decode(key, validate=True)) == 16
                    accept = base64.b64encode(hashlib.sha1((key +
                        "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                    self.send_response(101)
                    self.send_header("Upgrade", "websocket")
                    self.send_header("Connection", "Upgrade")
                    self.send_header("Sec-WebSocket-Accept", accept)
                    self.end_headers()
                    self.wfile.flush()
                    if fixture.kind == "existing" or (fixture.kind == "webrtc" and fixture.version == "v3"):
                        self.send_session_ready()
                    while not fixture.closing.is_set():
                        opcode, payload = read_frame(self.rfile)
                        if opcode == 8:
                            self.connection.sendall(frame(payload, 8))
                            fixture.record("ws_closed")
                            return
                        if opcode == 9:
                            self.connection.sendall(frame(payload, 10))
                            continue
                        assert opcode == 1
                        message = json.loads(payload)
                        fixture.record("native_frame", message=message)
                        if message["type"] == "session.update":
                            assert fixture.kind != "existing"
                            assert fixture.kind == "websocket" or fixture.version == "v1"
                            assert message == {"type": "session.update", "session": fixture.expected_session()}
                            self.send_session_ready()
                        elif message["type"] == "session.close":
                            # Stock V3 may close the session before dropping its socket.
                            assert fixture.version == "v3"
                        elif fixture.extension:
                            if fixture.accept_extension_frame(message):
                                for event in fixture.extension_output():
                                    self.send_json(event)
                                fixture.record("peer_exchange", version=fixture.version)
                        else:
                            assert message == fixture.expected_append()
                            fixture.append_count += 1
                            assert fixture.append_count == 1
                            self.send_transcript()
                except (EOFError, ConnectionError, OSError) as error:
                    if not fixture.closing.is_set():
                        fixture.record("ws_peer_end", error_type=type(error).__name__)
                except Exception as error:
                    fixture.record("fixture_error", stage="websocket", error_type=type(error).__name__,
                                   error_line=traceback.extract_tb(error.__traceback__)[-1].lineno)
                finally:
                    self.close_connection = True
                    fixture.record("ws_worker_closed")

            def send_session_ready(self):
                self.send_json({"type": "session.updated" if fixture.version == "v1" else "session.started",
                                "session": {"id": "owned-peer-session", "instructions": fixture.prompt}})
                fixture.record("peer_ready")

            def send_transcript(self):
                if fixture.version == "v1":
                    messages = [
                        {"type": "conversation.input_transcript.delta", "delta": TRANSCRIPT},
                        {"type": "conversation.input_transcript.turn_marked", "transcript": TRANSCRIPT},
                        {"type": "conversation.output_audio.delta", "delta": "AAAAAA==",
                         "sample_rate": 24000, "channels": 1}]
                else:
                    messages = [
                        {"type": "input_transcript.added", "item": {"text": TRANSCRIPT}},
                        {"type": "turn.done", "turn": {"role": "user", "transcript": TRANSCRIPT}},
                        {"type": "output_audio.delta", "audio": "AAAAAA=="}]
                for message in messages:
                    self.send_json(message)
                fixture.record("peer_exchange", version=fixture.version)

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 160
            self.journal["events"].append({"event": event, **fields})
            write_json(self.args.root / "journal.json", self.journal)

    def extension_session(self):
        if self.version == "v1":
            return {"type": "quicksilver", "instructions": self.prompt,
                    "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000}},
                              "output": {"voice": "cove"}}}
        session = {"instructions": self.prompt, "audio": {"output": {"voice": "cove"}},
                   "delegation": {"type": "client"}}
        if self.extension == "controls":
            session["delegation"]["ack_filler"] = False
            session["initial_items"] = [
                {"type": "message", "role": "user",
                 "content": [{"type": "input_text", "text": "Owned initial user"}]},
                {"type": "message", "role": "assistant",
                 "content": [{"type": "output_text", "text": "Owned initial assistant"}]}]
        return session

    def extension_start(self):
        params = {"threadId": self.thread_id, "transport": {"type": "websocket"},
                  "version": self.version, "outputModality": "audio",
                  "includeStartupContext": False, "prompt": self.prompt,
                  "voice": "cove", "realtimeSessionId": self.session_id}
        if self.extension == "controls":
            params["delegationAckFiller"] = False
            params["initialItems"] = [
                {"role": "user", "text": "Owned initial user"},
                {"role": "assistant", "text": "Owned initial assistant"}]
        return params

    def extension_inputs(self):
        if self.extension == "utf8":
            return [("thread/realtime/appendText", {
                "threadId": self.thread_id, "role": "assistant",
                "text": "a" * 499 + "λ" + "b" * 499})]
        data, item_id = (("AQACAA==", "owned-v1-input") if self.extension == "ingress"
                         else ("BQAGAA==", "owned-v3-input"))
        inputs = [("thread/realtime/appendAudio", {
            "threadId": self.thread_id, "audio": {
                "data": data, "sampleRate": 24000, "numChannels": 1,
                "samplesPerChannel": 2, "itemId": item_id}})]
        if self.extension == "ingress":
            inputs += [
                ("thread/realtime/appendText", {
                    "threadId": self.thread_id, "role": "assistant",
                    "text": "Owned V1 assistant text"}),
                ("thread/realtime/appendText", {
                    "threadId": self.thread_id, "role": "developer",
                    "text": "Owned V1 developer text"})]
        return inputs

    def extension_frames(self):
        if self.extension == "controls":
            return [{"type": "input_audio.append", "audio": "BQAGAA=="}]
        if self.extension == "utf8":
            return [{"type": "session.context.append",
                     "content": [{"type": "input_text", "text": text}]}
                    for text in ["a" * 499, "λ" + "b" * 498, "b"]]
        return [
            {"type": "input_audio_buffer.append", "audio": "AQACAA=="},
            {"type": "conversation.item.create", "item": {
                "type": "message", "role": "assistant",
                "content": [{"type": "output_text", "text": "Owned V1 assistant text"}]}},
            {"type": "conversation.item.create", "item": {
                "type": "message", "role": "developer",
                "content": [{"type": "input_text", "text": "Owned V1 developer text"}]}}]

    def accept_extension_frame(self, message):
        expected = self.extension_frames()
        assert self.append_count < len(expected)
        assert message == expected[self.append_count]
        self.append_count += 1
        self.record("extension_frame", index=self.append_count)
        return self.append_count == len(expected)

    def extension_output(self):
        if self.extension == "ingress":
            return [
                {"type": "conversation.output_transcript.delta",
                 "delta": "Owned V1 assistant reply"},
                {"type": "response.output_audio_transcript.done",
                 "transcript": "Owned V1 assistant reply"},
                {"type": "conversation.output_audio.delta", "delta": "AwAEAA==",
                 "sample_rate": 24000, "channels": 1, "samples_per_channel": 2}]
        if self.extension == "controls":
            return [
                {"type": "input_transcript.added",
                 "item": {"text": "Owned V3 ingress transcript"}},
                {"type": "turn.done", "turn": {
                    "role": "user", "transcript": "Owned V3 ingress transcript"}}]
        return [
            {"type": "output_transcript.added",
             "item": {"text": "Owned V3 assistant reply λ"}},
            {"type": "turn.done", "turn": {
                "role": "assistant", "transcript": "Owned V3 assistant reply λ"}}]

    def expected_session(self, model=False):
        if self.extension:
            assert not model
            return self.extension_session()
        if self.version == "v1":
            session = {"type": "quicksilver", "instructions": PROMPT,
                       "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000}},
                                 "output": {"voice": "cove"}}}
        else:
            session = {"instructions": PROMPT, "audio": {"output": {"voice": "cove"}},
                       "delegation": {"type": "client"},
                       "initial_items": [{"type": "message", "role": "developer",
                                          "content": [{"type": "input_text", "text": INITIAL[0]["text"]}]}]}
        if model:
            session["model"] = "owned-synthetic-realtime"
        return session

    def expected_ws_path(self):
        if self.version == "v3":
            return "/v1/live?model=owned-synthetic-realtime" if self.kind == "websocket" else f"/v1/live/{CALL_ID}"
        suffix = "model=owned-synthetic-realtime" if self.kind == "websocket" else f"call_id={CALL_ID}"
        return "/v1/realtime?intent=quicksilver&" + suffix

    def expected_append(self):
        if self.version == "v1":
            return {"type": "conversation.item.create", "item": {"type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": TEXT}]}}
        return {"type": "session.context.append", "content": [{"type": "input_text", "text": TEXT}]}

    def expected_start(self):
        if self.extension:
            return self.extension_start()
        transport = {"type": "websocket"} if self.kind == "websocket" else (
            {"type": "webrtc", "sdp": OFFER} if self.kind == "webrtc" else
            {"type": "existingCall", "callId": CALL_ID})
        params = {"threadId": self.thread_id, "outputModality": "audio", "transport": transport,
                  "includeStartupContext": False, "realtimeSessionId": "owned-realtime-" + self.args.scenario}
        if self.explicit_version:
            params["version"] = self.version
        if self.kind != "existing":
            params["voice"] = "cove"
            if self.version == "v3":
                params["initialItems"] = INITIAL
        return params

    def native_input(self, value):
        method, params = value.get("method"), value.get("params")
        assert method in ALLOWED or (method == "thread/realtime/appendAudio"
                                     and self.extension in {"ingress", "controls"})
        if method == "initialize":
            assert params["capabilities"] == {"experimentalApi": True}
        elif method == "initialized":
            assert params is None
        elif method == "thread/start":
            assert self.thread_request is None
            assert params == {"cwd": str(self.args.root / "workspace")}
            self.thread_request = value["id"]
        elif method == "thread/realtime/start":
            assert self.thread_id and params == self.expected_start()
        elif self.extension and method in {"thread/realtime/appendAudio", "thread/realtime/appendText"}:
            expected = self.extension_inputs()
            assert self.input_count < len(expected)
            assert (method, params) == expected[self.input_count]
            self.input_count += 1
        elif method == "thread/realtime/appendText":
            assert params == {"threadId": self.thread_id, "role": "user", "text": TEXT}
        else:
            assert params == {"threadId": self.thread_id}
            if self.extension:
                assert self.input_count == len(self.extension_inputs())
                assert self.append_count == len(self.extension_frames())
        self.record("native_input", method=method, id=value.get("id"))

    def native_output(self, value):
        if value.get("id") == self.thread_request and "result" in value:
            assert self.thread_id is None
            self.thread_id = value["result"]["thread"]["id"]


def configure(args, fixture):
    endpoint = f"http://127.0.0.1:{fixture.server.server_port}"
    # A nonblank config prompt overrides even an explicit request at this pin.
    backend_prompt = "" if fixture.extension else PROMPT
    (args.root / "codex/config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
experimental_realtime_ws_base_url = "{endpoint}/v1"
experimental_realtime_webrtc_call_base_url = "{endpoint}/v1"
experimental_realtime_ws_backend_prompt = "{backend_prompt}"
experimental_realtime_ws_startup_context = "Unused synthetic startup context"
experimental_realtime_ws_model = "owned-synthetic-realtime"
[realtime]
version = "v2"
type = "conversational"
voice = "cedar"
[analytics]
enabled = false
[features]
apps = false
plugins = false
hooks = false
recommended_plugins = false
shell_snapshot = false
shell_tool = false
unified_exec = false
[model_providers.fixture]
name = "Owned synthetic realtime peer"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
experimental_bearer_token = "{TOKEN}"
request_max_retries = 0
stream_max_retries = 0
''')


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = Fixture(args, isolation(args.parent_netns))
    fixture.thread.start()
    configure(args, fixture)
    native, reader = None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        environment = {"HOME": str(args.root / "home"), "CODEX_HOME": str(args.root / "codex"),
            "TMPDIR": str(args.root / "tmp"), "PATH": os.environ["PATH"],
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
        with (args.root / "native-stderr.log").open("wb") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=SHA256,
                       inherited_host_credentials=False, inherited_host_bus=False)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n")
                    fixture.native_output(json.loads(line))
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 20 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            fixture.native_input(json.loads(line))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        deadline = time.monotonic() + 0.75

        def remaining(cap):
            return max(0.0, min(cap, deadline - time.monotonic()))

        fixture.closing.set()
        with fixture.lock:
            peers = list(fixture.peer_sockets)
        for peer in peers:
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        fixture.server.shutdown()
        fixture.server.server_close()
        if native is not None:
            try:
                native.stdin.close()
            except OSError:
                pass
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=remaining(0.25))
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=remaining(0.15))
        if reader:
            reader.join(remaining(0.15))
            assert not reader.is_alive()
        with fixture.lock:
            workers = list(fixture.peer_threads)
        for worker in workers:
            worker.join(remaining(0.1))
            assert not worker.is_alive()
        fixture.thread.join(remaining(0.1))
        assert not fixture.thread.is_alive()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=SCENARIOS)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
    assert all((args.root / name).is_dir() and not (args.root / name).is_symlink()
               for name in ["home", "codex", "workspace", "tmp"])
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter fixture"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, "-I", __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
