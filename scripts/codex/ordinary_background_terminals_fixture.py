#!/usr/bin/env python3
"""Finite ordinary Responses backend and two owned background stdin readers.

This peer emits model output only. Every app-server frame and unified-exec
session ID must originate in the pinned native process, never this fixture.
"""
import argparse
import base64
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
import time
import tty


PROMPT = "Owned ordinary background terminals only"
ANSWER = "Owned ordinary background terminals launched."
NAMES = ("a", "b")
MAX_BODY = 262144
MAX_JOURNAL = 2097152


def write_json(path, value):
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    assert len(data) <= MAX_JOURNAL
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(data)
    temporary.replace(path)


def ready(name):
    return f"owned-background-{name}-ready\n"


def reader(root, name):
    tty.setraw(0)
    marker = root / f"reader-{name}-started.json"
    assert not marker.exists()
    write_json(marker, {"pid": os.getpid(), "name": name, "cwd": os.getcwd()})
    os.write(1, ready(name).encode())
    readable, _, _ = select.select([0], [], [], 35)
    reason = "input_or_eof" if readable else "deadline"
    write_json(root / f"reader-{name}-unexpected.json", {"pid": os.getpid(), "reason": reason})
    raise SystemExit(3)


def response_events(index, item):
    identity = f"owned-background-response-{index}"
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
        try:
            self.request.settimeout(5)
            self.request_once(peer)
        except Exception as failure:
            peer.state["errors"].append(type(failure).__name__)
            peer.save()
            raise
        finally:
            self.request.close()

    def read_exact(self, count, deadline):
        assert 0 <= count <= MAX_BODY
        data = bytearray()
        while len(data) < count:
            remaining = deadline - time.monotonic()
            assert remaining > 0, "Owned HTTP input deadline"
            self.request.settimeout(remaining)
            chunk = self.request.recv(count - len(data))
            assert chunk, "Owned incomplete HTTP input"
            data.extend(chunk)
        return bytes(data)

    def request_once(self, peer):
        deadline = time.monotonic() + 5
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            assert len(header) < 8192
            header.extend(self.read_exact(1, deadline))
        lines = header.decode("iso-8859-1").split("\r\n")
        method, path, version = lines[0].split(" ")
        assert method == "POST" and version == "HTTP/1.1"
        lengths = [line.split(":", 1)[1].strip() for line in lines[1:]
                   if line.lower().startswith("content-length:")]
        assert len(lengths) == 1
        body = self.read_exact(int(lengths[0]), deadline)
        del header, lines
        peer.state["requestCount"] += 1
        assert peer.state["requestCount"] <= 6
        if path == "/fixture/observe":
            query = json.loads(body)
            assert set(query) == {"name", "waitExit"}
            name, wait_exit = query["name"], query["waitExit"]
            expected = [("a", True), ("b", False), ("b", True)]
            index = len(peer.state["controls"])
            assert index < len(expected) and (name, wait_exit) == expected[index]
            assert type(wait_exit) is bool and name in peer.pidfds
            fd = peer.pidfds[name]
            exited = bool(select.select([fd], [], [], 5 if wait_exit else 0)[0])
            result = {"name": name, "pid": peer.state["readers"][name]["pid"], "exited": exited}
            peer.state["controls"].append({"input": query, "result": result})
            peer.save()
            self.reply(json.dumps(result, separators=(",", ":")).encode(), b"application/json")
            return
        assert path == "/v1/responses", "Unexpected owned peer route"
        request = json.loads(body)
        assert isinstance(request, dict)
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") == PROMPT]
        assert markers == [PROMPT]
        outputs = [{"type": item["type"], "call_id": item["call_id"], "output": item["output"]}
                   for item in request.get("input", []) if item.get("type") == "function_call_output"]
        index = len(peer.state["requests"]) + 1
        assert index <= 3
        assert [entry["call_id"] for entry in outputs] == [f"owned-background-{n}" for n in NAMES[:index - 1]]
        peer.state["requests"].append({"index": index, "bodyBase64": base64.b64encode(body).decode(),
                                       "toolOutputs": outputs})
        if index > 1:
            name = NAMES[index - 2]
            output = outputs[-1]["output"]
            assert isinstance(output, str) and output.endswith("Output:\n" + ready(name))
            matches = re.findall(r"^Process running with session ID ([1-9][0-9]*)$", output, re.M)
            assert len(matches) == 1
            started = json.loads((peer.root / f"reader-{name}-started.json").read_text())
            assert set(started) == {"pid", "name", "cwd"}
            assert type(started["pid"]) is int and started["pid"] > 0
            assert started["name"] == name and started["cwd"] == str(peer.root / "workspace")
            assert name not in peer.pidfds
            peer.pidfds[name] = os.pidfd_open(started["pid"])
            assert not select.select([peer.pidfds[name]], [], [], 0)[0]
            peer.state["readers"][name] = {**started, "processId": matches[0]}
        if index < 3:
            name = NAMES[index - 1]
            item = {"type": "function_call", "name": "exec_command", "call_id": f"owned-background-{name}",
                    "arguments": json.dumps(peer.exec_args[name], separators=(",", ":"))}
        else:
            assert len({entry["pid"] for entry in peer.state["readers"].values()}) == 2
            assert len({entry["processId"] for entry in peer.state["readers"].values()}) == 2
            item = {"type": "message", "role": "assistant", "id": "owned-background-answer",
                    "content": [{"type": "output_text", "text": ANSWER}]}
        events = response_events(index, item)
        payload = "".join(f"event: {entry['type']}\ndata: "
                          + json.dumps(entry, separators=(",", ":")) + "\n\n" for entry in events).encode()
        assert len(payload) <= 65536
        peer.state["emitted"].append({"events": events, "bodyBase64": base64.b64encode(payload).decode()})
        peer.save()
        self.reply(payload, b"text/event-stream")

    def reply(self, body, kind):
        self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: " + kind
            + f"\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body)


