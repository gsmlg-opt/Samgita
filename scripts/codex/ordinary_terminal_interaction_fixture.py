#!/usr/bin/env python3
"""Finite local Responses backend and owned stdin reader; no app-server frames."""
import argparse
import json
import os
from pathlib import Path
import re
import select
import shlex
import signal
import socket
import socketserver
import sys
import threading
import time
import tty


PROMPT = "Owned ordinary terminal interaction only"
INPUT = "owned-terminal-input λ🙂\n"
READY = "owned-terminal-ready\n"
OUTPUT = "owned-terminal-received λ🙂\n"
ANSWER = "Owned ordinary terminal interaction finished."
EXEC_ID = "owned-terminal-exec"
WRITE_ID = "owned-terminal-write"
MAX_BODY = 262144
MAX_JOURNAL = 2097152


def write_json(path, value):
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    assert len(data) <= MAX_JOURNAL
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(data)
    temporary.replace(path)


def reader(root):
    # Raw terminal mode gives an exact byte oracle rather than terminal echo.
    tty.setraw(0)
    write_json(root / "reader-started.json", {"pid": os.getpid()})
    os.write(1, READY.encode())
    expected = INPUT.encode()
    received = bytearray()
    deadline = time.monotonic() + 15
    while len(received) < len(expected):
        remaining = deadline - time.monotonic()
        assert remaining > 0, "Owned reader input deadline"
        readable, _, _ = select.select([0], [], [], remaining)
        assert readable, "Owned reader input deadline"
        chunk = os.read(0, len(expected) - len(received))
        assert chunk, "Owned reader input ended early"
        received.extend(chunk)
    assert bytes(received) == expected, "Unexpected owned reader input"
    write_json(root / "reader-input.json", {"text": received.decode(), "bytes": list(received)})
    os.write(1, OUTPUT.encode())
    write_json(root / "reader-finished.json", {"pid": os.getpid(), "inputBytes": len(received)})


