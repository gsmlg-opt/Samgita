#!/usr/bin/env python3
"""Fixed model-only peer for cancelling a replayed native command approval.

Target: apps/samgita_codex_driver/test/support/native_command_replay_cancel_fixture.py.
Never emits app-server protocol frames. Only an explicitly owned private shell
with fixed printf argv can be requested. Successful cancellation needs one call.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
from server_interaction_fixture import InteractionFixture


class CommandReplayCancelFixture(InteractionFixture):
    def item(self, index):
        if index == 2:
            return super().item(2)
        if index != 1:
            raise ValueError("Owned command-replay-cancel fixture exceeded two model calls")
        return {
            "type": "function_call",
            "name": "exec_command",
            "call_id": "command-replay-cancel-1",
            "arguments": json.dumps({
                "cmd": "printf samgita_interaction",
                "workdir": self.workspace,
                "shell": str(Path(self.workspace).parent / "bin" / "sh"),
                "login": False,
                "tty": False,
                "sandbox_permissions": "require_escalated",
                "justification": "Synthetic fixture approval only",
                "prefix_rule": ["printf"],
            }),
        }

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
    parser.add_argument("--scenario", choices=["command_replay_cancel"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = CommandReplayCancelFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        threading.Event().wait()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
