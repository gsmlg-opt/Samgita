#!/usr/bin/env python3
"""Owned synthetic Responses provider and stdio MCP peer for deferred tools.

Codex performs discovery, routing, history association, and cancellation. This
fixture only returns deterministic provider events and synthetic MCP results.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture


SEARCH_ID = "deferred-search-1"
TOOL_ID = "deferred-echo-1"
NAMESPACE = "mcp__deferred"
MESSAGE = "quasar_echo_824 synthetic λ"


def tool(name, description, properties):
    return {"name": name, "description": description,
            "inputSchema": {"type": "object", "properties": properties,
                            "required": ["message"] if name == "echo" else list(properties),
                            "additionalProperties": False},
            "annotations": {"readOnlyHint": True, "destructiveHint": False}}


def mcp_result(message):
    method = message.get("method")
    if method == "initialize":
        return {"protocolVersion": message["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "synthetic-deferred", "version": "1"},
                "instructions": "Synthetic quasar tools for isolated discovery."}
    if method == "tools/list":
        return {"tools": [
            tool("echo", "quasar_echo_824 repeats the synthetic message", {
                "message": {"type": "string"}, "mode": {"type": "string"}}),
            tool("hidden", "nebula_hidden_913 inaccessible synthetic tool", {"secret": {"type": "string"}}),
        ]}
    if method in {"resources/list", "resources/templates/list"}:
        return {"resources" if method == "resources/list" else "resourceTemplates": []}
    if method == "tools/call":
        arguments = message["params"].get("arguments", {})
        mode = arguments.get("mode")
        if mode == "rpc_error":
            return {"error": {"code": -32043, "message": "synthetic deferred protocol failure",
                              "data": {"fixture": "deferred"}}}
        return {"content": [{"type": "text", "text": "Synthetic deferred MCP result: " + arguments["message"]}],
                "structuredContent": {"echo": arguments["message"], "association": TOOL_ID},
                "isError": mode == "tool_error"}
    if method == "ping":
        return {}
    return {"error": {"code": -32601, "message": "Synthetic method absent"}}


def mcp_server(journal):
    for line in sys.stdin:
        message = json.loads(line)
        with journal.open("a", encoding="utf-8") as target:
            target.write(json.dumps(message, ensure_ascii=False) + "\n")
        if "id" not in message:
            continue
        if message.get("method") == "tools/call" and message["params"].get("arguments", {}).get("mode") == "hold":
            # Keep reading stdin so Codex's cancellation notification is recorded.
            # EOF belongs to the session owner and shuts down this pending peer.
            continue
        result = mcp_result(message)
        response = {"jsonrpc": "2.0", "id": message["id"]}
        response.update(result if "error" in result else {"result": result})
        print(json.dumps(response, ensure_ascii=False), flush=True)


class DeferredFixture(ModelFixture):
    def response_item(self, index, request):
        if self.scenario == "gating":
            return super().item(2)
        if index == 1:
            query = "nebula_hidden_913" if self.scenario == "filtered" else "quasar_echo_824"
            if self.scenario == "empty_query":
                query = "   "
            return {"type": "tool_search_call", "call_id": SEARCH_ID, "execution": "client",
                    "arguments": {"query": query, "limit": 0 if self.scenario == "zero_limit" else 8}}
        if index == 2 and self.scenario not in {"filtered", "empty_query", "zero_limit"}:
            arguments = {"message": MESSAGE}
            if self.scenario in {"tool_error", "rpc_error", "hold"}:
                arguments["mode"] = self.scenario
            return {"type": "function_call", "call_id": TOOL_ID, "namespace": NAMESPACE,
                    "name": "echo", "arguments": json.dumps(arguments, ensure_ascii=False)}
        return super().item(2)

    def config(self, codex_home):
        super().config(codex_home)
        arguments = [str(Path(__file__).resolve()), "--mcp", "--journal", str(Path(codex_home, "mcp.jsonl"))]
        with Path(codex_home, "config.toml").open("a") as target:
            target.write('\n[features]\nshell_snapshot = false\n'
                         '\n[mcp_servers.deferred]\ncommand = ' + json.dumps(sys.executable)
                         + '\nargs = ' + json.dumps(arguments)
                         + '\nrequired = true\nstartup_timeout_sec = 10\ntool_timeout_sec = 15\n'
                         'enabled_tools = ["echo", "hidden"]\ndisabled_tools = ["hidden"]\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--journal", type=Path)
    parser.add_argument("--scenario", default="success",
                        choices=["success", "tool_error", "rpc_error", "filtered", "empty_query", "zero_limit", "gating", "hold"])
    parser.add_argument("--workspace")
    parser.add_argument("--codex-home")
    parser.add_argument("--requests-file", type=Path)
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal)
        return
    fixture = DeferredFixture(args.scenario, args.workspace, args.requests_file).start()
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
