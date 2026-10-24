#!/usr/bin/env python3
"""Fixed, owned-file approval lifetime cases for the pinned native Codex.

This is only a loopback model backend. The real executable creates approvals,
applies patches, persists threads and handles interruption. No arbitrary fixture
commands, model destinations or file targets are accepted.
"""
import argparse
import json

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


class LifetimeFixture(InteractionFixture):
    def item(self, index):
        limit = 6 if self.scenario == "patch_lifetime" else 4
        if self.scenario not in {"patch_lifetime", "patch_repeat"}:
            raise ValueError("Unknown owned-file approval scenario")
        if not 1 <= index <= limit:
            raise ValueError("Unexpected extra model request in approval fixture")
        if index % 2 == 0:
            return ModelFixture.item(self, 2)
        patches = {
            1: "*** Begin Patch\n*** Add File: approved.txt\n+owned first\n*** End Patch",
            3: ("*** Begin Patch\n*** Update File: approved.txt\n@@\n"
                "-owned first\n+owned second\n*** End Patch"),
            5: "*** Begin Patch\n*** Add File: other.txt\n+owned other\n*** End Patch",
        }
        return {
            "type": "function_call", "name": "exec_command",
            "call_id": f"lifetime-call-{index}",
            "arguments": json.dumps({
                "cmd": f"apply_patch <<'EOF'\n{patches[index]}\nEOF\n",
                "workdir": self.workspace, "login": False,
            }),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["patch_lifetime", "patch_repeat"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = LifetimeFixture(args.scenario, args.workspace, args.requests_file).start()
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
