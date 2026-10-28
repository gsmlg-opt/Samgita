#!/usr/bin/env python3
"""One ordinary generic child; warm/cold MCP catalogs come from the native runtime."""
import argparse
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from subagent_search_provenance_fixture import ProvenanceFixture


class Fixture(ProvenanceFixture):
    def config(self, codex_home):
        root = Path(codex_home).parent
        self.lifecycle = root / "ordinary-mcp-provider-lifecycle.json"
        self.lifecycle.write_text(json.dumps({"started": os.getpid()}))
        super().config(codex_home)
        peer = Path(__file__).with_name("ordinary_mcp_not_started_peer.py").resolve()
        journals = root / "ordinary-mcp-peers"
        journals.mkdir()
        config = Path(codex_home, "config.toml")
        with config.open("a") as output:
            output.write("\n[mcp_servers.ordinary_dormant]\n"
                         + "command = " + json.dumps(sys.executable) + "\n"
                         + "args = " + json.dumps([str(peer), "--journal-dir", str(journals)]) + "\n"
                         + "cwd = " + json.dumps(self.workspace) + "\n")

    def close(self):
        super().close()
        assert not self.thread.is_alive(), "Owned provider thread shutdown unconfirmed"
        temporary = self.lifecycle.with_suffix(".partial")
        temporary.write_text(json.dumps({"started": os.getpid(), "closed": os.getpid()}))
        temporary.replace(self.lifecycle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = Fixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
