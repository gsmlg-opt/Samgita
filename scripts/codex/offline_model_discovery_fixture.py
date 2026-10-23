#!/usr/bin/env python3
"""Run the actual pinned app-server with an offline catalog and no network egress.

This launcher never synthesizes app-server messages or model responses. The
native process replaces it in a private user/network namespace. Its only
network interface is loopback; no listener or external credential is required.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    assert Path(args.codex).is_absolute() and Path(args.codex).is_file()
    assert args.root.is_absolute() and args.root.is_dir()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux offline catalog profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])

    child = os.readlink("/proc/self/ns/net")
    assert child != args.parent_netns, "BLOCKED_ENV: unchanged network namespace"
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert len(links) == 1 and links[0]["ifname"] == "lo", "BLOCKED_ENV: nonloopback interface"
    assert all(row.get("dev") == "lo" and row.get("dst") != "default" for row in routes)
    journal = {"parent_netns": args.parent_netns, "child_netns": child,
               "interfaces": ["lo"], "default_route": False, "native_pid": os.getpid(),
               "namespace_owner_pid": os.getppid()}
    pending = args.root / "offline-model-discovery.pending"
    pending.write_text(json.dumps(journal))
    pending.replace(args.root / "offline-model-discovery.json")
    environment = {key: value for key, value in os.environ.items()
                   if key in {"HOME", "CODEX_HOME", "PATH", "TMPDIR", "NO_COLOR", "RUST_LOG"}}
    os.execve(args.codex, [args.codex, "app-server", "--listen", "stdio://"], environment)


if __name__ == "__main__":
    main()
