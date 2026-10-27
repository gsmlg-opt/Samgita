#!/usr/bin/env python3
"""Finite loopback Responses input for one real native added-file patch.

The provider emits only model SSE. Codex applies the patch to its owned workspace
and produces all app-server messages itself; this fixture never constructs them.
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


ADDED = "owned added λ🙂\n"
PATCH_PARTS = [
    "*** Begin Patch\n*** Add File: owned-added.txt\n+owned added ",
    "λ🙂\n*** End Patch\n",
]
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


def response_events(index):
    identity = f"owned-file-change-response-{index}"
    if index == 1:
        item = {"type": "custom_tool_call", "id": "owned-patch-item",
                "name": "apply_patch", "call_id": "owned-patch-call",
                "input": "".join(PATCH_PARTS)}
        body = [
            {"type": "response.output_item.added",
             "item": {**item, "input": "", "status": "in_progress"}},
            *({"type": "response.custom_tool_call_input.delta",
               "item_id": "owned-patch-item", "call_id": "owned-patch-call",
               "delta": part} for part in PATCH_PARTS),
            {"type": "response.output_item.done", "item": item},
        ]
    else:
        body = [{"type": "response.output_item.done", "item": message(
            "owned-patch-answer", "Synthetic patch finished")}]
    result = [{"type": "response.created", "response": {"id": identity}}, *body,
              {"type": "response.completed", "response": {"id": identity, "usage": {
                  "input_tokens": 0, "input_tokens_details": None,
                  "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
              }}}]
    assert len(result) <= 8
    return result


def assert_request(index, request, workspace):
    assert index in (1, 2), "Extra owned inference"
    assert request["model"] == "mock-model"
    markers = [part.get("text") for item in request["input"]
               if item.get("role") == "user" for part in item.get("content", [])
               if part.get("type") == "input_text"
               and part.get("text", "").startswith("synthetic:file-change-")]
    assert markers == ["synthetic:file-change-add"]
    target = workspace / "owned-added.txt"
    assert (workspace / "untouched.txt").read_bytes() == b"owned untouched\n"
    if index == 1:
        assert not target.exists()
        tools = [tool for tool in request["tools"] if tool.get("name") == "apply_patch"]
        assert len(tools) == 1 and tools[0]["type"] == "custom"
    else:
        assert target.is_file() and target.read_bytes() == ADDED.encode()
        outputs = [item for item in request["input"]
                   if item.get("type") in ("function_call_output", "custom_tool_call_output")]
        assert len(outputs) == 1
        output = outputs[0]
        identity = output.get("id")
        assert isinstance(identity, str) and re.fullmatch(
            r"ctco_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", identity)
        assert set(output) == {"type", "id", "call_id", "output"}
        assert output["type"] == "custom_tool_call_output"
        assert output["call_id"] == "owned-patch-call"
        assert isinstance(output["output"], str) and re.fullmatch(
            r"Exit code: 0\nWall time: [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n"
            r"Success\. Updated the following files:\nA owned-added\.txt\n", output["output"])


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


class FileChangeProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("file-change-add", root / "workspace", root / "requests.json")
        self.root = root
        self.events = []
        self.server.RequestHandlerClass = ProviderHandler
        self.server.fixture = self
        write_json(self.requests_file, [])
        write_json(root / "provider-events.json", [])

    def respond(self, handler, request):
        index = len(self.requests) + 1
        assert_request(index, request, Path(self.workspace))
        events = response_events(index)
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
            "slug": "mock-model", "display_name": "Owned file-change fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "apply_patch_tool_type": "freeform",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned file-change fixture instructions."},
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
apply_patch_streaming_events = true
[model_providers.fixture]
name = "Owned file-change provider"
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
    fixture = FileChangeProvider(root)
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
