#!/usr/bin/env python3
"""Owned stdio catalog dependency; emits MCP replies, never app-server messages."""
import argparse
import json
import os
from pathlib import Path
import stat
import sys


MAX_FRAME_BYTES = 65536
MAX_JOURNAL_BYTES = 131072
MAX_JOURNAL_ROWS = 128
RESULTS = {
    "initialize": {
        "protocolVersion": "2025-06-18",
        "capabilities": {"tools": {}, "resources": {}},
        "serverInfo": {"name": "owned-status-detail", "version": "1.0.0"},
    },
    "tools/list": {"tools": []},
    "resources/list": {"resources": [{
        "uri": "fixture://status-detail/resource", "name": "owned-resource",
        "title": "Resource λ", "description": "Fixed catalog resource",
        "mimeType": "text/plain", "size": 37,
    }]},
    "resources/templates/list": {"resourceTemplates": [{
        "uriTemplate": "fixture://status-detail/{key}", "name": "owned-template",
        "title": "Template λ", "description": "Fixed catalog template",
        "mimeType": "text/plain",
    }]},
}


class Peer:
    def __init__(self, journal):
        if not stat.S_ISREG(journal.lstat().st_mode):
            raise ValueError("Expected precreated journal")
        self.journal = journal
        self.initialized = False
        self.notified = False
        self.record({"event": "started"})

    def record(self, row):
        row = {**row, "pid": os.getpid()}
        encoded = (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        if len(encoded) > 4096:
            raise ValueError("Journal row bound exceeded")
        with self.journal.open("rb") as source:
            existing = source.read(MAX_JOURNAL_BYTES + 1)
        if len(existing) + len(encoded) > MAX_JOURNAL_BYTES:
            raise ValueError("Journal byte bound exceeded")
        if existing.count(b"\n") >= MAX_JOURNAL_ROWS:
            raise ValueError("Journal row count exceeded")
        with self.journal.open("ab", buffering=0) as output:
            if output.write(encoded) != len(encoded):
                raise OSError("Incomplete journal write")

    def handle(self, request):
        if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
            raise ValueError("Expected MCP envelope")
        method = request.get("method")
        if method == "notifications/initialized":
            if "id" in request or not self.initialized or self.notified:
                raise ValueError("Unexpected initialized notification")
            self.notified = True
            self.record({"event": "notification", "method": method})
            return
        if method not in RESULTS or type(request.get("id")) not in (int, str):
            raise ValueError("Unexpected catalog request")
        params = request.get("params", {})
        if not isinstance(params, dict):
            raise ValueError("Expected params object")
        if method == "initialize":
            if self.initialized or params.get("protocolVersion") != "2025-06-18":
                raise ValueError("Unexpected initialization")
            self.initialized = True
        elif not self.initialized or not self.notified or params.get("cursor") is not None:
            raise ValueError("Unexpected catalog lifecycle or cursor")
        self.record({"event": "request", "request": request})
        reply = {"jsonrpc": "2.0", "id": request["id"], "result": RESULTS[method]}
        encoded = (json.dumps(reply, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        if len(encoded) > MAX_FRAME_BYTES:
            raise ValueError("Reply frame bound exceeded")
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()
        self.record({"event": "reply", "method": method, "reply": reply})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", type=Path, required=True)
    peer = Peer(parser.parse_args().journal)
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