def response_events(index, item):
    identity = f"owned-terminal-response-{index}"
    return [
        {"type": "response.created", "response": {"id": identity}},
        {"type": "response.output_item.done", "item": item},
        {"type": "response.completed", "response": {"id": identity, "usage": {
            "input_tokens": 0, "input_tokens_details": None,
            "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0}}},
    ]


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        peer = self.server.peer
        self.request.settimeout(0.2)
        with peer.lock:
            peer.sockets.add(self.request)
        try:
            self.request_once(peer)
        except Exception as failure:
            if not peer.stopping.is_set():
                with peer.lock:
                    assert len(peer.state["errors"]) < 8
                    peer.state["errors"].append(type(failure).__name__)
                    peer.save_locked()
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.request.close()
            with peer.lock:
                peer.sockets.discard(self.request)

    def read_exact(self, count, peer, deadline):
        assert 0 <= count <= MAX_BODY
        data = bytearray()
        while len(data) < count:
            assert not peer.stopping.is_set(), "Owned peer stopping"
            assert time.monotonic() < deadline, "Owned peer read deadline"
            try:
                chunk = self.request.recv(count - len(data))
            except socket.timeout:
                continue
            assert chunk, "Owned incomplete HTTP input"
            data.extend(chunk)
        return bytes(data)

    def request_once(self, peer):
        deadline = time.monotonic() + 5
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            assert len(header) < 8192, "Owned HTTP input overflow"
            header.extend(self.read_exact(1, peer, deadline))
        lines = header.decode("iso-8859-1").split("\r\n")
        method, path, version = lines[0].split(" ")
        assert version == "HTTP/1.1" and method == "POST"
        lengths = [line.split(":", 1)[1].strip() for line in lines[1:]
                   if line.lower().startswith("content-length:")]
        assert len(lengths) == 1
        length = int(lengths[0])
        body = self.read_exact(length, peer, deadline)
        del lines, header
        if path == "/fixture/release":
            assert length == 0
            with peer.lock:
                assert peer.state["controls"] == []
                assert len(peer.state["requests"]) == 2
                assert len(peer.state["emitted"]) == 1
                peer.state["controls"].append({"method": method, "path": path, "bodyBytes": 0})
                peer.save_locked()
            self.reply(b'{"released":true}', b"application/json")
            peer.release.set()
            return
        assert path == "/v1/responses", "Unexpected owned peer route"
        request = json.loads(body)
        assert isinstance(request, dict)
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") == PROMPT]
        assert markers == [PROMPT], "Unexpected owned inference input"
        outputs = [{"type": item["type"], "call_id": item["call_id"], "output": item["output"]}
                   for item in request.get("input", []) if item.get("type") == "function_call_output"]
        with peer.lock:
            index = len(peer.state["requests"]) + 1
            assert index <= 3, "Extra owned Responses request"
            peer.state["requests"].append({"index": index, "marker": PROMPT, "toolOutputs": outputs})
            peer.save_locked()
        if index == 1:
            assert outputs == []
            item = {"type": "function_call", "name": "exec_command", "call_id": EXEC_ID,
                    "arguments": json.dumps(peer.exec_args, ensure_ascii=False, separators=(",", ":"))}
        elif index == 2:
            assert [output["call_id"] for output in outputs] == [EXEC_ID]
            output = outputs[0]["output"]
            assert isinstance(output, str) and output.endswith("Output:\n" + READY)
            matches = re.findall(r"^Process running with session ID ([1-9][0-9]*)$", output, re.M)
            assert len(matches) == 1
            started = json.loads((peer.root / "reader-started.json").read_text())
            assert set(started) == {"pid"} and isinstance(started["pid"], int)
            with peer.lock:
                peer.state["sessionId"] = matches[0]
                peer.save_locked()
            deadline = time.monotonic() + 10
            while not peer.release.is_set():
                assert not peer.stopping.is_set(), "Owned peer stopping"
                remaining = deadline - time.monotonic()
                assert remaining > 0, "Owned write release deadline"
                peer.release.wait(min(0.2, remaining))
            args = {"session_id": int(matches[0]), "chars": INPUT,
                    "yield_time_ms": 1000, "max_output_tokens": 512}
            item = {"type": "function_call", "name": "write_stdin", "call_id": WRITE_ID,
                    "arguments": json.dumps(args, ensure_ascii=False, separators=(",", ":"))}
        else:
            assert [output["call_id"] for output in outputs] == [EXEC_ID, WRITE_ID]
            output = outputs[1]["output"]
            assert isinstance(output, str) and "Process exited with code 0\n" in output
            assert output.endswith("Output:\n" + OUTPUT)
            assert json.loads((peer.root / "reader-input.json").read_text()) == {
                "text": INPUT, "bytes": list(INPUT.encode())}
            item = {"type": "message", "role": "assistant", "id": "owned-terminal-answer",
                    "content": [{"type": "output_text", "text": ANSWER}]}
        events = response_events(index, item)
        with peer.lock:
            peer.state["emitted"].append(events)
            peer.save_locked()
        payload = "".join(f"event: {entry['type']}\ndata: "
                          + json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n\n"
                          for entry in events).encode()
        assert len(payload) <= 65536
        self.reply(payload, b"text/event-stream")

    def reply(self, body, kind):
        self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: " + kind
            + f"\r\nContent-Length: {len(body)}\r\n".encode()
            + b"Connection: close\r\n\r\n" + body)


class Server(socketserver.TCPServer):
    allow_reuse_address = False

    def process_request(self, request, address):
        peer = self.peer
        with peer.lock:
            peer.state["requestCount"] += 1
            assert peer.state["requestCount"] <= 4, "Owned request count overflow"
            assert len(peer.handlers) < 2, "Owned handler count overflow"
            thread = threading.Thread(target=self.run_handler, args=(request, address), daemon=False)
            peer.handlers.add(thread)
            peer.save_locked()
        thread.start()

    def run_handler(self, request, address):
        try:
            self.finish_request(request, address)
        finally:
            self.shutdown_request(request)
            with self.peer.lock:
                self.peer.handlers.discard(threading.current_thread())


class Peer:
    def __init__(self, root):
        self.root = root
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.release = threading.Event()
        self.sockets, self.handlers = set(), set()
        self.state = {"requests": [], "emitted": [], "controls": [], "errors": [],
                      "requestCount": 0, "sessionId": None}
        self.command = "exec " + shlex.quote(sys.executable) + " " + shlex.quote(str(root / "bin/reader.py")) + " --reader --root " + shlex.quote(str(root))
        self.exec_args = {"cmd": self.command, "workdir": str(root / "workspace"),
                          "shell": str(root / "bin/sh"), "login": False, "tty": True,
                          "yield_time_ms": 1000, "max_output_tokens": 512}
        self.server = Server(("127.0.0.1", 0), Handler)
        self.server.peer = self
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.05),
                                       name="owned-ordinary-terminal", daemon=False)
        self.save_locked()

    def save_locked(self):
        write_json(self.root / "peer.json", self.state)

    def configure(self):
        url = f"http://127.0.0.1:{self.server.server_address[1]}"
        catalog = self.root / "codex/models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary terminal fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned local terminal fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
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
chatgpt_base_url = "{url}"
openai_base_url = "{url}/v1"
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
unified_exec = true
unified_exec_tty = true
[model_providers.fixture]
name = "Owned ordinary terminal provider"
base_url = "{url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def close(self):
        self.stopping.set()
        self.release.set()
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
            handlers = list(self.handlers)
        for handler in handlers:
            handler.join(timeout=2)
            assert not handler.is_alive(), "Owned terminal handler did not stop"
        self.server.server_close()
        if self.thread.ident is not None:
            self.thread.join(timeout=2)
        assert not self.thread.is_alive(), "Owned terminal peer did not stop"
        with self.lock:
            assert not self.sockets and not self.handlers
        write_json(self.root / "peer-closed.json", {
            "activeSockets": len(self.sockets), "handlerThreads": len(self.handlers),
            "threadAlive": self.thread.is_alive(), "serverClosed": self.server.socket.fileno() == -1})


def terminate(_signum, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--reader", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.reader:
        reader(root)
        return
    peer = Peer(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        peer.configure()
        peer.thread.start()
        print(json.dumps({"pid": os.getpid(), "port": peer.server.server_address[1],
                          "command": peer.command, "execArgs": peer.exec_args}), flush=True)
        sys.stdin.buffer.read(1)
    finally:
        peer.close()


if __name__ == "__main__":
    main()
