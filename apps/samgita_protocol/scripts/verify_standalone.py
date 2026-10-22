#!/usr/bin/env python3
"""Optional build proof in a temporary directory outside the repository (Python stdlib only)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="samgita-protocol-consumer-") as scratch:
    package = Path(scratch) / "samgita_protocol"
    shutil.copytree(source, package, ignore=shutil.ignore_patterns("_build", "deps", ".devenv", ".git"))
    env = os.environ.copy()
    # Never inherit build/dependency/config overrides from a shell running the umbrella.
    for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_LOCKFILE", "MIX_EXS", "MIX_ENV"):
        env.pop(key, None)
    for directory in (package, package / "examples/consumer"):
        print(f"Independent project: {directory.relative_to(Path(scratch))}", flush=True)
        for args in (("deps.get",), ("compile", "--warnings-as-errors"), ("test",), ("format", "--check-formatted")):
            subprocess.run(["mix", *args], cwd=directory, env=env, check=True)
