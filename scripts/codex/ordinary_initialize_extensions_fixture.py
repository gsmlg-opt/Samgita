#!/usr/bin/env python3
"""Owned bounded MCP extension219 peer; never an app-server emulator.

No children, threads, network, file-resource access, tools or model responses.
The only writes are the explicitly owned journal/owner marker. Startup includes
an empty tools/list catalog because immutable Codex fetches it unconditionally.
"""
import sys
sys.dont_write_bytecode = True

import argparse
import base64
import json
import os
from pathlib import Path
import select
import signal
import time

MAX_FRAME = 16_384
MAX_MESSAGES = 8
MAX_JOURNAL = 131_072
MAX_EVENTS = 32
LIFETIME_SECONDS = 20
PROTOCOL = "2025-06-18"
URI = "fixture://extension-219/data"
TEXT = "Owned extension219 resource λ🙂\nDescriptor observed by the actual peer.\n"
EXTENSIONS = {
    "io.modelcontextprotocol/ui": {
        "mimeTypes": ["text/html;profile=mcp-app"],
        "ownedDescriptor": {"label": "Owned descriptor λ🙂", "revision": 1},
    }
}
CONTENTS = [
    {"uri": URI, "mimeType": "text/plain", "text": TEXT},
]


class ExtensionPeer:
    def __init__(self, journal):
        self.journal = journal
        self.events = []
        self.reason = None
        self.count = 0
        self.initialized = False
        self.seen = {}
        self.ids = set()
        self.until = time.monotonic() + LIFETIME_SECONDS
        self.owner = journal.with_suffix(journal.suffix + ".owner")
        with self.owner.open("x", encoding="utf-8") as output:
            output.write(json.dumps({"pid": os.getpid(), "parent": os.getppid()}))
        self.record("started", pid=os.getpid(), parent=os.getppid(),
                    script=str(Path(__file__).resolve()), lifetime_seconds=LIFETIME_SECONDS)

    def record(self, event, **fields):
        assert len(self.events) < MAX_EVENTS, "Owned peer journal event bound"
        self.events.append({"event": event, **fields})
        data = json.dumps({"events": self.events}, ensure_ascii=False).encode()
        assert len(data) <= MAX_JOURNAL, "Owned peer journal byte bound"
        pending = self.journal.with_suffix(self.journal.suffix + ".pending")
        pending.write_bytes(data)
        pending.replace(self.journal)

    def wire(self, direction, raw):
        assert len(raw) <= MAX_FRAME, "Owned peer JSONL frame bound"
        self.record("wire", direction=direction,
                    raw_base64=base64.b64encode(raw).decode("ascii"))

    def signal_stop(self, number, _frame):
        # Finish journaling a current small response before exiting on SIGTERM.
        self.reason = "signal:" + str(number)

    def once(self, method):
        self.seen[method] = self.seen.get(method, 0) + 1
        assert self.seen[method] == 1, "Owned peer operation count bound"

    def result(self, message):
        method = message.get("method")
        params = message.get("params") or {}
        assert isinstance(params, dict), "Owned peer parameter object"
        self.once(method)
        if method == "initialize":
            assert not self.initialized and self.count == 1
            assert params["protocolVersion"] == PROTOCOL
            # Observe original real-native MCP bytes; do not manufacture a
            # descriptor from app-server input or echo it into our response.
            assert params["capabilities"]["extensions"] == EXTENSIONS
            return {"protocolVersion": PROTOCOL,
                    "capabilities": {"resources": {}, "tools": {}},
                    "serverInfo": {"name": "owned-extension-219", "version": "1"}}
        if method == "notifications/initialized":
            assert "id" not in message and "initialize" in self.seen
            self.initialized = True
            return None
        assert self.initialized, "Owned peer initialization order"
        if method == "tools/list":
            assert not params.get("cursor"), "Owned one terminal startup catalog"
            return {"tools": []}
        if method == "resources/read":
            assert params["uri"] == URI
            return {"contents": CONTENTS}
        self.record("unexpected_method", method=method)
        raise ValueError("Unexpected owned MCP peer operation")

    def message(self, raw):
        self.count += 1
        assert self.count <= MAX_MESSAGES, "Owned peer message count bound"
        self.wire("in", raw)
        message = json.loads(raw)
        assert isinstance(message, dict) and message.get("jsonrpc") == "2.0"
        result = self.result(message)
        if result is None:
            return
        assert "id" in message
        identity = message["id"]
        assert type(identity) in (int, str), "Owned peer typed JSON-RPC identity"
        typed = (type(identity).__name__, identity)
        assert typed not in self.ids, "Owned peer unique request identity"
        self.ids.add(typed)
        response = {"jsonrpc": "2.0", "id": identity, "result": result}
        encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
        assert len(encoded) <= 4_096
        # Small bounded messages fit in the owned pipe; readiness has a deadline.
        remaining = max(self.until - time.monotonic(), 0)
        assert select.select([], [sys.stdout.fileno()], [], remaining)[1]
        assert os.write(sys.stdout.fileno(), encoded) == len(encoded)
        self.wire("out", encoded)

    def run(self):
        buffer = b""
        try:
            while self.reason is None:
                remaining = self.until - time.monotonic()
                if remaining <= 0:
                    self.reason = "deadline"
                    raise TimeoutError("Owned peer lifetime bound")
                ready, _, _ = select.select([sys.stdin.fileno()], [], [], min(remaining, 0.05))
                if not ready:
                    continue
                chunk = os.read(sys.stdin.fileno(), 4_096)
                if not chunk:
                    assert not buffer, "Owned complete final JSONL frame"
                    self.reason = "eof"
                    break
                buffer += chunk
                assert len(buffer) <= MAX_FRAME, "Owned peer pending byte bound"
                while b"\n" in buffer:
                    raw, buffer = buffer.split(b"\n", 1)
                    self.message(raw + b"\n")
                    if self.reason is not None:
                        break
        except Exception as error:
            self.record("fatal", kind=type(error).__name__)
            self.reason = self.reason or "failure"
            raise
        finally:
            self.record("closed", pid=os.getpid(), reason=self.reason,
                        messages=self.count, methods=self.seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", required=True, type=Path)
    args = parser.parse_args()
    peer = ExtensionPeer(args.journal)
    signal.signal(signal.SIGTERM, peer.signal_stop)
    signal.signal(signal.SIGINT, peer.signal_stop)
    peer.run()


if __name__ == "__main__":
    main()
