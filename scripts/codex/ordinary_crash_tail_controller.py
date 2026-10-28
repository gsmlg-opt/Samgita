#!/usr/bin/env python3
"""One checked-owned native SIGKILL for the ordinary process-crash-tail case.

This does not launch Codex, write native history, change transport behavior or
signal the stdio owner. The caller supplies the identity snapshot from its exact
owned native/helper pair. Both process identities are retained with pidfds while
all expected facts are checked. Exactly one native pidfd signal is permitted.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import sys

MAX_SPEC = 16_384


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    with open(path, "rb") as source:
        value = hashlib.sha256()
        for block in iter(lambda: source.read(131_072), b""):
            value.update(block)
    return value.hexdigest()


def facts(pid):
    parts = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return {"ppid": int(parts[1]), "pgrp": int(parts[2]),
            "session": int(parts[3]), "start": parts[19]}


def argv(pid):
    data = Path(f"/proc/{pid}/cmdline").read_bytes()
    require(0 < len(data) <= 16_384 and data.endswith(b"\0"), "Owned argv bound")
    return [os.fsdecode(part) for part in data[:-1].split(b"\0")]


def homes(pid):
    data = Path(f"/proc/{pid}/environ").read_bytes()
    require(len(data) <= 131_072, "Owned environment bound")
    result = {}
    for part in data.split(b"\0"):
        name, separator, value = part.partition(b"=")
        if separator and name in [b"HOME", b"CODEX_HOME"]:
            require(name not in result, "Duplicate owned home field")
            result[name] = os.fsdecode(value)
    return result


def same_executable(pid, expected):
    actual = os.stat(f"/proc/{pid}/exe")
    wanted = os.stat(expected)
    return (actual.st_dev, actual.st_ino) == (wanted.st_dev, wanted.st_ino)


def alive(fd):
    return not select.select([fd], [], [], 0)[0]


def run(spec):
    require(sys.platform == "linux" and hasattr(os, "pidfd_open")
            and hasattr(signal, "pidfd_send_signal"),
            "BLOCKED_ENV: Linux Python pidfd primitives required")
    keys = {"parent_pid", "native_pid", "helper_pid", "native_start", "helper_start",
            "native_argv", "helper_argv", "home", "codex_home", "cwd",
            "binary", "binary_sha256", "helper", "helper_sha256", "python"}
    require(set(spec) == keys, "Owned crash spec fields")
    native, helper, parent = (spec[name] for name in ["native_pid", "helper_pid", "parent_pid"])
    require(all(type(pid) is int and pid > 1 for pid in [native, helper, parent]),
            "Owned crash PID types")
    require(len({native, helper, parent, os.getpid()}) == 4,
            "Owned crash parent binding")
    require(spec["native_start"].isdigit() and spec["helper_start"].isdigit(),
            "Owned crash start identities")
    require(spec["native_argv"][0] == spec["binary"]
            and spec["helper_argv"] == [spec["python"], spec["helper"], *spec["native_argv"]],
            "Owned crash expected argv relationship")
    require(digest(spec["binary"]) == spec["binary_sha256"], "Owned native binary hash")
    require(digest(spec["helper"]) == spec["helper_sha256"], "Owned stdio helper hash")
    native_fd = os.pidfd_open(native)
    try:
        helper_fd = os.pidfd_open(helper)
        try:
            require(alive(native_fd) and alive(helper_fd), "Owned pair exited before crash")
            before_native, before_helper = facts(native), facts(helper)
            require(before_native == {"ppid": helper, "pgrp": native, "session": native,
                                      "start": spec["native_start"]}, "Owned native process identity")
            require(before_helper["ppid"] == parent and before_helper["start"] == spec["helper_start"],
                    "Owned helper process identity")
            require(argv(native) == spec["native_argv"] and argv(helper) == spec["helper_argv"],
                    "Owned pair argv identity")
            require(same_executable(native, spec["binary"])
                    and same_executable(helper, spec["python"]), "Owned pair executable identity")
            require(digest(f"/proc/{native}/exe") == spec["binary_sha256"],
                    "Owned running native binary hash")
            expected_homes = {b"HOME": spec["home"], b"CODEX_HOME": spec["codex_home"]}
            require(homes(native) == expected_homes and homes(helper) == expected_homes,
                    "Owned pair home identity")
            require(os.path.samefile(f"/proc/{native}/cwd", spec["cwd"])
                    and os.path.samefile(f"/proc/{helper}/cwd", spec["cwd"]), "Owned pair cwd identity")
            require(facts(native) == before_native and facts(helper) == before_helper
                    and alive(native_fd) and alive(helper_fd), "Owned pair changed during validation")
            # Exactly one signal, addressed to the retained native pidfd only.
            # Failure is surfaced; this controller never retries a signal.
            signal.pidfd_send_signal(native_fd, signal.SIGKILL)
            require(bool(select.select([native_fd], [], [], 5.0)[0]), "Owned native exit deadline")
            require(bool(select.select([helper_fd], [], [], 5.0)[0]), "Owned helper exit deadline")
            require(not Path(f"/proc/{native}").exists(), "Owned helper did not reap native")
            return {"native_pid": native, "helper_pid": helper,
                    "native_start": spec["native_start"], "helper_start": spec["helper_start"],
                    "native_ppid": helper, "helper_ppid": parent,
                    "native_argv": spec["native_argv"], "helper_argv": spec["helper_argv"],
                    "home": spec["home"], "codex_home": spec["codex_home"], "cwd": spec["cwd"],
                    "binary_sha256": spec["binary_sha256"], "helper_sha256": spec["helper_sha256"],
                    "signal": "SIGKILL", "signal_count": 1,
                    "native_pidfd_exited": True, "helper_pidfd_exited": True}
        finally:
            os.close(helper_fd)
    finally:
        os.close(native_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, type=Path)
    args = parser.parse_args()
    # Bounds apply to this owned controller only; expiry never signals a target.
    signal.alarm(12)
    data = args.spec.read_bytes()
    require(0 < len(data) <= MAX_SPEC, "Owned crash spec byte bound")
    proof = run(json.loads(data))
    encoded = json.dumps(proof, sort_keys=True).encode()
    require(len(encoded) <= MAX_SPEC, "Owned crash proof byte bound")
    sys.stdout.buffer.write(encoded + b"\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as failure:
        # Never print arbitrary process/environment bytes or Python tracebacks.
        print(f"Owned crash controller failed: {type(failure).__name__}: {failure}", file=sys.stderr)
        sys.exit(1)
