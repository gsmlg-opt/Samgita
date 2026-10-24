#!/usr/bin/env python3
"""Four fixed Responses items for an owned denied-directory permission case.

Only the local model provider is synthetic. Pinned Codex owns permission
intersection, sandbox enforcement, file approval callbacks and actual patches.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture
from permission_lifetime_fixture import PermissionLifetimeFixture


class PermissionEffectsFixture(PermissionLifetimeFixture):
    def __init__(self, workspace, requests_file):
        super().__init__("denied_directory", workspace, requests_file)
        with self.requests_file.open("x") as target:
            target.write("[]")

    def item(self, index):
        if not 1 <= index <= 4:
            raise ValueError("Unexpected extra model request in permission effects fixture")
        if index == 1:
            root = Path(self.workspace) / "writable"
            return self.function("request_permissions", "permission-effects-grant", {
                "reason": "Owned canonical denied-directory patch only",
                "permissions": {"file_system": {"entries": [
                    {"path": {"type": "path", "path": str(root)}, "access": "write"},
                    {"path": {"type": "path", "path": str(root / "secrets")}, "access": "deny"},
                ]}},
            })
        if index == 4:
            return ModelFixture.item(self, 2)
        patches = {
            2: ("*** Begin Patch\n*** Update File: writable/public.txt\n@@\n"
                "-owned public before\n+owned public after\n*** End Patch"),
            3: ("*** Begin Patch\n*** Update File: writable/secrets/private.txt\n@@\n"
                "-owned private before\n+owned private after\n*** End Patch"),
        }
        identity = "permission-effects-public" if index == 2 else "permission-effects-private"
        return self.function("exec_command", identity, {
            "cmd": f"apply_patch <<'EOF'\n{patches[index]}\nEOF\n",
            "workdir": self.workspace, "login": False,
        })

    @staticmethod
    def function(name, identity, arguments):
        return {"type": "function_call", "name": name, "call_id": identity,
                "arguments": json.dumps(arguments)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["denied_directory"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = PermissionEffectsFixture(args.workspace, args.requests_file).start()
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
