#!/usr/bin/env python3
"""Two assistant-only native turns over real executor filesystem discovery.

The ordinary lifecycle helper owns both immutable native processes. This module
adds a local fixed Responses dependency and observes filesystem method/path only.
Connection bootstrap remains internal; HTTP upgrade bytes are forwarded opaquely.
No native app-server response is synthesized.
"""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import select
import signal
import socket
import struct
import sys
import time

from ordinary_environment_connection_fixture import BINARY_SHA, Fixture as Lifecycle

MAX_BYTES = 262_144
SKILL = ("---\nname: review\ndescription: Owned ordinary review metadata λ.\n---\n"
         "This inert document preserves β and 漢字; it has no executable actions.\n")
PROMPTS = ["Owned ordinary environment skills first input",
           "Owned ordinary environment skills replacement input"]
ANSWERS = ["Owned ordinary first assistant λ", "Owned ordinary replacement assistant β"]


class FrameObserver:
    """Bounded passive observer; forwarders always relay original bytes unchanged."""
    def __init__(self, owner, identity):
        self.owner, self.identity = owner, identity
        self.pending = bytearray()
        self.upgraded = False
        self.fragments = bytearray()
        self.frame_count = 0

    def feed(self, data):
        self.pending.extend(data)
        if len(self.pending) > MAX_BYTES:
            raise RuntimeError("ordinary skills observer buffer bound")
        if not self.upgraded:
            end = self.pending.find(b"\r\n\r\n")
            if end < 0:
                if len(self.pending) > 16_384:
                    raise RuntimeError("ordinary skills upgrade framing bound")
                return
            # Delimiter framing only: never decode, inspect or retain headers.
            del self.pending[:end + 4]
            self.upgraded = True
        while len(self.pending) >= 2:
            first, second = self.pending[:2]
            length, offset = second & 127, 2
            if length in (126, 127):
                width = 2 if length == 126 else 8
                if len(self.pending) < offset + width:
                    return
                length = struct.unpack("!H" if width == 2 else "!Q",
                                       self.pending[offset:offset + width])[0]
                offset += width
            if length > MAX_BYTES:
                raise RuntimeError("ordinary skills executor frame bound")
            masked = bool(second & 128)
            mask_size = 4 if masked else 0
            if len(self.pending) < offset + mask_size + length:
                return
            mask = self.pending[offset:offset + mask_size]
            offset += mask_size
            payload = self.pending[offset:offset + length]
            del self.pending[:offset + length]
            if masked:
                payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            self.frame_count += 1
            if self.frame_count > 160:
                raise RuntimeError("ordinary skills executor frame count bound")
            opcode = first & 15
            if opcode in (0, 1, 2):
                self.fragments.extend(payload)
                if len(self.fragments) > MAX_BYTES:
                    raise RuntimeError("ordinary skills executor message bound")
                if first & 128:
                    wire = json.loads(self.fragments)
                    self.fragments.clear()
                    method = wire.get("method")
                    if method in {"fs/walk", "fs/readFile"}:
                        self.owner.record("discovery", connection=self.identity,
                                          method=method, path=wire.get("params", {}).get("path"))


