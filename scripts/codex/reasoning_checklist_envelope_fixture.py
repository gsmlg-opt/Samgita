#!/usr/bin/env python3
"""Finite local Responses input for native reasoning/checklist envelope checks.

Only provider SSE is produced. Codex itself parses the stream, executes its
metadata-only update_plan tool and emits app-server messages on its own stdio.
"""
import argparse
from http.server import BaseHTTPRequestHandler
import json
import os
from pathlib import Path
import re
import signal
import sys

from model_fixture import ModelFixture


CHECKLIST_ARGUMENTS = ('{"explanation":"Synthetic checklist λ🙂","plan":['
                       '{"step":"Owned completed step","status":"completed"},'
                       '{"step":"Owned current step","status":"in_progress"},'
                       '{"step":"Owned pending step","status":"pending"}]}')
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 2_097_152


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned provider journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def message(identity, text):
    return {"type": "message", "role": "assistant", "id": identity,
            "content": [{"type": "output_text", "text": text}]}


def reasoning_item():
    return {"type": "reasoning", "id": "owned-reasoning", "summary": [
        {"type": "summary_text", "text": "Synthetic summary λ🙂"},
        {"type": "summary_text", "text": "Synthetic second summary"}],
            "content": [{"type": "reasoning_text", "text": text}
                        for text in ["", "", "Synthetic raw α🙂"]]}


def response_events(scenario, index):
    identity = f"owned-envelope-response-{index}"
    if scenario == "reasoning":
        body = [
            {"type": "response.output_item.added", "item": {
                "type": "reasoning", "id": "owned-reasoning", "summary": []}},
            {"type": "response.reasoning_summary_part.added", "summary_index": 0},
            {"type": "response.reasoning_summary_text.delta", "summary_index": 0,
             "delta": "Synthetic summary "},
            {"type": "response.reasoning_summary_text.delta", "summary_index": 0,
             "delta": "λ🙂"},
            {"type": "response.reasoning_summary_part.added", "summary_index": 1},
            {"type": "response.reasoning_summary_text.delta", "summary_index": 1,
             "delta": "Synthetic second summary"},
            {"type": "response.reasoning_text.delta", "content_index": 2,
             "delta": "Synthetic raw "},
            {"type": "response.reasoning_text.delta", "content_index": 2,
             "delta": "α🙂"},
            {"type": "response.output_item.done", "item": reasoning_item()},
            {"type": "response.output_item.done", "item": message(
                "owned-reasoning-answer", "Synthetic reasoning finished")},
        ]
    elif index == 1:
        body = [{"type": "response.output_item.done", "item": {
            "type": "function_call", "name": "update_plan",
            "call_id": "owned-checklist-call", "arguments": CHECKLIST_ARGUMENTS}}]
    else:
        body = [{"type": "response.output_item.done", "item": message(
            "owned-checklist-answer", "Synthetic tool finished")}]
    result = [{"type": "response.created", "response": {"id": identity}}, *body,
              {"type": "response.completed", "response": {"id": identity, "usage": {
                  "input_tokens": 0, "input_tokens_details": None, "output_tokens": 0,
                  "output_tokens_details": None, "total_tokens": 0}}}]
    assert len(result) <= 64
    return result


def user_markers(request):
    return [part.get("text") for item in request["input"]
            if item.get("role") == "user" for part in item.get("content", [])
            if part.get("type") == "input_text"
            and part.get("text", "").startswith("synthetic:envelope-")]


def assert_request(scenario, index, request):
    assert request["model"] == "mock-model"
    assert user_markers(request) == [f"synthetic:envelope-{scenario}"]
    assert index <= (1 if scenario == "reasoning" else 2), "Extra owned inference"
    if scenario == "checklist" and index == 1:
        tools = [tool for tool in request["tools"] if tool.get("name") == "update_plan"]
        assert len(tools) == 1 and tools[0]["type"] == "function"
    if index == 2:
        outputs = [item for item in request["input"]
                   if item.get("type") == "function_call_output"]
        assert len(outputs) == 1
        identity = outputs[0].get("id")
        assert isinstance(identity, str) and re.fullmatch(
            r"fco_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", identity)
        assert outputs == [{"type": "function_call_output", "id": identity,
                            "call_id": "owned-checklist-call", "output": "Plan updated"}]


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
            request = json.loads(body)
            with fixture.lock:
                fixture.respond(self, request)
        except Exception as failure:
            write_json(fixture.root / "provider-error.json", {"error": type(failure).__name__})
            self.send_error(500)


class EnvelopeProvider(ModelFixture):
    def __init__(self, root, scenario):
        super().__init__(scenario, root / "workspace", root / "requests.json")
        self.root = root
        self.events = []
        self.server.RequestHandlerClass = ProviderHandler
        self.server.fixture = self
        write_json(self.requests_file, [])
        write_json(root / "provider-events.json", [])

    def respond(self, handler, request):
        index = len(self.requests) + 1
        assert_request(self.scenario, index, request)
        events = response_events(self.scenario, index)
        self.requests.append(request)
        self.events.append(events)
        write_json(self.requests_file, self.requests)
        write_json(self.root / "provider-events.json", self.events)
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        assert len(body) <= 65_536
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        handler.wfile.flush()

    def config(self, codex_home):
        catalog = Path(codex_home) / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned envelope fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned envelope fixture instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        Path(codex_home, "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
show_raw_agent_reasoning = true
hide_agent_reasoning = false
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
hooks = false
concurrent_reasoning_summaries = false
collaboration_modes = true
[tools.update_plan]
enabled = true
[model_providers.fixture]
name = "Owned envelope provider"
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
    parser.add_argument("--scenario", required=True, choices=["reasoning", "checklist"])
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    fixture = EnvelopeProvider(root, args.scenario)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.config(root / "codex")
        fixture.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        sys.stdin.buffer.read(1)
    finally:
        fixture.close()
        assert not fixture.thread.is_alive(), "Owned provider thread did not stop"


if __name__ == "__main__":
    main()
