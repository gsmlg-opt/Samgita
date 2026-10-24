#!/usr/bin/env python3
"""Observe original native request-ID upgrade headers and reconnect, metadata only."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import threading

import isolated_thread_environment_fixture as shared
from isolated_environment_fixture import TOKEN


REQUEST_ID = "Owned-Request-ID-20261025"
ORIGINAL_VALIDATE = shared.validate


class Fixture(shared.Fixture):
    def __init__(self, root, namespace):
        super().__init__(root, namespace)
        self.gate.set()
        self.header_owner = threading.local()
        self.registration_seen = False

    def connection(self, downstream, identity):
        self.header_owner.identity = identity
        self.header_owner.first = True
        super().connection(downstream, identity)

    def headers(self, conn):
        original = super().headers(conn)
        if self.header_owner.first:
            self.header_owner.first = False
            headers = [line.split(b":", 1) for line in original.split(b"\r\n")[1:] if b":" in line]
            request_ids = [value.strip() for name, value in headers if name.lower() == b"x-request-id"]
            bearers = [value.strip() for name, value in headers if name.lower() == b"authorization"]
            assert request_ids == [REQUEST_ID.encode("ascii")], "native upgrade request ID mismatch"
            assert bearers == [("Bearer " + TOKEN).encode("ascii")], "native upgrade bearer mismatch"
            identity = self.header_owner.identity
            assert identity in (1, 2), "unexpected native request-ID connection"
            self.record("request_id_verified", connection=identity, request_id=REQUEST_ID)
        # Return the original bytes, including exact header casing/values, unchanged.
        return original


def validate(wire, fixture):
    method, params = wire.get("method"), wire.get("params")
    assert method in {"initialize", "initialized", "environment/add", "environment/info",
                      "environment/status", "thread/loaded/list"}
    if method == "environment/add":
        assert not fixture.registration_seen, "unexpected repeated registration"
        assert params == {"environmentId": "request-id", "execServerUrl": fixture.url,
                          "authBearerToken": TOKEN, "connectTimeoutMs": 15_000,
                          "websocketRequestId": REQUEST_ID}
        fixture.registration_seen = True
    elif method in {"environment/info", "environment/status"}:
        assert params == {"environmentId": "request-id"}
    elif method == "thread/loaded/list":
        assert params == {}
    else:
        ORIGINAL_VALIDATE(wire, fixture)


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
