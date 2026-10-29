#!/usr/bin/env python3
"""Build and test the reusable driver consumer outside the umbrella, with real Codex.

Only the three reusable packages and an explicit model-provider fixture are
copied. No database, Phoenix endpoint or umbrella configuration is available.
This is ordinary functional evidence, not a full compatibility certificate.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from fetch_pin import BINARY_SHA256, CACHE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=CACHE / "codex-x86_64-unknown-linux-musl")
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit("BLOCKED_ENV: fetch the pinned executable or pass --binary")
    if hashlib.sha256(binary.read_bytes()).hexdigest() != BINARY_SHA256:
        raise SystemExit("Selected executable does not match the immutable qualification pin")

    source = Path(__file__).resolve().parents[2]
    env = os.environ.copy()
    for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_LOCKFILE", "MIX_EXS", "MIX_ENV", "MIX_CONFIG_PATH", "ERL_LIBS"):
        env.pop(key, None)
    env["CODEX_BINARY"] = str(binary)
    with tempfile.TemporaryDirectory(prefix="samgita-codex-independent-") as scratch:
        destination = Path(scratch)
        for package in ("samgita_protocol", "samgita_protocol_codex", "samgita_codex_driver"):
            shutil.copytree(source / "apps" / package, destination / package,
                ignore=shutil.ignore_patterns("_build", "deps", ".devenv", ".git", "__pycache__"))
        fixture = destination / "fixtures" / "ordinary_consumer_provider.py"
        fixture.parent.mkdir()
        for name in ("ordinary_consumer_provider.py", "model_fixture.py"):
            shutil.copyfile(source / "scripts/codex" / name, fixture.parent / name)
        env["CODEX_MODEL_FIXTURE_SCRIPT"] = str(fixture)
        consumer = destination / "samgita_codex_driver" / "examples" / "consumer"
        for command in (["mix", "deps.get"], ["mix", "compile", "--warnings-as-errors"],
                        ["mix", "test"], ["mix", "format", "--check-formatted"],
                        ["mix", "run", "run.exs"]):
            print("Independent consumer: " + " ".join(command), flush=True)
            subprocess.run(command, cwd=consumer, env=env, check=True, timeout=300)
        print("Independent consumer verified: actual pinned binary, no Repo/Phoenix/umbrella", flush=True)


if __name__ == "__main__":
    main()
