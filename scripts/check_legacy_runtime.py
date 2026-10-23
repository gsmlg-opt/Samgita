#!/usr/bin/env python3
"""Reject legacy integration identifiers, allowing comments and negative isolation assertions."""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCOPE = ["apps", "config", "deployment", "Dockerfile", "docker-compose.yml", "mix.exs",
         "mix.lock", "devenv.nix", ".env.example"]
FORBIDDEN = re.compile(r"SamgitaProvider|SamgitaMemory|samgita_provider|samgita_memory|Horde|pgvector|"
                       r"ANTHROPIC_API_KEY|CLAUDE_COMMAND|MEMORY_POOL_SIZE|DNS_CLUSTER_QUERY")
NEGATIVE_ATOMS = re.compile(r"refute app in \[[\s,:a-z_]{1,1000}\]")


def violations(path, source):
    negative = list(NEGATIVE_ATOMS.finditer(source)) if path.endswith("_test.exs") else []
    offset = 0
    result = []
    for line_no, line in enumerate(source.splitlines(keepends=True), 1):
        for match in FORBIDDEN.finditer(line):
            position = offset + match.start()
            if line.lstrip().startswith("#"):
                continue
            if any(span.start() <= position < span.end() for span in negative):
                continue
            result.append(f"{path}:{line_no}: forbidden runtime identifier {match.group()}")
        offset += len(line)
    return result


def main():
    # Git is already required by checkout; hosted runners need no extra search tool.
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *SCOPE],
        cwd=ROOT, text=True)
    found = []
    for path in filter(None, paths.split("\0")):
        source = (ROOT / path).read_text(errors="replace")
        found.extend(violations(path, source))
    if found:
        print("\n".join(found))
        return 1
    print("Legacy runtime scan passed (comments and literal negative assertions permitted).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
