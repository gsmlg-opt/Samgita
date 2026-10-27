#!/usr/bin/env python3
"""Finite Responses input for an actual interrupted V1 child and stable close.

Only local model SSE is produced. Stock Codex creates the child, interrupts it
through the public client request, closes it and persists every native item.
"""
import argparse
from http.server import BaseHTTPRequestHandler
import json
import os
from pathlib import Path
import signal
import sys
import threading

from model_fixture import ModelFixture


ROOT = "OWNED_V417_ROOT"
CHILD = "OWNED_V417_CHILD_HELD"
ANSWER = "Owned interrupted child closed."
SPAWN = "owned-v417-spawn"
CLOSE = "owned-v417-close"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 2_097_152


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned provider journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def texts(request):
    return [part.get("text") for item in request["input"]
            if item.get("role") == "user" for part in item.get("content", [])
            if part.get("type") == "input_text"]


def outputs(request):
    items = [item for item in request["input"] if item.get("type") == "function_call_output"]
    assert len({item["call_id"] for item in items}) == len(items)
    return {item["call_id"]: json.loads(item["output"]) for item in items}


def metadata(request):
    value = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
    assert all(isinstance(value.get(key), str) and value[key] for key in ("thread_id", "turn_id"))
    return value


def response_events(step, item):
    identity = f"owned-v417-response-{step}"
    return [
        {"type": "response.created", "response": {"id": identity}},
        {"type": "response.output_item.done", "item": item},
        {"type": "response.completed", "response": {"id": identity, "usage": {
            "input_tokens": 0, "input_tokens_details": None,
            "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
        }}},
    ]


class ProviderHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.send_error(404)

    def do_POST(self):
        fixture = self.server.fixture
        try:
            self.connection.settimeout(2)
            size = int(self.headers.get("Content-Length", "0"))
            assert self.path == "/v1/responses" and 0 < size <= MAX_REQUEST_BYTES
            body = self.rfile.read(size)
            assert len(body) == size, "Incomplete owned provider request"
            fixture.respond(self, json.loads(body))
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append(type(failure).__name__)
                fixture.save_state()
            self.send_error(500)


class InterruptedProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("interrupted", root / "workspace", root / "requests.json")
        self.root = root
        self.child_ready = threading.Event()
        self.root_ready = threading.Event()
        self.release = threading.Event()
        self.closing = threading.Event()
        self.events = []
        self.state = {
            "root_requests": 0, "child_requests": 0, "root_responses": [],
            "root_thread": None, "root_turn": None,
            "child_thread": None, "child_turn": None,
            "child_held": False, "root_held": False, "controls": [], "errors": [],
        }
        self.server.RequestHandlerClass = ProviderHandler
        self.server.fixture = self
        write_json(self.requests_file, [])
        write_json(root / "provider-events.json", [])
        self.save_state()

    def save_state(self):
        write_json(self.root / "provider-state.json", self.state)

    def respond(self, handler, request):
        assert request["model"] == "mock-model"
        assert request["reasoning"]["effort"] == "low"
        marker = next((text for text in reversed(texts(request)) if text in (ROOT, CHILD)), None)
        assert marker is not None
        identity = metadata(request)
        values = outputs(request)
        with self.lock:
            assert len(self.requests) < 4, "Extra owned inference"
            self.requests.append(request)
            if marker == CHILD:
                assert values == {}
                self.state["child_requests"] += 1
                assert self.state["child_requests"] == 1, "Repeated child inference"
                self.state["child_thread"] = identity["thread_id"]
                self.state["child_turn"] = identity["turn_id"]
                self.state["child_held"] = True
            else:
                self.state["root_requests"] += 1
                step = self.state["root_requests"]
                assert 1 <= step <= 3, "Repeated root inference"
                if step == 1:
                    self.state["root_thread"] = identity["thread_id"]
                    self.state["root_turn"] = identity["turn_id"]
                assert identity["thread_id"] == self.state["root_thread"]
                assert identity["turn_id"] == self.state["root_turn"]
                assert list(values) == [SPAWN, CLOSE][:step - 1]
                if step >= 2:
                    assert isinstance(values[SPAWN].get("agent_id"), str) and values[SPAWN]["agent_id"]
                if step == 2:
                    self.state["root_held"] = True
                if step == 3:
                    assert values[CLOSE] == {"previous_status": "interrupted"}
            write_json(self.requests_file, self.requests)
            self.save_state()

        if marker == CHILD:
            self.child_ready.set()
            # Teardown releases this handler before server_close joins it. No
            # response headers/SSE can turn the child into a completed success.
            assert self.closing.wait(30), "Owned held-child teardown deadline"
            return

        if step == 1:
            item = {"type": "function_call", "namespace": "multi_agent_v1",
                    "name": "spawn_agent", "call_id": SPAWN, "arguments": json.dumps({
                        "message": CHILD, "fork_context": False,
                        "model": "mock-model", "reasoning_effort": "low",
                    })}
            label = SPAWN
        elif step == 2:
            self.root_ready.set()
            assert self.release.wait(30), "Owned root continuation deadline"
            if self.closing.is_set():
                return
            assert self.child_ready.is_set()
            with self.lock:
                assert self.state["controls"] == ["after-native-interrupted"]
                assert values[SPAWN]["agent_id"] == self.state["child_thread"]
                assert self.state["child_thread"] != self.state["root_thread"]
                assert self.state["child_turn"] != self.state["root_turn"]
            item = {"type": "function_call", "namespace": "multi_agent_v1",
                    "name": "close_agent", "call_id": CLOSE,
                    "arguments": json.dumps({"target": values[SPAWN]["agent_id"]})}
            label = CLOSE
        else:
            item = {"type": "message", "role": "assistant", "id": "owned-v417-answer",
                    "content": [{"type": "output_text", "text": ANSWER}]}
            label = "root_final"
        events = response_events(step, item)
        with self.lock:
            self.state["root_responses"].append(label)
            self.events.append(events)
            write_json(self.root / "provider-events.json", self.events)
            self.save_state()
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        assert len(events) == 3 and len(body) <= 65_536
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        handler.wfile.flush()

    def continue_after_interrupt(self):
        with self.lock:
            assert self.child_ready.is_set() and self.root_ready.is_set()
            assert not self.closing.is_set() and self.state["controls"] == []
            self.state["controls"].append("after-native-interrupted")
            self.save_state()
        self.release.set()

    def close(self):
        self.closing.set()
        self.release.set()
        super().close()

    def config(self, codex_home):
        catalog = Path(codex_home) / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned interrupted collaboration fixture",
            "supported_reasoning_levels": [{"effort": "low", "description": "Owned low effort"}],
            "default_reasoning_level": "low", "multi_agent_version": "v1",
            "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned interrupted collaboration fixture instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        Path(codex_home, "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_reasoning_effort = "low"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
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
[agents]
enabled = true
max_depth = 2
max_concurrent_threads_per_session = 2
[features]
multi_agent = true
multi_agent_v2 = false
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = false
concurrent_reasoning_summaries = false
collaboration_modes = true
[model_providers.fixture]
name = "Owned interrupted collaboration provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    fixture = InterruptedProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.config(root / "codex")
        fixture.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        while True:
            command = sys.stdin.buffer.readline(1025)
            if not command:
                break
            assert command == b"after-native-interrupted\n", "Unexpected owned control"
            fixture.continue_after_interrupt()
    finally:
        fixture.close()
        assert not fixture.thread.is_alive(), "Owned provider thread did not stop"


if __name__ == "__main__":
    main()
