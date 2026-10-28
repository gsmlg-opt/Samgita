#!/usr/bin/env python3
"""One bounded loopback Responses stream, held after its first text delta.

Only provider SSE is synthetic. An unmodified native app-server produces every
protocol frame. The controller releases the remaining bytes through stdin.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import threading

INPUT = "Owned ordinary WebSocket detached stream λ🙂"
FIRST = "Owned visible λ "
REST = "detached completion β🙂"
ANSWER = FIRST + REST
MAX_BODY = 1_048_576


class Fixture:
    def __init__(self, root, requests):
        self.root = root
        self.requests_path = requests
        self.lock = threading.Lock()
        self.release = threading.Event()
        self.rows = []
        self.state = {"first_flushed": False, "released": False,
                      "finished": False, "errors": [], "handlers": 0,
                      "pid": os.getpid()}
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                try:
                    self.connection.settimeout(3)
                    size = int(self.headers.get("Content-Length", "0"))
                    assert self.path == "/v1/responses" and 0 < size <= MAX_BODY
                    body = self.rfile.read(size)
                    assert len(body) == size
                    owner.respond(self, json.loads(body), size)
                except Exception as failure:
                    with owner.lock:
                        owner.state["errors"].append(type(failure).__name__)
                        owner.save()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = False
        self.worker = threading.Thread(target=self.server.serve_forever)
        self.write(self.requests_path, [])
        self.save()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def write(self, path, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        assert len(data) <= 2_097_152
        temporary = path.with_suffix(".partial")
        temporary.write_bytes(data)
        temporary.replace(path)

    def save(self):
        self.write(self.root / "websocket-gap-state.json", self.state)

    def respond(self, handler, request, size):
        markers = [part.get("text") for item in request["input"]
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") == INPUT]
        assert request["model"] == "mock-model" and markers == [INPUT]
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        record = {"marker": INPUT, "model": "mock-model", "bytes": size,
                  "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"]}
        with self.lock:
            assert self.rows == [], "Unexpected second provider request"
            self.rows.append(record)
            self.state["handlers"] += 1
            self.write(self.requests_path, self.rows)
            self.save()
        initial_item = {"type": "message", "role": "assistant",
                        "id": "owned-websocket-gap-message",
                        "content": [{"type": "output_text", "text": ""}]}
        final_item = dict(initial_item, content=[{"type": "output_text", "text": ANSWER}])
        prefix = [
            {"type": "response.created", "response": {"id": "owned-websocket-gap-response"}},
            {"type": "response.output_item.added", "item": initial_item},
            {"type": "response.output_text.delta", "delta": FIRST},
        ]
        suffix = [
            {"type": "response.output_text.delta", "delta": REST},
            {"type": "response.output_item.done", "item": final_item},
            {"type": "response.completed", "response": {
                "id": "owned-websocket-gap-response", "usage": {
                    "input_tokens": 7, "input_tokens_details": {"cached_tokens": 0},
                    "output_tokens": 11,
                    "output_tokens_details": {"reasoning_tokens": 0}, "total_tokens": 18}}},
        ]

        def encode(events):
            return "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                           for event in events).encode()

        first, rest = encode(prefix), encode(suffix)
        assert len(first) + len(rest) <= 8192
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(first) + len(rest)))
        handler.end_headers()
        succeeded = False
        try:
            handler.wfile.write(first)
            handler.wfile.flush()
            with self.lock:
                self.state["first_flushed"] = True
                self.save()
            print(json.dumps({"event": "first_flushed", "handlers": 1, "requests": 1}), flush=True)
            assert self.release.wait(15), "Owned stream release deadline"
            handler.wfile.write(rest)
            handler.wfile.flush()
            succeeded = True
        finally:
            with self.lock:
                self.state["handlers"] -= 1
                self.state["finished"] = succeeded
                self.save()
            if succeeded:
                # State publication precedes this stdout control checkpoint.
                # The consumer awaits it before reading finished/handler state.
                print(json.dumps({"event": "stream_finished", "handlers": 0, "requests": 1}), flush=True)

    def config(self, codex_home):
        Path(codex_home, "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
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
[model_providers.fixture]
name = "Owned detached-stream provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def close(self):
        self.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(3)
        assert not self.worker.is_alive()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--scenario", choices=["ordinary-websocket-gap"], required=True)
    parser.add_argument("--requests-file", required=True, type=Path)
    args = parser.parse_args()
    fixture = Fixture(args.requests_file.parent, args.requests_file)
    fixture.config(args.codex_home)
    fixture.worker.start()
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        for line in sys.stdin:
            assert len(line) <= 128
            command = json.loads(line)
            if command == {"release": True}:
                with fixture.lock:
                    assert fixture.state["first_flushed"] and not fixture.state["released"]
                    fixture.state["released"] = True
                    fixture.save()
                fixture.release.set()
            elif command == {"stop": True}:
                break
            else:
                raise ValueError("Unexpected owned stream control")
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
