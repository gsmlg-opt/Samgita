#!/usr/bin/env python3
"""Two ordinary Responses requests; hold the second before response.completed.

Only model-provider bytes are synthetic. Native Codex owns all app-server frames
and history. The first assistant message and turn finish normally. The second
assistant message finishes; a subsequent empty assistant item starts, but its
turn remains genuinely active until native turn/interrupt. The later item/start
is the serial-listener barrier for the first message's legacy active projection.
stdin then closes the held HTTP handler WITHOUT ever
emitting response.completed. This does not model an unfinished assistant item.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import threading

PREFIX = "Owned active-page completed prefix λ"
ACTIVE = "Owned active-page interrupted turn 🙂"
ANSWERS = ["Owned persisted prefix answer β", "Owned interrupted assistant answer γ🙂"]
IDS = ["owned-active-page-prefix-message", "owned-active-page-active-message"]
MAX_BODY = 1_048_576


class Fixture:
    def __init__(self, root, requests):
        self.root = root
        self.requests_path = requests
        self.lock = threading.Lock()
        self.finish_active = threading.Event()
        self.rows = []
        self.state = {"pid": os.getpid(), "prefix_completed_sent": False,
                      "active_item_flushed": False, "active_completed_sent": False,
                      "active_closed": False, "handlers": 0, "errors": []}
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
        self.write(self.root / "active-page-state.json", self.state)

    def respond(self, handler, request, size):
        markers = [part.get("text") for item in request["input"]
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") in [PREFIX, ACTIVE]]
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        with self.lock:
            index = len(self.rows)
            assert index in [0, 1] and request["model"] == "mock-model"
            assert markers == [[PREFIX], [PREFIX, ACTIVE]][index]
            if index == 1:
                assert self.state["prefix_completed_sent"]
            self.rows.append({"index": index, "markers": markers, "bytes": size,
                              "thread_id": metadata["thread_id"],
                              "turn_id": metadata["turn_id"]})
            self.state["handlers"] += 1
            self.write(self.requests_path, self.rows)
            self.save()

        response_id = f"owned-active-page-response-{index}"
        item = {"type": "message", "role": "assistant", "id": IDS[index],
                "content": [{"type": "output_text", "text": ANSWERS[index]}]}
        initial = [
            {"type": "response.created", "response": {"id": response_id}},
            {"type": "response.output_item.done", "item": item},
        ]
        if index == 1:
            initial.append({"type": "response.output_item.added", "item": {
                "type": "message", "role": "assistant",
                "id": "owned-active-page-trailing-message",
                "content": [{"type": "output_text", "text": ""}]}})
        terminal = {"type": "response.completed", "response": {
            "id": response_id, "usage": {
                "input_tokens": 7, "input_tokens_details": {"cached_tokens": 0},
                "output_tokens": 11, "output_tokens_details": {"reasoning_tokens": 0},
                "total_tokens": 18}}}

        def encode(events):
            return "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                           for event in events).encode()

        first, last = encode(initial), encode([terminal])
        assert len(first) + len(last) <= 8192
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(first) + len(last)))
        handler.end_headers()
        try:
            handler.wfile.write(first)
            handler.wfile.flush()
            if index == 0:
                with self.lock:
                    handler.wfile.write(last)
                    handler.wfile.flush()
                    self.state["prefix_completed_sent"] = True
                    self.save()
            else:
                with self.lock:
                    self.state["active_item_flushed"] = True
                    self.save()
                print(json.dumps({"event": "active_item_flushed", "requests": 2}), flush=True)
                assert self.finish_active.wait(15), "Owned active-response close deadline"
                # Native interruption has already settled. No terminal provider
                # bytes are written and no artificial app-server reply is used.
        finally:
            with self.lock:
                self.state["handlers"] -= 1
                if index == 1:
                    self.state["active_closed"] = True
                self.save()
            if index == 1:
                print(json.dumps({"event": "active_handler_closed", "requests": 2}), flush=True)

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
name = "Owned active-page provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')

    def close(self):
        self.finish_active.set()
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(3)
        assert not self.worker.is_alive()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--scenario", choices=["ordinary-active-page"], required=True)
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
            if command == {"close_active": True}:
                with fixture.lock:
                    assert fixture.state["active_item_flushed"] and not fixture.finish_active.is_set()
                fixture.finish_active.set()
            elif command == {"stop": True}:
                break
            else:
                raise ValueError("Unexpected owned active-page control")
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
