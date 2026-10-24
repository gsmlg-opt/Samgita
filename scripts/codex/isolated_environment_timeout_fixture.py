#!/usr/bin/env python3
"""Owned native connect-timeout expiry and delayed successful upgrade control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import sys
import threading
import time

import isolated_thread_environment_fixture as shared
from isolated_environment_fixture import TOKEN


class Fixture(shared.Fixture):
    def __init__(self, root, namespace):
        super().__init__(root, namespace)
        self.gate.set()
        self.release_upgrade = threading.Event()
        self.header_owner = threading.local()
        self.held_at = {}
        self.hold_lock = threading.Lock()

    def connection(self, downstream, identity):
        self.header_owner.identity = identity
        self.header_owner.first = True
        super().connection(downstream, identity)

    def headers(self, conn):
        data = super().headers(conn)
        if not self.header_owner.first:
            return data
        self.header_owner.first = False
        identity = self.header_owner.identity
        assert identity in (1, 2), "unexpected owned timeout connection"
        lines = data.decode("ascii").split("\r\n")
        auth = [line for line in lines if line.lower().startswith("authorization:")]
        assert len(auth) == 1 and auth[0].lower() == ("Authorization: Bearer " + TOKEN).lower()
        started = time.monotonic_ns()
        with self.hold_lock:
            self.held_at[identity] = started
        self.record("upgrade_held", connection=identity, monotonic_ns=started)
        deadline = time.monotonic() + 4
        while not self.closed.is_set():
            readable, _, _ = select.select([conn], [], [], 0.01)
            if readable:
                extra = conn.recv(1)
                assert extra == b"", "unexpected data before owned upgrade release"
                self.record("upgrade_peer_closed", connection=identity,
                            monotonic_ns=time.monotonic_ns())
                raise EOFError
            if identity == 2 and self.release_upgrade.is_set():
                return data
            assert time.monotonic() < deadline, "owned timeout upgrade hold deadline"
        raise EOFError

    def controls(self):
        self.remember()
        seen = None
        try:
            while not self.closed.wait(0.01):
                path = self.root / "control.json"
                if not path.exists():
                    continue
                control = json.loads(path.read_text())
                if control["id"] == seen:
                    continue
                assert seen is None and set(control) == {"id", "action"}
                assert control["action"] == "release_control_upgrade"
                seen = control["id"]
                with self.hold_lock:
                    started = self.held_at[2]
                while time.monotonic_ns() - started < 1_000_000_000:
                    if self.closed.wait(0.01):
                        return
                held_ns = time.monotonic_ns() - started
                assert held_ns < 4_000_000_000, "owned control release deadline"
                self.record("upgrade_released", connection=2, held_ns=held_ns)
                self.release_upgrade.set()
                self.record("control_completed", id=seen, action=control["action"])
        except Exception as error:
            self.record("fixture_error", stage="timeout-control", error_type=type(error).__name__)


def validate(wire, fixture):
    method, params = wire.get("method"), wire.get("params")
    assert method in {"initialize", "initialized", "environment/add", "environment/info",
                      "environment/status", "thread/loaded/list"}
    if method == "environment/add":
        assert set(params) == {"environmentId", "execServerUrl", "authBearerToken", "connectTimeoutMs"}
        expected = {"timeout": 500, "control": 5000}
        identity = params["environmentId"]
        assert identity in expected and params["connectTimeoutMs"] == expected[identity]
        assert params["execServerUrl"] == fixture.url and params["authBearerToken"] == TOKEN
        # Metadata only: never retain the raw bearer or upgrade headers.
        fixture.record("registration_checked", environment_id=identity,
                       connect_timeout_ms=expected[identity], approved_destination=True)
    elif method == "environment/status":
        assert set(params) == {"environmentId"} and params["environmentId"] in {"timeout", "control"}
    elif method == "environment/info":
        assert params == {"environmentId": "control"}, "failed environment info would retry"
    elif method == "thread/loaded/list":
        assert params == {}
    else:
        ORIGINAL_VALIDATE(wire, fixture)


ORIGINAL_VALIDATE = shared.validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == shared.SHA256
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration present"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net"),
            "--parent-userns", os.readlink("/proc/self/ns/user")])
    shared.Fixture = Fixture
    shared.validate = validate
    shared.isolated(args)


if __name__ == "__main__":
    main()
