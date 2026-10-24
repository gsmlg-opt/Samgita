#!/usr/bin/env python3
"""Loopback model and stdio MCP dependencies for real native Form tests.

The stock pinned binary owns every app-server frame. This peer only journals
synthetic messages and returns the elicitation response as a tool result.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


MESSAGE = "Synthetic scalar form only"
META = {"fixture/request": {"marker": "scalar-fields"}}
SCHEMA = {
    "type": "object",
    "properties": {
        "confirmed": {"type": "boolean", "title": "Ready",
                      "description": "Synthetic flag", "default": False},
        "count": {"type": "integer", "title": "Count",
                  "description": "Synthetic integer", "minimum": 1,
                  "maximum": 9, "default": 3},
        "ratio": {"type": "number", "title": "Ratio",
                  "description": "Synthetic fraction", "minimum": 0.25,
                  "maximum": 1.75, "default": 0.5},
        "email": {"type": "string", "title": "Email",
                  "description": "Synthetic address", "minLength": 3,
                  "maxLength": 64, "format": "email",
                  "default": "fixture@example.invalid"},
    },
    "required": ["confirmed", "count", "ratio", "email"],
}


class FormFieldsFixture(InteractionFixture):
    def __init__(self, modern, workspace, requests_file):
        super().__init__("mcp", workspace, requests_file)
        self.modern = modern

    def config(self, codex_home):
        # Keep the shared InteractionFixture config and MCP implementation intact.
        ModelFixture.config(self, codex_home)
        args = [str(Path(__file__).resolve()), "--mcp", "--journal",
                str(Path(codex_home, "mcp-form-fields.jsonl"))]
        if self.modern:
            args.append("--modern")
        body = ("\n[features]\nshell_snapshot = false\n"
                f"mcp_2026_07_28 = {str(self.modern).lower()}\n"
                "[mcp_servers.fixture]\ncommand = " + json.dumps(sys.executable)
                + "\nargs = " + json.dumps(args)
                + "\nstartup_timeout_sec = 10\ntool_timeout_sec = 10\n")
        if self.modern:
            body += 'env = { CODEX_MCP_PROTOCOL_VERSION = "2026-07-28" }\n'
        with Path(codex_home, "config.toml").open("a") as target:
            target.write(body)


def mcp_server(journal, modern):
    protocol = "2026-07-28" if modern else "2025-06-18"
    pending = None

    def record(entry):
        with Path(journal).open("a", encoding="utf-8") as target:
            target.write(json.dumps(entry) + "\n")

    def send(message):
        message = {"jsonrpc": "2.0", **message}
        record({"direction": "out", "message": message})
        print(json.dumps(message), flush=True)

    def result(identity, value):
        if modern:
            value = {**value, "resultType": "complete"}
        send({"id": identity, "result": value})

    for line in sys.stdin:
        message = json.loads(line)
        record({"direction": "in", "message": message})
        method = message.get("method")
        identity = message.get("id")
        if method == "initialize":
            assert not modern
            assert message["params"]["protocolVersion"] == protocol
            result(identity, {"protocolVersion": protocol, "capabilities": {"tools": {}},
                              "serverInfo": {"name": "synthetic-form-fields", "version": "1"}})
        elif method == "server/discover":
            assert modern
            assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == protocol
            result(identity, {"supportedVersions": [protocol], "capabilities": {"tools": {}},
                              "_meta": {"io.modelcontextprotocol/serverInfo": {
                                  "name": "synthetic-form-fields", "version": "1"}},
                              "ttlMs": 0, "cacheScope": "private"})
        elif method == "tools/list":
            result(identity, {"tools": [{
                "name": "confirm", "description": "Synthetic scalar form only",
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]})
        elif method == "tools/call":
            assert pending is None
            assert message["params"]["name"] == "confirm"
            pending = identity
            send({"id": "synthetic-scalar-form", "method": "elicitation/create", "params": {
                "mode": "form", "message": MESSAGE, "_meta": META,
                "requestedSchema": SCHEMA,
            }})
        elif identity == "synthetic-scalar-form" and pending is not None:
            # A journal marker is the only accepted-action effect; no tool executes.
            if message.get("result", {}).get("action") == "accept":
                record({"effect": "accepted-form-marker"})
            result(pending, {"content": [{"type": "text", "text": json.dumps(message)}],
                             "isError": False})
            pending = None
        elif method == "ping":
            result(identity, {})
        elif identity is not None:
            send({"id": identity, "error": {"code": -32601,
                                              "message": "Synthetic method absent"}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--modern", action="store_true")
    parser.add_argument("--journal")
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.modern)
        return
    fixture = FormFieldsFixture(args.scenario == "modern", args.workspace, args.requests_file).start()
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
