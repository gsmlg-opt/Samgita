#!/usr/bin/env python3
"""Owned Responses and stdio MCP peers for actual pinned native item tests.

Only dependencies are synthetic. The real Codex binary emits app-server items
and persists/reads them. No approval, external account or remote service is used.
"""
import argparse
import json
import os
from pathlib import Path
import sys

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


VARIANTS = ("structured_success", "tool_error")


def tool_result(variant):
    if variant == "structured_success":
        return {
            "content": [{"type": "text", "text": "Owned MCP structured success λ"}],
            "structuredContent": {"ok": True, "count": 3, "labels": ["blue", "λ"]},
            "_meta": {"fixture/result": {"variant": "structured_success", "sequence": 1},
                      "fixture/opaque": ["λ", None, 17]},
            "isError": False,
        }
    if variant == "tool_error":
        return {
            "content": [{"type": "text", "text": "Owned MCP tool failure λ"}],
            "structuredContent": {"ok": False, "reason": "owned-declined", "codes": [7, 9]},
            "_meta": {"fixture/result": {"variant": "tool_error", "sequence": 1},
                      "fixture/opaque": ["λ", None, 17]},
            "isError": True,
        }
    raise ValueError("Unsupported owned MCP result variant")


class ResultVariantsFixture(InteractionFixture):
    def __init__(self, variant, workspace, requests_file):
        super().__init__("mcp", workspace, requests_file)
        self.variant = variant
        with self.requests_file.open("x", encoding="utf-8") as target:
            target.write("[]")

    def config(self, codex_home):
        ModelFixture.config(self, codex_home)
        args = [str(Path(__file__).resolve()), "--mcp", "--scenario", self.variant,
                "--journal", str(Path(codex_home, "mcp-result-variants.jsonl"))]
        body = ("\n[features]\nshell_snapshot = false\nmcp_2026_07_28 = false\n"
                "[mcp_servers.fixture]\ncommand = " + json.dumps(sys.executable)
                + "\nargs = " + json.dumps(args)
                + "\nstartup_timeout_sec = 10\ntool_timeout_sec = 10\n")
        with Path(codex_home, "config.toml").open("a", encoding="utf-8") as target:
            target.write(body)


def mcp_server(journal, variant):
    def record(entry):
        with Path(journal).open("a", encoding="utf-8") as target:
            target.write(json.dumps(entry) + "\n")

    def send(message):
        message = {"jsonrpc": "2.0", **message}
        record({"direction": "out", "message": message})
        print(json.dumps(message), flush=True)

    # The native session owns this process. Its PID is independent of any item.
    record({"peer_started": {"pid": os.getpid(), "parent_pid": os.getppid(),
                             "variant": variant}})
    calls = 0
    for line in sys.stdin:
        message = json.loads(line)
        record({"direction": "in", "message": message})
        method = message.get("method")
        identity = message.get("id")
        if method == "initialize":
            assert message["params"]["protocolVersion"] == "2025-06-18"
            send({"id": identity, "result": {
                "protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                "serverInfo": {"name": "synthetic-result-variants", "version": "1"},
            }})
        elif method == "tools/list":
            send({"id": identity, "result": {"tools": [{
                "name": "confirm", "description": "Owned result variant only",
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]}})
        elif method == "tools/call":
            assert message["params"]["name"] == "confirm"
            assert message["params"]["arguments"] == {}
            calls += 1
            record({"effect": "tool-call-observed", "variant": variant, "sequence": calls})
            # Keep a repeated call visible rather than erasing its side effect.
            assert calls == 1
            send({"id": identity, "result": tool_result(variant)})
        elif method == "ping":
            send({"id": identity, "result": {}})
        elif identity is not None:
            send({"id": identity, "error": {
                "code": -32601, "message": "Synthetic method absent",
            }})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--journal")
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario", choices=VARIANTS, required=True)
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.scenario)
        return
    fixture = ResultVariantsFixture(args.scenario, args.workspace, args.requests_file).start()
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
