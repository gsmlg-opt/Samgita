#!/usr/bin/env python3
"""Fixed local model responses for real native approval loss/replay tests.

The backend never handles app-server protocol traffic. Native Codex emits the
approvals, applies the only permitted patch, and reports native completion.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class ApprovalLossFixture(ModelFixture):
    def item(self, index):
        total = 2 if self.scenario == "file" else 3
        if self.scenario not in {"file", "permission"} or not 1 <= index <= total:
            raise ValueError("Unexpected approval loss fixture inference")
        if index == total:
            return ModelFixture.item(self, 2)
        if self.scenario == "permission" and index == 1:
            return {
                "type": "function_call", "name": "request_permissions",
                "call_id": "approval-loss-1",
                "arguments": json.dumps({
                    "reason": "Synthetic approval loss owned workspace only",
                    "permissions": {"file_system": {"write": ["."]}},
                }),
            }
        patch = ("*** Begin Patch\n*** Add File: loss-approved.txt\n"
                 "+owned recovered approval\n*** End Patch")
        return {
            "type": "function_call", "name": "exec_command",
            "call_id": f"approval-loss-{index}",
            "arguments": json.dumps({
                "cmd": f"apply_patch <<'EOF'\n{patch}\nEOF\n",
                "workdir": self.workspace, "login": False,
            }),
        }

    def config(self, codex_home):
        super().config(codex_home)
        with Path(codex_home, "config.toml").open("a") as target:
            target.write("\n[features]\napps = false\nplugins = false\n"
                         "recommended_plugins = false\nshell_snapshot = false\n"
                         "request_permissions_tool = true\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["file", "permission"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = ApprovalLossFixture(args.scenario, args.workspace, args.requests_file).start()
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
