#!/usr/bin/env python3
"""Fixed owned-file effects for native turn/session permission lifetime tests.

Only the Responses model provider is synthetic. Native Codex owns approvals,
permission lifetime, patch application, thread storage and interruption.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class PermissionLifetimeFixture(ModelFixture):
    def item(self, index):
        limit = 3 if self.scenario == "permission_pending" else 5
        if self.scenario not in {"permission_lifetime", "permission_pending"}:
            raise ValueError("Unknown owned permission scenario")
        if not 1 <= index <= limit:
            raise ValueError("Unexpected extra model request in permission fixture")
        if index == 1:
            return {
                "type": "function_call", "name": "request_permissions",
                "call_id": "permission-lifetime-1",
                "arguments": json.dumps({
                    "reason": "Synthetic owned workspace permission lifetime only",
                    "permissions": {"file_system": {"write": ["."]}},
                }),
            }
        if index in {3, 5}:
            return ModelFixture.item(self, 2)
        patches = {
            2: ("*** Begin Patch\n*** Add File: granted-now.txt\n"
                "+owned turn grant\n*** End Patch"),
            4: ("*** Begin Patch\n*** Add File: granted-later.txt\n"
                "+owned session grant\n*** End Patch"),
        }
        return {
            "type": "function_call", "name": "exec_command",
            "call_id": f"permission-lifetime-{index}",
            "arguments": json.dumps({
                "cmd": f"apply_patch <<'EOF'\n{patches[index]}\nEOF\n",
                "workdir": self.workspace, "login": False,
            }),
        }

    def config(self, codex_home):
        super().config(codex_home)
        with Path(codex_home, "config.toml").open("a") as target:
            target.write("\n[features]\nshell_snapshot = false\nrequest_permissions_tool = true\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["permission_lifetime", "permission_pending"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = PermissionLifetimeFixture(args.scenario, args.workspace, args.requests_file).start()
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