class Server(socketserver.TCPServer):
    allow_reuse_address = False

    def handle_error(self, _request, _address):
        raise RuntimeError("Owned ordinary backend request failed")


class Peer:
    def __init__(self, root):
        assert hasattr(os, "pidfd_open"), "BLOCKED_ENV: Linux Python pidfd_open required"
        self.root, self.pidfds = root, {}
        self.state = {"requests": [], "emitted": [], "controls": [], "errors": [],
                      "requestCount": 0, "readers": {}}
        self.exec_args = {}
        for name in NAMES:
            argv = [sys.executable, str(root / "bin/reader.py"), "--reader", "--root", str(root), "--name", name]
            command = "exec " + " ".join(shlex.quote(part) for part in argv)
            self.exec_args[name] = {"cmd": command, "workdir": str(root / "workspace"),
                                    "shell": str(root / "bin/sh"), "login": False, "tty": True,
                                    "yield_time_ms": 1000, "max_output_tokens": 512}
        self.server = Server(("127.0.0.1", 0), Handler)
        self.server.peer = self
        self.save()

    def save(self):
        write_json(self.root / "peer.json", self.state)

    def configure(self):
        url = f"http://127.0.0.1:{self.server.server_address[1]}"
        catalog = self.root / "codex/models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary background fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned local background fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        (self.root / "codex/config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
cli_auth_credentials_store = "ephemeral"
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
codex_hooks = false
unified_exec = true
unified_exec_tty = true
[model_providers.fixture]
name = "Owned ordinary background provider"
base_url = "{url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def run(self):
        deadline = time.monotonic() + 50
        print(json.dumps({"pid": os.getpid(), "port": self.server.server_address[1],
                          "execArgs": self.exec_args}), flush=True)
        while True:
            remaining = deadline - time.monotonic()
            assert remaining > 0, "Owned background backend lifetime exceeded"
            readable, _, _ = select.select([self.server, sys.stdin], [], [], remaining)
            assert readable, "Owned background backend lifetime exceeded"
            if sys.stdin in readable:
                sys.stdin.buffer.read(1)
                return
            self.server.handle_request()

    def close(self):
        for fd in self.pidfds.values():
            os.close(fd)
        self.pidfds.clear()
        self.server.server_close()
        write_json(self.root / "peer-closed.json", {"pidfds": len(self.pidfds),
                    "serverClosed": self.server.socket.fileno() == -1})


def terminate(_signum, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--reader", action="store_true")
    parser.add_argument("--name", choices=NAMES)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.reader:
        assert args.name in NAMES
        reader(root, args.name)
        return
    assert args.name is None
    peer = Peer(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        peer.configure()
        peer.run()
    finally:
        peer.close()


if __name__ == "__main__":
    main()
