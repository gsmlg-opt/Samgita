#!/usr/bin/env python3
"""Check the pinned native bubblewrap write/deny prerequisite.

Only a fixed Python body runs through the pinned codex-linux-sandbox helper.
No model, listener, approval handler, arbitrary command, privilege change or
legacy sandbox fallback is available. All writes target fresh owned scratch.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
BWRAP_SHA256 = "77360cb751ccedc5971391444ac86a8a33c15b04d6b4a6fe45f5d25496e62c4c"
BEFORE = b"owned outside must remain unchanged\n"
AFTER = b"owned sandbox allowed write\n"
BODY = r'''
import errno,json,os,pathlib,sys
allowed,outside,host_netns=map(str,sys.argv[1:])
allowed,outside=pathlib.Path(allowed),pathlib.Path(outside)
assert allowed.is_file() and not allowed.is_symlink()
assert outside.is_file() and not outside.is_symlink()
assert outside.read_bytes()==b"owned outside must remain unchanged\n"
allowed.write_bytes(b"owned sandbox allowed write\n")
assert allowed.read_bytes()==b"owned sandbox allowed write\n"
try:
    outside.write_bytes(b"must be denied\n")
except OSError as error:
    assert error.errno in (errno.EROFS,errno.EACCES,errno.EPERM), error
    denied_errno=error.errno
else:
    raise AssertionError("native sandbox permitted outside write")
assert outside.read_bytes()==b"owned outside must remain unchanged\n"
assert os.readlink("/proc/self/ns/net")!=host_netns
print(json.dumps({"allowed_write":True,"outside_write_denied":True,
    "outside_unchanged":True,"denied_errno":denied_errno,
    "sandbox_network_namespace":os.readlink("/proc/self/ns/net")}))
'''


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def run_fixed(command, *, environment, cwd, timeout, executable=None):
    process = subprocess.Popen(command, executable=executable, env=environment,
        cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=3)
        raise RuntimeError("fixed owned prerequisite exceeded deadline: " +
                           stderr.decode(errors="replace")[:65_536])
    return process.returncode, stdout.decode(errors="replace"), stderr.decode(errors="replace")


def inside(args, binary):
    assert os.readlink("/proc/self/ns/user") != args.parent_userns
    assert os.readlink("/proc/self/ns/net") != args.parent_netns
    assert os.geteuid() == 0
    root = Path(args.root).resolve(strict=True)
    assert root.name.startswith("samgita-native-sandbox-probe-")
    env = {"PATH": os.environ["PATH"], "HOME": str(root / "home"),
           "CODEX_HOME": str(root / "codex"), "TMPDIR": str(root / "tmp"),
           "NO_COLOR": "1", "RUST_LOG": "off", "CODEX_DISABLE_REMOTE_CONTROL": "1",
           "PYTHONDONTWRITEBYTECODE": "1"}
    for directory in ["home", "codex", "tmp", "workspace", "outside", "empty-bin"]:
        (root / directory).mkdir()
    for command in [["ip", "link", "set", "lo", "up"],
                    ["ip", "-j", "link", "show"],
                    ["ip", "-4", "-j", "route", "show", "table", "all"],
                    ["ip", "-6", "-j", "route", "show", "table", "all"]]:
        status, output, stderr = run_fixed(command, environment=env, cwd=root, timeout=3)
        assert status == 0, stderr
        if command[1:3] == ["-j", "link"]:
            assert [row["ifname"] for row in json.loads(output)] == ["lo"]
        elif "route" in command:
            assert all(row.get("dst") not in {"default", "0.0.0.0/0", "::/0"}
                       for row in json.loads(output))

    allowed, outside = root / "workspace/allowed.txt", root / "outside/denied.txt"
    allowed.write_bytes(b"owned before\n")
    outside.write_bytes(BEFORE)
    # Prove the denial target is writable before applying the native sandbox.
    outside.write_bytes(BEFORE)
    profile = {"type": "managed", "network": "restricted", "file_system": {
        "type": "restricted", "entries": [
            {"path": {"type": "special", "value": {"kind": "root"}}, "access": "read"},
            {"path": {"type": "path", "path": str(root / "workspace")}, "access": "write"}
        ]}}
    # Fixed argv0 invokes the pin's helper directly, avoiding CLI config/model startup.
    command = ["codex-linux-sandbox", "--sandbox-policy-cwd", str(root / "workspace"),
        "--command-cwd", str(root / "workspace"), "--permission-profile", json.dumps(profile),
        "--", str(Path(sys.executable).resolve()), "-I", "-S", "-c", BODY,
        str(allowed), str(outside), args.parent_netns]
    system_bwrap = shutil.which("bwrap", path=env["PATH"])
    # Qualify the pinned fallback independently of whichever system tool exists.
    sandbox_env = dict(env, PATH=str(root / "empty-bin"))
    status, stdout, stderr = run_fixed(command, executable=str(binary),
        environment=sandbox_env, cwd=root / "workspace", timeout=15)
    # This environment is synthetic and allowlisted; stderr is the underlying
    # sandbox error, never an app-server approval request to accept/retry.
    report = {"check": "codex_native_sandbox_prerequisites", "exit_code": status,
        "binary_sha256": BINARY_SHA256, "bundled_bwrap_sha256": BWRAP_SHA256,
        "system_bwrap_path": system_bwrap, "forced_bundled_fallback": True,
        "private_user_namespace": os.readlink("/proc/self/ns/user"),
        "private_network_namespace": os.readlink("/proc/self/ns/net"),
        "native_stdout": stdout[:65_536], "native_stderr": stderr[:65_536]}
    (root / "native-result.json").write_text(json.dumps(report))
    print(json.dumps(report), flush=True)
    assert status == 0, "BLOCKED_ENV: fixed native sandbox launch failed"
    result = json.loads(stdout)
    assert result["allowed_write"] and result["outside_write_denied"] and result["outside_unchanged"]
    assert allowed.read_bytes() == AFTER and outside.read_bytes() == BEFORE
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--root")
    parser.add_argument("--parent-userns")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    assert sys.platform == "linux"
    binary = Path(os.environ["CODEX_BINARY"]).resolve(strict=True)
    assert digest(binary) == BINARY_SHA256
    sidecar = binary.parent / "codex-resources/bwrap"
    assert sidecar.is_file() and not sidecar.is_symlink() and os.access(sidecar, os.X_OK)
    assert digest(sidecar) == BWRAP_SHA256
    assert all(shutil.which(name) for name in ["unshare", "ip"])
    if args.inside:
        assert args.root and args.parent_userns and args.parent_netns
        return inside(args, binary)
    with tempfile.TemporaryDirectory(prefix="samgita-native-sandbox-probe-") as root:
        env = {"PATH": os.environ["PATH"], "CODEX_BINARY": str(binary),
               "PYTHONDONTWRITEBYTECODE": "1"}
        command = ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, str(Path(__file__).resolve()), "--inside",
            "--root", root, "--parent-userns", os.readlink("/proc/self/ns/user"),
            "--parent-netns", os.readlink("/proc/self/ns/net")]
        status, stdout, stderr = run_fixed(command, environment=env, cwd=root, timeout=30)
        print(stdout, end="")
        print(stderr, end="", file=sys.stderr)
        if status:
            print("BLOCKED_ENV: native sandbox prerequisite failed; no fallback", file=sys.stderr)
        return 0 if status == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, OSError, RuntimeError, ValueError) as error:
        print("BLOCKED_ENV: native sandbox prerequisite: " + str(error), file=sys.stderr)
        sys.exit(1)

