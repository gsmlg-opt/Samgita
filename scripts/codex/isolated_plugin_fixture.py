#!/usr/bin/env python3
"""Run immutable native Codex stdio in a private network with owned local state.

No synthetic app-server, HTTP peer, credential or model turn is provided.
The driver Stdio guardian owns and reaps the entire process group.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--proof", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    binary = args.codex.resolve(strict=True)
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == BINARY_SHA256
    if not args.inside:
        assert sys.platform == "linux" and shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: Linux/unshare/ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])

    interfaces = sorted(link["ifname"] for link in json.loads(subprocess.check_output(["ip", "-j", "link", "show"])))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    default_route = any(row.get("dst") == "default" for row in routes)
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace != args.parent_netns and interfaces == ["lo"] and not default_route
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == BINARY_SHA256
    proof = {"parent_namespace": args.parent_netns, "namespace": namespace,
             "interfaces": interfaces, "default_route": default_route,
             "native_pid": os.getpid(), "namespace_owner_pid": os.getppid()}
    temporary = args.proof.with_suffix(".tmp")
    temporary.write_text(json.dumps(proof))
    temporary.replace(args.proof)
    allowed = {"HOME", "CODEX_HOME", "PATH", "TMPDIR", "NO_COLOR", "RUST_LOG",
               "CODEX_DISABLE_REMOTE_CONTROL", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL",
               "GIT_TERMINAL_PROMPT"}
    environment = {key: value for key, value in os.environ.items() if key in allowed}
    os.chdir(root / "workspace")
    os.execve(binary, [str(binary), "app-server", "--listen", "stdio://"], environment)


if __name__ == "__main__":
    main()
