#!/usr/bin/env python3
"""Owned model-only fixture: fixed printf command, cwd A/A/B/A, eight requests.

Integration target: apps/samgita_codex_driver/test/support/native_command_cache_context_fixture.py.
The pinned Codex executable, never this provider, generates app-server messages.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
from server_interaction_fixture import InteractionFixture


class CommandCacheContextFixture(InteractionFixture):
    def item(self, index):
        if not 1 <= index <= 8:
            raise ValueError("Owned command-cache fixture exhausted its eight requests")
        if index % 2 == 0:
            return super().item(2)
        workspace = Path(self.workspace)
        cwd = workspace / ("context-b" if index == 5 else "context-a")
        return {
            "type": "function_call",
            "name": "exec_command",
            "call_id": f"command-cache-call-{index}",
            "arguments": json.dumps({
                "cmd": "printf samgita_interaction",
                "workdir": str(cwd),
                "shell": str(workspace.parent / "bin" / "sh"),
                "login": False,
                "tty": False,
                "sandbox_permissions": "require_escalated",
                "justification": "Synthetic fixture approval only",
                "prefix_rule": ["printf"],
            }),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["command_cache_context"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = CommandCacheContextFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        threading.Event().wait()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
