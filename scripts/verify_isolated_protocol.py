#!/usr/bin/env python3
"""Copy protocol projects outside the umbrella and prove a direct runtime host.

No Repo, root lockfile, root configuration or umbrella dependencies are copied.
The core verifier additionally builds its standalone consumer.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_LOCKFILE", "MIX_EXS", "MIX_ENV"):
    env.pop(key, None)
subprocess.run(["python3", str(root / "apps/samgita_protocol/scripts/verify_standalone.py")], env=env, check=True)
with tempfile.TemporaryDirectory(prefix="samgita-direct-consumer-") as scratch:
    for name in ("samgita_protocol", "samgita_protocol_websocket"):
        shutil.copytree(root / "apps" / name, Path(scratch) / name,
                        ignore=shutil.ignore_patterns("_build", "deps", ".devenv", ".git"))
    consumer = Path(scratch) / "samgita_protocol_websocket/examples/consumer"
    print("Outside-umbrella transport consumer:", consumer, flush=True)
    for args in (("deps.get",), ("compile", "--warnings-as-errors"), ("test",), ("format", "--check-formatted")):
        subprocess.run(["mix", *args], cwd=consumer, env=env, check=True)
