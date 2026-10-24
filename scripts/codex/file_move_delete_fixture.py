#!/usr/bin/env python3
"""Fixed model-only responses for native owned move/delete approval.

The peer never changes workspace files or synthesizes app-server notifications.
"""
import argparse
import json

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


PATCHES = {
    1: ("*** Begin Patch\n*** Update File: origin.txt\n"
        "*** Move to: moved.txt\n@@\n-owned before\n+owned moved\n*** End Patch"),
    3: "*** Begin Patch\n*** Delete File: moved.txt\n*** End Patch",
    5: "*** Begin Patch\n*** Delete File: moved.txt\n*** End Patch",
}


class FileMoveDeleteFixture(InteractionFixture):
    def __init__(self, workspace, requests_file):
        super().__init__("file_move_delete", workspace, requests_file)
        with self.requests_file.open("x") as target:
            target.write("[]")

    def item(self, index):
        if not 1 <= index <= 6:
            raise ValueError("Unexpected extra model request in file move/delete fixture")
        if index % 2 == 0:
            return ModelFixture.item(self, 2)
        return {
            "type": "function_call", "name": "exec_command",
            "call_id": f"file-move-delete-call-{index}",
            "arguments": json.dumps({
                "cmd": f"apply_patch <<'EOF'\n{PATCHES[index]}\nEOF\n",
                "workdir": self.workspace, "login": False,
            }),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["file_move_delete"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = FileMoveDeleteFixture(args.workspace, args.requests_file).start()
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
