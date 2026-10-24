#!/usr/bin/env python3
"""Owned MCP/model dependencies for stock Codex arbitrary-form qualification.

No app-server messages are synthesized. The two custom MCP request methods are
the exact producers in pinned rmcp-client/src/elicitation_client_service.rs.
Only a fixed accept response writes a synthetic journal effect marker.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


MESSAGE = "Owned arbitrary form decision only"
META = {"fixture/request": {"kind": "arbitrary-form", "nested": [True, None, "λ"]}}
SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "template": {
            "type": "openai/imagePicker",
            "items": [{
                "id": "owned-review-λ", "title": "Owned review λ",
                "image": "data:image/svg+xml;base64,PHN2Zy8+",
            }],
        },
        "settings": {
            "type": "object",
            "properties": {
                "labels": {"type": "array", "items": {"type": "string"}},
                "threshold": {"type": ["number", "null"]},
            },
            "required": ["labels"],
            "additionalProperties": False,
        },
    },
    "required": ["template", "settings"],
    "additionalProperties": False,
}
SELECTION = {"template": "owned-review-λ",
             "settings": {"labels": ["first", "λ"], "threshold": 0.625}}
REQUEST_ID = "synthetic-arbitrary-form"
EXTENSIONS = {"openai/form": {}, "openai/elicitation": {"form": {}}}


class OpenAiFormsFixture(InteractionFixture):
    def __init__(self, modern, method, action, workspace, requests_file):
        super().__init__("mcp", workspace, requests_file)
        self.modern, self.method, self.action = modern, method, action
        # Exclusive creation occurs before the loopback provider starts. Do not
        # reset journals after requests could have occurred.
        with self.requests_file.open("x") as target:
            target.write("[]")

    def config(self, codex_home):
        ModelFixture.config(self, codex_home)
        args = [str(Path(__file__).resolve()), "--mcp", "--journal",
                str(Path(codex_home, "mcp-openai-forms.jsonl")),
                "--method", self.method, "--action", self.action]
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


def mcp_server(journal, modern, method, action):
    protocol = "2026-07-28" if modern else "2025-06-18"
    pending = None
    calls = 0

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
        incoming_method = message.get("method")
        identity = message.get("id")
        if incoming_method == "initialize":
            assert not modern
            assert message["params"]["protocolVersion"] == protocol
            assert message["params"]["capabilities"]["extensions"] == EXTENSIONS
            result(identity, {"protocolVersion": protocol, "capabilities": {"tools": {}},
                              "serverInfo": {"name": "synthetic-arbitrary-form", "version": "1"}})
        elif incoming_method == "server/discover":
            assert modern
            meta = message["params"]["_meta"]
            assert meta["io.modelcontextprotocol/protocolVersion"] == protocol
            assert meta["io.modelcontextprotocol/clientCapabilities"]["extensions"] == EXTENSIONS
            result(identity, {"supportedVersions": [protocol], "capabilities": {"tools": {}},
                              "_meta": {"io.modelcontextprotocol/serverInfo": {
                                  "name": "synthetic-arbitrary-form", "version": "1"}},
                              "ttlMs": 0, "cacheScope": "private"})
        elif incoming_method == "tools/list":
            result(identity, {"tools": [{
                "name": "confirm", "description": MESSAGE,
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]})
        elif incoming_method == "tools/call":
            calls += 1
            assert calls == 1 and pending is None
            assert message["params"]["name"] == "confirm"
            assert message["params"]["arguments"] == {}
            pending = identity
            params = {"message": MESSAGE, "_meta": META, "requestedSchema": SCHEMA}
            # Legacy extension has no mode tag; the successor custom method
            # uses mode=form and is rendered as openaiForm on app-server.
            if method == "openai/elicitation/create":
                params["mode"] = "form"
            send({"id": REQUEST_ID, "method": method, "params": params})
        elif identity == REQUEST_ID:
            assert pending is not None and "error" not in message
            expected = {"action": action,
                        "_meta": {"fixture/response": {"decision": action, "marker": "owned-λ"}}}
            if action == "accept":
                expected["content"] = SELECTION
            assert message["result"] == expected
            record({"decision_observed": action})
            if action == "accept":
                record({"effect": "accepted-arbitrary-form", "selection": SELECTION})
            result(pending, {"content": [{"type": "text", "text": json.dumps(message)}],
                             "isError": False})
            pending = None
        elif incoming_method == "ping":
            result(identity, {})
        elif identity is not None:
            send({"id": identity, "error": {"code": -32601,
                                              "message": "Synthetic method absent"}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--modern", action="store_true")
    parser.add_argument("--journal")
    parser.add_argument("--method", choices=["openai/form", "openai/elicitation/create"])
    parser.add_argument("--action", choices=["accept", "decline", "cancel"])
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.modern, args.method, args.action)
        return
    profile, mode, action = args.scenario.split(":")
    assert profile in ("legacy", "modern") and mode in ("legacy", "successor")
    assert action in ("accept", "decline", "cancel")
    method = "openai/form" if mode == "legacy" else "openai/elicitation/create"
    fixture = OpenAiFormsFixture(profile == "modern", method, action,
                                 args.workspace, args.requests_file).start()
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
