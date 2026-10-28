#!/usr/bin/env python3
"""Ordinary label form dependencies for the stock pinned app-server.

Only the loopback model provider and an owned stdio MCP peer are synthetic.
No app-server frame is emitted here. ModelFixture's generic HTTP lifecycle is
reused, with both its config and item dispatch fully overridden.
"""
import argparse
import json
import os
from pathlib import Path
import sys

from model_fixture import ModelFixture


MESSAGE = "Choose an ordinary display label"
SCHEMA = {
    "type": "object",
    "properties": {
        "label": {"type": "string", "title": "Display label",
                  "description": "Ordinary synthetic label", "minLength": 1,
                  "maxLength": 64, "default": "Draft label"},
    },
    "required": ["label"],
}
REQUEST_META = {"fixture/request": {"topic": "ordinary-label"}}
DONE = "Ordinary label recorded"


class OrdinaryFormFixture(ModelFixture):
    def __init__(self, workspace, requests_file):
        super().__init__("assistant", workspace, requests_file)

    def item(self, index):
        if index in (1, 3):
            ordinal = 1 if index == 1 else 2
            return {"type": "function_call", "name": "select_label",
                    "namespace": "mcp__fixture",
                    "call_id": f"ordinary-label-call-{ordinal}", "arguments": "{}"}
        if index == 2:
            return {"type": "message", "role": "assistant", "id": "ordinary-label-done",
                    "content": [{"type": "output_text", "text": DONE}]}
        raise AssertionError("Unexpected ordinary form model continuation")

    def config(self, codex_home):
        arguments = [str(Path(__file__).resolve()), "--mcp", "--journal",
                     str(Path(codex_home, "ordinary-mcp-form.jsonl"))]
        # NativeLaunchFixture.ordinary_args supplies the existing fixed YOLO inputs.
        # No inherited mixed-scenario config or item branch is called.
        body = f'''model = "mock-model"
model_provider = "fixture"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
[model_providers.fixture]
name = "Owned ordinary label fixture"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[features]
shell_snapshot = false
mcp_2026_07_28 = false
remote_plugin = false
apps = false
memories = false
[memories]
generate_memories = false
use_memories = false
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[mcp_servers.fixture]
command = {json.dumps(sys.executable)}
args = {json.dumps(arguments)}
startup_timeout_sec = 10
tool_timeout_sec = 20
'''
        Path(codex_home, "config.toml").write_text(body)


def mcp_server(journal):
    path = Path(journal)
    count = 0
    calls = 0
    pending = None
    rows = []

    def record(row):
        nonlocal count
        count += 1
        assert count <= 64, "Owned MCP journal row bound"
        encoded = json.dumps(row, ensure_ascii=False)
        assert len(encoded.encode()) <= 65536, "Owned MCP frame bound"
        rows.append(encoded + "\n")
        temporary = path.with_suffix(".partial")
        temporary.write_text("".join(rows), encoding="utf-8")
        temporary.replace(path)

    def send(message):
        message = {"jsonrpc": "2.0", **message}
        record({"direction": "out", "message": message})
        print(json.dumps(message, ensure_ascii=False), flush=True)

    record({"kind": "peer-start", "pid": os.getpid()})
    for line in sys.stdin:
        assert len(line.encode()) <= 65536, "Owned MCP input bound"
        message = json.loads(line)
        record({"direction": "in", "message": message})
        identity = message.get("id")
        method = message.get("method")
        if method == "initialize":
            assert message["params"]["protocolVersion"] == "2025-06-18"
            send({"id": identity, "result": {
                "protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                "serverInfo": {"name": "ordinary-label-form", "version": "1"}}})
        elif method == "tools/list":
            send({"id": identity, "result": {"tools": [{
                "name": "select_label", "description": MESSAGE,
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False}}]}})
        elif method == "tools/call":
            assert pending is None and calls < 2, "Unexpected ordinary label call"
            assert message["params"]["name"] == "select_label"
            calls += 1
            pending = (identity, f"ordinary-label-form-{calls}")
            send({"id": pending[1], "method": "elicitation/create", "params": {
                "mode": "form", "message": MESSAGE, "_meta": REQUEST_META,
                "requestedSchema": SCHEMA}})
        elif pending and identity == pending[1]:
            # Echo the real Codex-produced MCP response; this peer does not
            # decide which action interruption should produce.
            send({"id": pending[0], "result": {"content": [{
                "type": "text", "text": json.dumps(message, ensure_ascii=False)}],
                "isError": False}})
            pending = None
        elif method == "ping":
            send({"id": identity, "result": {}})
        elif identity is not None:
            send({"id": identity, "error": {"code": -32601,
                                              "message": "Ordinary fixture method absent"}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--journal")
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal)
        return
    fixture = OrdinaryFormFixture(args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
