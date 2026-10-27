#!/usr/bin/env python3
"""Owned stdio MCP startup dependency; never emits app-server messages or calls tools."""
import argparse
import json
import os
from pathlib import Path
import stat
import sys
import time


MAX_FRAME_BYTES = 65536
MAX_JOURNAL_BYTES = 65536
MAX_JOURNAL_ROWS = 64
RELEASE_WAIT_SECONDS = 8


class Peer:
    def __init__(self, journal, release, name):
        if not stat.S_ISREG(journal.lstat().st_mode) or journal.stat().st_size != 0:
            raise ValueError("Expected exclusively created empty journal")
        if release.exists():
            raise ValueError("Release must not exist before startup")
        self.journal = journal
        self.release = release
        self.name = name
        self.rows = 0
        self.initialized = False
        self.notified = False
        self.record({"event": "started", "pid": os.getpid(), "parentPid": os.getppid(),
                     "processGroup": os.getpgrp(), "name": name})

    def record(self, row):
        encoded = (json.dumps(row, separators=(",", ":")) + "\n").encode()
        if self.rows >= MAX_JOURNAL_ROWS or len(encoded) > 4096:
            raise ValueError("Journal row bound exceeded")
        if self.journal.stat().st_size + len(encoded) > MAX_JOURNAL_BYTES:
            raise ValueError("Journal byte bound exceeded")
        with self.journal.open("ab", buffering=0) as output:
            if output.write(encoded) != len(encoded):
                raise OSError("Incomplete journal write")
        self.rows += 1

    def handle(self, request):
        if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
            raise ValueError("Expected MCP request envelope")
        method = request.get("method")
        if method not in {"initialize", "notifications/initialized", "tools/list", "ping"}:
            raise ValueError("Unexpected dependency method")
        params = request.get("params", {})
        if not isinstance(params, dict):
            raise ValueError("Expected MCP params object")
        identity = request.get("id")
        if method == "notifications/initialized":
            if "id" in request or not self.initialized or self.notified:
                raise ValueError("Unexpected initialized notification")
            self.notified = True
            self.record({"event": "notification", "method": method})
            return
        if type(identity) not in (str, int):
            raise ValueError("Expected request identity")
        self.record({"event": "request", "method": method, "id": identity})
        if method == "initialize":
            if self.initialized or params.get("protocolVersion") != "2025-06-18":
                raise ValueError("Unexpected initialize negotiation")
            deadline = time.monotonic() + RELEASE_WAIT_SECONDS
            while not self.release.exists():
                if time.monotonic() >= deadline:
                    raise ValueError("Owned initialize release deadline exceeded")
                time.sleep(0.01)
            if not stat.S_ISREG(self.release.lstat().st_mode):
                raise ValueError("Expected regular release file")
            if self.release.stat().st_size != len(b"release\n"):
                raise ValueError("Unexpected release size")
            if self.release.read_bytes() != b"release\n":
                raise ValueError("Unexpected release marker")
            self.record({"event": "released", "method": method, "id": identity})
            result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                      "serverInfo": {"name": self.name, "version": "1.0.0"}}
            self.initialized = True
        elif method == "tools/list":
            if not self.initialized or not self.notified:
                raise ValueError("Catalog requested before initialization")
            result = {"tools": []}
        else:
            if not self.initialized:
                raise ValueError("Ping before initialization")
            result = {}
        encoded = (json.dumps({"jsonrpc": "2.0", "id": identity, "result": result},
                              separators=(",", ":")) + "\n").encode()
        if len(encoded) > MAX_FRAME_BYTES:
            raise ValueError("Reply frame bound exceeded")
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()
        self.record({"event": "reply", "method": method, "id": identity})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    peer = Peer(args.journal, args.release, args.name)
    try:
        while True:
            line = sys.stdin.buffer.readline(MAX_FRAME_BYTES + 1)
            if not line:
                peer.record({"event": "eof"})
                return
            if len(line) > MAX_FRAME_BYTES or not line.endswith(b"\n"):
                raise ValueError("Request frame bound exceeded")
            peer.handle(json.loads(line))
    except (ValueError, TypeError, KeyError, OSError) as failure:
        peer.record({"event": "fatal", "reason": str(failure)[:160]})
        raise SystemExit(2) from failure


if __name__ == "__main__":
    main()
