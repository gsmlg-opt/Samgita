#!/usr/bin/env python3
"""Fail explicitly if the native qualification's private namespaces are unavailable.

Only fixed unshare/ip commands run. No listener, native executable, account,
credential, environment dump or host permission change is involved.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def fail(message):
    print(f"BLOCKED_ENV: Codex namespace prerequisite: {message}", file=sys.stderr)
    return 1


def run_ip(arguments):
    # Arguments are fixed by the caller below; never accept arbitrary tool input.
    result = subprocess.run(["ip", *arguments], capture_output=True, text=True,
                            timeout=3, check=False)
    if result.returncode:
        print(f"ip {' '.join(arguments)} exited {result.returncode}", file=sys.stderr)
        if result.stderr:
            print(result.stderr, end="" if result.stderr.endswith("\n") else "\n",
                  file=sys.stderr)
        raise ValueError("fixed ip prerequisite command failed")
    return result.stdout


def inside(args):
    if os.readlink("/proc/self/ns/user") == args.parent_userns:
        return fail("user namespace did not change")
    if os.readlink("/proc/self/ns/net") == args.parent_netns:
        return fail("network namespace did not change")
    if os.geteuid() != 0:
        return fail("map-root-user did not map the child effective UID to zero")

    run_ip(["link", "set", "lo", "up"])
    links = json.loads(run_ip(["-j", "link", "show"]))
    if [row.get("ifname") for row in links] != ["lo"]:
        return fail("private namespace does not contain exactly the loopback interface")
    if "UP" not in links[0].get("flags", []):
        return fail("private loopback interface did not become UP")

    for family in ["-4", "-6"]:
        routes = json.loads(run_ip([family, "-j", "route", "show", "table", "all"]))
        if any(row.get("dst") in {"default", "0.0.0.0/0", "::/0"} for row in routes):
            return fail(f"private namespace has an unexpected {family} default route")

    print(json.dumps({"check": "codex_namespace_prerequisites", "status": "passed",
                      "user_namespace_changed": True, "network_namespace_changed": True,
                      "interfaces": ["lo"], "loopback_up": True,
                      "ipv4_default_route": False, "ipv6_default_route": False}))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-userns")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if sys.platform != "linux":
        return fail("Linux is required")
    if any(shutil.which(tool) is None for tool in ["unshare", "ip"]):
        return fail("unshare and ip executables are required")

    try:
        if args.inside:
            if not args.parent_userns or not args.parent_netns:
                return fail("internal namespace comparison arguments are missing")
            return inside(args)

        command = ["unshare", "--user", "--map-root-user", "--net", "--fork",
                   "--kill-child=TERM", sys.executable, str(Path(__file__).resolve()),
                   "--inside", "--parent-userns", os.readlink("/proc/self/ns/user"),
                   "--parent-netns", os.readlink("/proc/self/ns/net")]
        result = subprocess.run(command, capture_output=True, text=True, timeout=15, check=False)
        # Only output from this fixed prerequisite script/unshare/ip is printed.
        # Never print the ambient environment or invoke the native controller.
        if result.stdout:
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
        if result.stderr:
            print(result.stderr, end="" if result.stderr.endswith("\n") else "\n",
                  file=sys.stderr)
        if result.returncode:
            return fail(f"private user/network namespace probe exited {result.returncode}")
        return 0
    except subprocess.TimeoutExpired:
        return fail("fixed namespace/ip prerequisite command exceeded its deadline")
    except (OSError, ValueError) as error:
        return fail(str(error))


if __name__ == "__main__":
    sys.exit(main())
