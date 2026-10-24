#!/usr/bin/env python3
"""Six fixed model responses for an owned multi-file patch approval case.

Only the loopback model peer is synthetic. Pinned Codex creates callbacks,
applies or rejects the patch, and owns the session approval cache.
"""
import argparse
import json

from approval_lifetime_fixture import LifetimeFixture
from model_fixture import ModelFixture


PATCHES = {
    1: "*** Begin Patch\n*** Add File: approved.txt\n+owned first\n*** End Patch",
    3: ("*** Begin Patch\n*** Update File: approved.txt\n@@\n"
        "-owned first\n+owned mixed\n"
        "*** Add File: other.txt\n+owned other\n*** End Patch"),
    5: ("*** Begin Patch\n*** Update File: approved.txt\n@@\n"
        "-owned first\n+owned reused\n*** End Patch"),
}


class MultifileFixture(LifetimeFixture):
    def __init__(self, workspace, requests_file):
        super().__init__("multifile_cache", workspace, requests_file)
        with self.requests_file.open("x") as target:
            target.write("[]")

    def item(self, index):
        if not 1 <= index <= 6:
            raise ValueError("Unexpected extra model request in multi-file approval fixture")
        if index % 2 == 0:
            return ModelFixture.item(self, 2)
        return {
            "type": "function_call", "name": "exec_command",
            "call_id": f"multifile-call-{index}",
            "arguments": json.dumps({
                "cmd": f"apply_patch <<'EOF'\n{PATCHES[index]}\nEOF\n",
                "workdir": self.workspace, "login": False,
            }),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["multifile_cache"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True)
    args = parser.parse_args()
    fixture = MultifileFixture(args.workspace, args.requests_file).start()
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
