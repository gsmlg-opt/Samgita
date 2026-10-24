#!/usr/bin/env python3
"""Fixed local MCP typed-enum dependency for actual native Codex tests.

Only model/MCP peers are synthetic. No app-server frame is fabricated here.
Accepting the fixed enum answer writes one journal marker, never a command.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


MESSAGE = "Owned titled enum selection only"
META = {"fixture/request": {"marker": "titled-enum"}}
SCHEMA = {
    "type": "object",
    "properties": {
        "route": {
            "type": "string",
            "title": "Owned route λ",
            "description": "Choose a synthetic identifier, not its display title.",
            "oneOf": [
                {"const": "blue-id", "title": "Blue display"},
                {"const": "green-id-λ", "title": "Green display λ"},
            ],
            "default": "blue-id",
        }
    },
    "required": ["route"],
}


class TitledEnumFixture(InteractionFixture):
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
                str(Path(codex_home, "mcp-titled-enum.jsonl"))]
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
                              "serverInfo": {"name": "synthetic-titled-enum", "version": "1"}})
        elif method == "server/discover":
            assert modern
            assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == protocol
            result(identity, {"supportedVersions": [protocol], "capabilities": {"tools": {}},
                              "_meta": {"io.modelcontextprotocol/serverInfo": {
                                  "name": "synthetic-titled-enum", "version": "1"}},
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
            send({"id": "synthetic-titled-enum", "method": "elicitation/create", "params": {
                "mode": "form", "message": MESSAGE, "_meta": META,
                "requestedSchema": SCHEMA,
            }})
        elif identity == "synthetic-titled-enum" and pending is not None:
            assert message["result"]["action"] == "accept"
            assert message["result"]["content"] == {"route": "green-id-λ"}
            record({"effect": "accepted-titled-enum", "route": "green-id-λ"})
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
    fixture = TitledEnumFixture(args.scenario == "modern", args.workspace, args.requests_file).start()
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
