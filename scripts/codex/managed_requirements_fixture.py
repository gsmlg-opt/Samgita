#!/usr/bin/env python3
"""Exec stock native app-server with child-only, read-only managed policy.

No provider, listener, task, credentials, transport emulator or debug override.
The private user/mount/net namespace pattern follows the repository's qualified
isolated_network_amendment_fixture.py. Host /etc is never changed; the owned
fixture root receives setup proof and allowlisted startup-failure metadata.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"


def fixed(command):
    return subprocess.check_output(command, timeout=5, stderr=subprocess.STDOUT).decode()


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def run(args):
    root, codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert root.name.startswith("samgita-managed-requirements-") and not args.root.is_symlink()
    assert hashlib.sha256(codex.read_bytes()).hexdigest() == SHA256
    assert all(shutil.which(tool) for tool in ["unshare", "ip", "mount"])

    if not args.inside:
        os.execvp("unshare", [
            "unshare", "--user", "--map-root-user", "--mount", "--net", "--fork",
            "--kill-child=TERM", sys.executable, "-I", str(Path(__file__).resolve()),
            *sys.argv[1:], "--inside",
            "--parent-user", os.readlink("/proc/self/ns/user"),
            "--parent-mnt", os.readlink("/proc/self/ns/mnt"),
            "--parent-net", os.readlink("/proc/self/ns/net"),
        ])

    names = ["user", "mnt", "net"]
    parents = {name: getattr(args, "parent_" + name) for name in names}
    namespaces = {name: os.readlink("/proc/self/ns/" + name) for name in names}
    assert all(namespaces[name] != parents[name] for name in names)
    assert os.geteuid() == 0, "BLOCKED_ENV: private mapped root required"
    fixed(["ip", "link", "set", "lo", "up"])
    links = json.loads(fixed(["ip", "-j", "link", "show"]))
    assert [link["ifname"] for link in links] == ["lo"]
    for family in ["-4", "-6"]:
        routes = json.loads(fixed(["ip", family, "-j", "route", "show", "table", "all"]))
        for route in routes:
            assert route.get("dev") == "lo"
            assert route.get("dst") not in ["default", "0.0.0.0/0", "::/0"]
            assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback

    source = root / "system"
    assert source.is_dir() and not source.is_symlink()
    assert (source / "requirements.toml").is_file()
    assert not any(path.is_symlink() for path in source.iterdir())
    fixed(["mount", "--make-rprivate", "/"])
    fixed(["mount", "-t", "tmpfs", "-o", "mode=0755,nodev,nosuid,noexec", "tmpfs", "/etc"])
    Path("/etc/codex").mkdir()
    fixed(["mount", "--bind", str(source), "/etc/codex"])
    fixed(["mount", "-o", "remount,bind,ro,nodev,nosuid,noexec", "/etc/codex"])
    assert Path("/etc/codex/requirements.toml").read_bytes() == (source / "requirements.toml").read_bytes()
    rows = [row.split() for row in Path("/proc/self/mountinfo").read_text().splitlines()]
    mounted = [row for row in rows if row[4] == "/etc/codex"]
    assert len(mounted) == 1 and "ro" in mounted[0][5].split(",")
    assert any(row[4] == "/etc" and "tmpfs" in row for row in rows)
    assert not Path("/etc/codex/config.toml").exists()
    # Stock discovery accepts .git directories only when HEAD exists. Keep
    # project-layer and trust discovery inside this disposable workspace.
    workspace = root / "workspace"
    assert workspace.is_dir() and not workspace.is_symlink()
    git_marker = workspace / ".git"
    git_marker.mkdir(exist_ok=True)
    assert not git_marker.is_symlink()
    head = git_marker / "HEAD"
    assert not head.is_symlink()
    head.write_text("ref: refs/heads/samgita-managed-fixture\n")
    write_json(root / "proof.json", {
        "parents": parents, "namespaces": namespaces, "interfaces": ["lo"],
        "default_route": False, "ipv6_default_route": False,
        "requirements_path": "/etc/codex/requirements.toml",
        "requirements_read_only": True, "private_etc_tmpfs": True,
        "project_root_marker": str(git_marker),
        "native_pid": os.getpid(), "namespace_owner_pid": os.getppid(),
        "binary_sha256": SHA256,
    })
    os.chdir(root / "workspace")
    os.execve(str(codex), [str(codex), "app-server", "--listen", "stdio://"], {
        "PATH": os.environ["PATH"], "HOME": str(root / "home"),
        "CODEX_HOME": str(root / "codex"), "TMPDIR": str(root / "tmp"),
        "CODEX_DISABLE_REMOTE_CONTROL": "1", "RUST_LOG": "off", "NO_COLOR": "1",
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--codex", type=Path, required=True)
    parser.add_argument("--inside", action="store_true")
    for name in ["user", "mnt", "net"]:
        parser.add_argument("--parent-" + name)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        write_json(args.root / "startup-failure.json", {
            "status": "BLOCKED_ENV", "stage": "private managed policy setup",
            "error_type": type(error).__name__,
        })
        raise


if __name__ == "__main__":
    main()
