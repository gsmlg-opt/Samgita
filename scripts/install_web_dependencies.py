#!/usr/bin/env python3
"""Frozen installation with bounded runtime, provenance diagnostics and optional clean-copy proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LOCAL_PACKAGES = ("phoenix", "phoenix_html", "phoenix_live_view", "phoenix_duskmoon")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def install(root, bun, seconds):
    web = root / "apps/samgita_web"
    version = subprocess.check_output([bun, "--version"], text=True, timeout=10).strip()
    print(f"Bun {version}; frozen install; timeout {seconds}s; root {root}", flush=True)
    for path in [web / "package.json", web / "bun.lock"]:
        print(f"{path.relative_to(root)} sha256={digest(path)}", flush=True)
    for name in LOCAL_PACKAGES:
        path = root / "deps" / name / "package.json"
        metadata = json.loads(path.read_text())
        print(f"local {name} version={metadata['version']} manifest_sha256={digest(path)}", flush=True)
    before = digest(web / "bun.lock")
    started = time.monotonic()
    process = subprocess.Popen([bun, "install", "--frozen-lockfile", "--verbose"],
                               cwd=web, start_new_session=True)
    try:
        result = process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print("Frozen installation timed out; terminating its process group.", flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
        return 124
    if digest(web / "bun.lock") != before:
        raise RuntimeError("Frozen installation modified the lockfile")
    print(f"Frozen install exited {result} in {time.monotonic() - started:.2f}s", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bun", default="bun")
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--isolated", action="store_true")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    if not args.isolated:
        return install(ROOT, args.bun, args.timeout)
    with tempfile.TemporaryDirectory(prefix="samgita-frozen-install-") as directory:
        root = Path(directory)
        web = root / "apps/samgita_web"
        web.mkdir(parents=True)
        for name in ("package.json", "bun.lock", "bunfig.toml"):
            shutil.copy2(ROOT / "apps/samgita_web" / name, web / name)
        for name in LOCAL_PACKAGES:
            shutil.copytree(ROOT / "deps" / name, root / "deps" / name,
                            ignore=shutil.ignore_patterns("node_modules", ".git", "_build", ".bun-cache"))
        # bunfig's relative cache directory is fresh inside this independent copy.
        return install(root, args.bun, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
