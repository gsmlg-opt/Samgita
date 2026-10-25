#!/usr/bin/env python3
"""Model-only independent command approvals for the immutable native binary.

Integration target is this repository-relative path. Reuse the unchanged
loopback fixture; only Codex may emit app-server approval frames. The first
Responses stream contains two fixed calls. The second contains only an answer.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
from server_interaction_fixture import InteractionFixture


class IndependentCommandApprovalsFixture(InteractionFixture):
    def command(self, label):
        if label not in ("A", "B"):
            raise ValueError("Unknown owned command label")
        return {
            "type": "function_call",
            "name": "exec_command",
            "call_id": f"independent-command-{label}",
            "arguments": json.dumps({
                "cmd": f"printf 'owned-{label}\\n' >> {label.lower()}.txt && printf owned-{label}",
                "workdir": self.workspace,
                "shell": str(Path(self.workspace).parent / "bin" / "sh"),
                "login": False,
                "tty": False,
                "sandbox_permissions": "require_escalated",
                "justification": f"Owned independent command {label} only",
                "prefix_rule": ["printf"],
            }),
        }

    def write_response(self, handler, index, request):
        if index == 2:
            return super().write_response(handler, index, request)
        if index != 1:
            raise ValueError("Owned independent approvals fixture exceeded two model calls")
        identity = "independent-approvals-response-1"
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": self.command("A")},
            {"type": "response.output_item.done", "item": self.command("B")},
            {"type": "response.completed", "response": {"id": identity, "usage": {
                "input_tokens": 0, "input_tokens_details": None,
                "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
            }}},
        ]
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)

    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(
            'cli_auth_credentials_store = "ephemeral"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + config.read_text()
            + '\napps = false\nplugins = false\nrecommended_plugins = false\n'
            'browser_use = false\ncomputer_use = false\n'
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["independent_command_approvals"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = IndependentCommandApprovalsFixture(
        args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        threading.Event().wait()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
