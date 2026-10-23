#!/usr/bin/env python3
"""Synthetic model/MCP peers for pinned-binary server-interaction tests.

The real Codex executable owns every app-server request and tool transition.
Only the model Responses backend and a local stdio MCP tool are fixtures.
"""
import argparse
import json
from pathlib import Path
import sys
import time

from model_fixture import ModelFixture


class InteractionFixture(ModelFixture):
    def item(self, index):
        if self.scenario == "mcp_mention" and index == 1:
            exposed = any(tool.get("type") == "namespace"
                          and tool.get("name") == "mcp__fixture"
                          and any(child.get("name") == "confirm"
                                  for child in tool.get("tools", []))
                          for tool in self.requests[-1].get("tools", []))
            if not exposed:
                return super().item(2)
        if index == 1 or (self.scenario == "command_repeat" and index == 3):
            name, arguments = self.tool()
            item = {"type": "function_call", "name": name,
                    "call_id": f"interaction-call-{index}",
                    "arguments": json.dumps(arguments)}
            if self.scenario in ("mcp", "mcp_mention"):
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
        if self.scenario in ("mcp", "mcp_mention"):
            return "mcp__fixture__confirm", {}
        raise ValueError("No tool for fixture scenario")

    def config(self, codex_home):
        super().config(codex_home)
        if self.scenario == "mcp_mention":
            config = Path(codex_home, "config.toml")
            config.write_text("mcp_optional_startup_grace_ms = 50\n" + config.read_text())
        extra = "\n[features]\nshell_snapshot = false\n"
        if self.scenario == "permissions":
            extra += "request_permissions_tool = true\n"
        if self.scenario == "current_time":
            extra += ('\n[features.current_time_reminder]\nenabled = true\n'
                      'reminder_interval_seconds = 1\nclock_source = "external"\n')
        if self.scenario in ("mcp", "mcp_mention"):
            arguments = [str(Path(__file__).resolve()), "--mcp",
                         "--journal", str(Path(codex_home, "mcp.json"))]
            if self.scenario == "mcp_mention":
                arguments += ["--startup-seen", str(Path(codex_home, "startup-seen")),
                              "--startup-release", str(Path(codex_home, "startup-release")),
                              "--call-journal", str(Path(codex_home, "mcp-calls.jsonl"))]
            extra += ('\n[mcp_servers.fixture]\ncommand = ' + json.dumps(sys.executable)
                      + '\nargs = ' + json.dumps(arguments)
                      + '\nstartup_timeout_sec = 10\ntool_timeout_sec = 10\n')
        with Path(codex_home, "config.toml").open("a") as target:
            target.write(extra)


def send(message):
    print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)


def mcp_server(journal, startup_seen=None, startup_release=None, call_journal=None):
    pending = None
    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        identity = message.get("id")
        if method == "initialize":
            if startup_seen:
                Path(startup_seen).write_text("initialize\n")
                deadline = time.monotonic() + 8
                while not Path(startup_release).exists():
                    if time.monotonic() >= deadline:
                        raise TimeoutError("Synthetic MCP startup release deadline")
                    time.sleep(0.01)
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
            if call_journal:
                with Path(call_journal).open("a") as target:
                    target.write(json.dumps(message["params"]) + "\n")
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
    parser.add_argument("--startup-seen")
    parser.add_argument("--startup-release")
    parser.add_argument("--call-journal")
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.startup_seen, args.startup_release, args.call_journal)
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