class Fixture(Lifecycle):
    def start_sink(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def do_POST(self):
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    if self.path != "/v1/responses" or not 0 < size <= MAX_BYTES:
                        raise RuntimeError("ordinary skills provider framing")
                    raw = self.rfile.read(size)
                    if len(raw) != size:
                        raise RuntimeError("ordinary skills provider incomplete body")
                    request = json.loads(raw)
                    with owner.lock:
                        owner.sink_count += 1
                        sequence = owner.sink_count
                    if sequence > 2:
                        raise RuntimeError("ordinary skills provider request count bound")
                    inputs = request["input"]
                    texts = [part["text"] for item in inputs for part in item.get("content", [])
                             if part.get("type") == "input_text"]
                    joined = "\n".join(texts)
                    if len(joined.encode()) > 131_072:
                        raise RuntimeError("ordinary skills provider text bound")
                    tool_input = any(item.get("type") in {
                        "function_call", "function_call_output", "custom_tool_call",
                        "custom_tool_call_output"} for item in inputs)
                    owner.record("provider_request", sequence=sequence, model=request.get("model"),
                                 texts=texts, toolInput=tool_input)
                    identity = f"owned-ordinary-skills-response-{sequence}"
                    item = {"type": "message", "role": "assistant",
                            "id": f"owned-ordinary-skills-message-{sequence}",
                            "content": [{"type": "output_text", "text": ANSWERS[sequence - 1]}]}
                    events = [
                        {"type": "response.created", "response": {"id": identity}},
                        {"type": "response.output_item.done", "item": item},
                        {"type": "response.completed", "response": {"id": identity, "usage": {
                            "input_tokens": 0, "input_tokens_details": None,
                            "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0}}}]
                    body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                                   for event in events).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(body)
                    self.wfile.flush()
                    owner.record("provider_response", sequence=sequence)
                except Exception as error:
                    owner.fault("provider", error)
                    self.close_connection = True

            def do_GET(self):
                owner.fault("provider-method", RuntimeError("ordinary skills unexpected request"))
                self.close_connection = True

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 0.1

        def serve():
            while not self.stopping.is_set():
                self.http.handle_request()

        self.worker("ordinary-model", serve)
        return f"http://127.0.0.1:{self.http.server_port}"

    def configure(self):
        runtime = super().configure()
        self.runtime_value = runtime
        for name in ["app", "executor"]:
            path = self.root / name / "config.toml"
            text = path.read_text()
            text = ("project_doc_max_bytes = 0\nproject_root_markers = []\n" + text)
            text = text.replace("[features]\n", "[features]\n"
                "executor_capability_discovery = false\nenable_request_compression = false\n"
                "remote_models = false\nshell_tool = false\nunified_exec = false\n"
                "browser_use = false\ncomputer_use = false\n")
            text += "\n[plugins._default]\nenabled = false\n[plugins.owned-skills-root]\nenabled = true\n"
            path.write_text(text)
        self.content_roots = [self.root / "owned-full-root", self.root / "owned-empty-root"]
        for root in self.content_roots:
            (root / ".codex-plugin").mkdir(parents=True)
            (root / ".codex-plugin/plugin.json").write_text('{"name":"owned","mcpServers":{}}\n')
        (self.content_roots[0] / "review").mkdir()
        (self.content_roots[0] / "review/SKILL.md").write_text(SKILL)
        catalog = self.root / "app/models.json"
        models = json.loads(catalog.read_text())
        models["models"][0]["model_messages"]["instructions_template"] = (
            "Return only the fixed assistant response. Do not call tools.")
        catalog.write_text(json.dumps(models))
        paths = [self.root / name / "config.toml" for name in ["app", "executor"]]
        paths += [catalog, *(root / ".codex-plugin/plugin.json" for root in self.content_roots),
                  self.content_roots[0] / "review/SKILL.md"]
        self.record("fixture_ready", snapshots={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                               for path in paths})
        return runtime

    def start_executor(self, runtime_value):
        super().start_executor(runtime_value)
        # Bootstrap remains internal to this fixture, not a captured test envelope.
        (self.root / "connection-setup.json").unlink()
        address = self.proxy_listener.getsockname()
        public = {"execServerUrl": f"ws://{address[0]}:{address[1]}"}
        pending = self.root / "endpoint.pending"
        pending.write_text(json.dumps(public))
        pending.replace(self.root / "endpoint.json")
        self.gate.set()

    def forward(self, downstream, identity):
        upstream = None
        observer = FrameObserver(self, identity)
        try:
            upstream = self.track(socket.create_connection(self.executor_address, timeout=2),
                                  self.proxy_sockets)
            downstream.settimeout(1)
            upstream.settimeout(1)
            total = 0
            while not self.stopping.is_set() and not self.proxy_stopped.is_set():
                readable, _, _ = select.select([downstream, upstream], [], [], 0.1)
                for source in readable:
                    data = source.recv(65_536)
                    if not data:
                        return
                    total += len(data)
                    if total > 1_048_576:
                        raise RuntimeError("ordinary skills proxy byte bound")
                    target = upstream if source is downstream else downstream
                    target.sendall(data)
                    if source is downstream:
                        observer.feed(data)
        except (OSError, ValueError):
            if not self.stopping.is_set() and not self.proxy_stopped.is_set():
                raise
        finally:
            self.close_socket(downstream, self.proxy_sockets)
            if upstream is not None:
                self.close_socket(upstream, self.proxy_sockets)
            self.record("proxy_connection_closed", connection=identity)

    def run(self):
        runtime = self.configure()
        self.start_executor(runtime)
        self.native = self.spawn("app", ["app-server", "--listen", "stdio://"],
                                 self.root / "workspace")
        self.record("native_started", pid=self.native.pid, executorPid=self.executor.pid,
                    controllerPid=os.getpid())
        # Only these two ordinary thread/start exchanges have original-byte capture.
        # Registration bootstrap and every other method remain opaque.
        self.thread_start_ids = {}
        self.thread_start_bytes = 0
        self.worker("native-output", self.output)
        self.worker("controls", self.controls)
        pending = bytearray()
        while not self.stopping.is_set():
            readable, _, _ = select.select([sys.stdin.buffer], [], [], 0.1)
            if not readable:
                continue
            chunk = os.read(sys.stdin.fileno(), 65_536)
            if not chunk:
                return
            pending.extend(chunk)
            if len(pending) > 65_536:
                raise RuntimeError("ordinary skills input byte bound")
            while b"\n" in pending:
                line, _, rest = pending.partition(b"\n")
                pending = bytearray(rest)
                self.input_count += 1
                if self.input_count > 32:
                    raise RuntimeError("ordinary skills input count bound")
                wire = json.loads(line)
                if wire.get("method") == "environment/add":
                    params = wire["params"]
                    params.update({"authBearerToken": self.runtime_value, "connectTimeoutMs": 10_000})
                    self.record("registration", id=wire["id"], method=wire["method"],
                                environmentId=params["environmentId"], skills=params["skills"])
                encoded = json.dumps(wire, ensure_ascii=False).encode() + b"\n"
                if wire.get("method") == "thread/start":
                    original = bytes(line) + b"\n"
                    identity = wire["id"]
                    if type(identity) not in (int, str):
                        raise RuntimeError("ordinary skills thread identity type")
                    if len(original) > 8_192 or len(encoded) > 8_192:
                        raise RuntimeError("ordinary skills thread input capture byte bound")
                    key = (type(identity).__name__, identity)
                    with self.lock:
                        if len(self.thread_start_ids) >= 2 or key in self.thread_start_ids:
                            raise RuntimeError("ordinary skills thread input capture count bound")
                        self.thread_start_ids[key] = False
                        self.thread_start_bytes += len(original) + len(encoded)
                        if self.thread_start_bytes > 196_608:
                            raise RuntimeError("ordinary skills thread total capture byte bound")
                        # Record forwarded bytes only after the actual flush succeeds.
                        self.native.stdin.write(encoded)
                        self.native.stdin.flush()
                        self.record("native_input", method=wire.get("method"), id=identity,
                                    driverJsonlBase64=base64.b64encode(original).decode("ascii"),
                                    nativeJsonlBase64=base64.b64encode(encoded).decode("ascii"))
                else:
                    self.record("native_input", method=wire.get("method"), id=wire.get("id"))
                    self.native.stdin.write(encoded)
                    self.native.stdin.flush()

    def output(self):
        while True:
            line = self.native.stdout.readline(65_537)
            if not line:
                if not self.stopping.is_set():
                    raise RuntimeError("ordinary skills native output exited")
                return
            self.output_count += 1
            if len(line) > 65_536 or not line.endswith(b"\n") or self.output_count > 128:
                raise RuntimeError("ordinary skills output bound")
            wire = json.loads(line)
            identity = wire.get("id")
            key = (type(identity).__name__, identity) if type(identity) in (int, str) else None
            with self.lock:
                captured = {}
                if key in self.thread_start_ids and "method" not in wire:
                    if self.thread_start_ids[key]:
                        raise RuntimeError("ordinary skills duplicate thread output capture")
                    self.thread_start_ids[key] = True
                    self.thread_start_bytes += len(line)
                    if self.thread_start_bytes > 196_608:
                        raise RuntimeError("ordinary skills thread total capture byte bound")
                    captured["nativeJsonlBase64"] = base64.b64encode(line).decode("ascii")
                self.record("native_output", id=identity, method=wire.get("method"), **captured)
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()

    def close(self):
        self.stopping.set()
        try:
            if hasattr(self, "http"):
                self.join_workers("ordinary-model")
        finally:
            try:
                if hasattr(self, "http"):
                    self.http.server_close()
            finally:
                super().close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    args = parser.parse_args()
    binary = args.codex.resolve()
    if hashlib.sha256(binary.read_bytes()).hexdigest() != BINARY_SHA:
        raise RuntimeError("immutable ordinary skills binary mismatch")
    fixture = Fixture(args.root, binary)
    signal.signal(signal.SIGTERM, lambda *_: fixture.stopping.set())
    signal.signal(signal.SIGINT, lambda *_: fixture.stopping.set())
    try:
        fixture.run()
    except Exception as error:
        fixture.fault("controller", error)
    finally:
        try:
            fixture.close()
        except Exception as error:
            fixture.fault("close", error)
    return 1 if fixture.failed else 0


if __name__ == "__main__":
    sys.exit(main())
