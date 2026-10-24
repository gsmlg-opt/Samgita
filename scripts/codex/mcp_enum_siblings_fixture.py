#!/usr/bin/env python3
"""Fixed local MCP enum-sibling dependency for actual native Codex tests.

Only model/MCP peers are synthetic. No app-server frame is fabricated here.
Accepting the fixed answer writes one journal marker, never a command.
This fixture verifies answer transport, not arbitrary schema constraint enforcement.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


MESSAGE = "Owned enum sibling selection only"
META = {"fixture/request": {"marker": "enum-siblings"}}
SCHEMA = {
    "type": "object",
    "properties": {
        "plainRoute": {
            "type": "string",
            "title": "Owned plain route λ",
            "description": "Choose a synthetic raw identifier.",
            "enum": [
                "plain-blue",
                "plain-green-λ"
            ],
            "default": "plain-blue"
        },
        "legacyRoute": {
            "type": "string",
            "title": "Owned legacy route λ",
            "description": "Legacy labels differ from their raw values.",
            "enum": [
                "legacy-blue",
                "legacy-green-λ"
            ],
            "enumNames": [
                "Legacy Blue display",
                "Legacy Green display λ"
            ],
            "default": "legacy-blue"
        },
        "plainRoutes": {
            "type": "array",
            "title": "Owned plain routes λ",
            "description": "Select two raw identifiers in explicit reply order.",
            "minItems": 1,
            "maxItems": 2,
            "items": {
                "type": "string",
                "enum": [
                    "plain-first",
                    "plain-second-λ",
                    "plain-third"
                ]
            },
            "default": [
                "plain-first"
            ]
        },
        "titledRoutes": {
            "type": "array",
            "title": "Owned titled routes λ",
            "description": "Submit const values, never the display titles.",
            "minItems": 1,
            "maxItems": 2,
            "items": {
                "anyOf": [
                    {
                        "const": "titled-first",
                        "title": "First display"
                    },
                    {
                        "const": "titled-second-λ",
                        "title": "Second display λ"
                    },
                    {
                        "const": "titled-third",
                        "title": "Third display"
                    }
                ]
            },
            "default": [
                "titled-first"
            ]
        }
    },
    "required": [
        "plainRoute",
        "legacyRoute",
        "plainRoutes",
        "titledRoutes"
    ]
}
ANSWER = {
    "plainRoute": "plain-green-λ",
    "legacyRoute": "legacy-green-λ",
    "plainRoutes": [
        "plain-third",
        "plain-second-λ"
    ],
    "titledRoutes": [
        "titled-third",
        "titled-second-λ"
    ]
}


class EnumSiblingsFixture(InteractionFixture):
    def __init__(self, modern, workspace, requests_file):
        super().__init__("mcp", workspace, requests_file)
        self.modern = modern
        # Create the empty observation before serving requests. Never overwrite
        # a journal that could already contain a request or hide a later call.
        with self.requests_file.open("x") as target:
            target.write("[]")

    def config(self, codex_home):
        ModelFixture.config(self, codex_home)
        args = [str(Path(__file__).resolve()), "--mcp", "--journal",
                str(Path(codex_home, "mcp-enum-siblings.jsonl"))]
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
                              "serverInfo": {"name": "synthetic-enum-siblings", "version": "1"}})
        elif method == "server/discover":
            assert modern
            assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == protocol
            result(identity, {"supportedVersions": [protocol], "capabilities": {"tools": {}},
                              "_meta": {"io.modelcontextprotocol/serverInfo": {
                                  "name": "synthetic-enum-siblings", "version": "1"}},
                              "ttlMs": 0, "cacheScope": "private"})
        elif method == "tools/list":
            result(identity, {"tools": [{
                "name": "confirm", "description": MESSAGE,
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]})
        elif method == "tools/call":
            assert pending is None
            assert message["params"]["name"] == "confirm"
            assert message["params"]["arguments"] == {}
            pending = identity
            send({"id": "synthetic-enum-siblings", "method": "elicitation/create", "params": {
                "mode": "form", "message": MESSAGE, "_meta": META,
                "requestedSchema": SCHEMA,
            }})
        elif identity == "synthetic-enum-siblings" and pending is not None:
            assert message["result"]["action"] == "accept"
            assert message["result"]["content"] == ANSWER
            record({"effect": "accepted-enum-siblings", "selection": ANSWER})
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
    parser.add_argument("--scenario", choices=["legacy", "modern"])
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.modern)
        return
    fixture = EnumSiblingsFixture(args.scenario == "modern", args.workspace, args.requests_file).start()
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
