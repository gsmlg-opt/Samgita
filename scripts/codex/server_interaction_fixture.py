#!/usr/bin/env python3
"""Synthetic model/MCP peers for pinned-binary server-interaction tests.

The real Codex executable owns every app-server request and tool transition.
Only the model Responses backend and a local stdio MCP tool are fixtures.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture


class InteractionFixture(ModelFixture):
    def item(self, index):
        if index == 1 or (self.scenario == "command_repeat" and index == 3):
            name, arguments = self.tool()
            item = {"type": "function_call", "name": name,
                    "call_id": f"interaction-call-{index}",
                    "arguments": json.dumps(arguments)}
            if self.scenario == "mcp":
                item.update(namespace="mcp__fixture", name="confirm")
            return item
        return super().item(2)

    def tool(self):
        if self.scenario == "patch":
            patch = "*** Begin Patch\n*** Add File: approved.txt\n+synthetic patch\n*** End Patch"
            return "exec_command", {"cmd": f"apply_patch <<'EOF'\n{patch}\nEOF\n",
                                    "workdir": self.workspace, "login": False}
        if self.scenario == "permissions":
            return "request_permissions", {
                "reason": "Synthetic directory permission only",
                "permissions": {"file_system": {"write": ["."]}},
            }
        if self.scenario == "command_repeat":
            return "exec_command", {
                "cmd": "printf samgita_interaction", "workdir": self.workspace,
                "login": False, "sandbox_permissions": "require_escalated",
                "justification": "Synthetic fixture approval only", "prefix_rule": ["printf"],
            }
        if self.scenario == "mcp":
            return "mcp__fixture__confirm", {}
        raise ValueError("No tool for fixture scenario")

    def config(self, codex_home):
        super().config(codex_home)
        extra = "\n[features]\nshell_snapshot = false\n"
        if self.scenario == "permissions":
            extra += "request_permissions_tool = true\n"
        if self.scenario == "current_time":
            extra += ('\n[features.current_time_reminder]\nenabled = true\n'
                      'reminder_interval_seconds = 1\nclock_source = "external"\n')
        if self.scenario == "mcp":
            extra += ('\n[mcp_servers.fixture]\ncommand = ' + json.dumps(sys.executable)
                      + '\nargs = ' + json.dumps([str(Path(__file__).resolve()), "--mcp",
                                                "--journal", str(Path(codex_home, "mcp.json"))])
                      + '\nstartup_timeout_sec = 10\ntool_timeout_sec = 10\n')
        with Path(codex_home, "config.toml").open("a") as target:
            target.write(extra)


def send(message):
    print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)


def mcp_server(journal):
    pending = None
    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        identity = message.get("id")
        if method == "initialize":
            send({"id": identity, "result": {
                "protocolVersion": message["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "synthetic-elicitation", "version": "1"},
            }})
        elif method == "tools/list":
            send({"id": identity, "result": {"tools": [{
                "name": "confirm", "description": "Synthetic confirmation only",
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]}})
        elif method == "tools/call":
            pending = identity
            send({"id": "synthetic-form", "method": "elicitation/create", "params": {
                "mode": "form", "message": "Synthetic confirmation only",
                "requestedSchema": {"type": "object", "properties": {
                    "confirmed": {"type": "boolean"}}, "required": ["confirmed"]},
            }})
        elif identity == "synthetic-form" and pending is not None:
            Path(journal).write_text(json.dumps(message))
            send({"id": pending, "result": {"content": [{
                "type": "text", "text": json.dumps(message.get("result"))}], "isError": False}})
            pending = None
        elif method == "ping":
            send({"id": identity, "result": {}})
        elif identity is not None:
            send({"id": identity, "error": {"code": -32601, "message": "Fixture method absent"}})


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
    fixture = InteractionFixture(args.scenario, args.workspace, args.requests_file).start()
    # The current-time case deliberately uses an ordinary final model response.
    if args.scenario == "current_time":
        fixture.item = lambda _index: ModelFixture.item(fixture, 2)
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
