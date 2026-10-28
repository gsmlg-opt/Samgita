#!/usr/bin/env python3
"""Owned inert stdio MCP catalog. Native Codex owns all app-server output."""
import argparse
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
MAX_FRAME = 65536
MAX_ROWS = 16
MAX_BYTES = 131072
TOOL = {"name": "owned_lookup", "description": "Owned cached descriptor λ🙂",
        "inputSchema": {"type": "object", "properties": {"key": {"type": "string"}}}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-dir", type=Path, required=True)
    args = parser.parse_args()
    slot = None
    for ordinal in (1, 2):
        try:
            slot = args.journal_dir / ("launch-" + str(ordinal))
            with slot.open("xb") as marker:
                marker.write(str(os.getpid()).encode())
            break
        except FileExistsError:
            slot = None
    if slot is None:
        raise SystemExit("Owned ordinary MCP total launch bound")
    journal = args.journal_dir / ("peer-" + str(os.getpid()) + ".jsonl")
    with journal.open("xb"):
        pass
    rows = 0
    counts = {"initialize": 0, "notifications/initialized": 0, "tools/list": 0}

    def record(value):
        nonlocal rows
        encoded = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        if rows >= MAX_ROWS or len(encoded) > MAX_FRAME or journal.stat().st_size + len(encoded) > MAX_BYTES:
            raise ValueError("Owned ordinary MCP journal bound")
        with journal.open("ab", buffering=0) as stream:
            if stream.write(encoded) != len(encoded):
                raise OSError("Owned ordinary MCP incomplete journal write")
        rows += 1

    record({"event": "started", "pid": os.getpid()})
    try:
        while True:
            raw = sys.stdin.buffer.readline(MAX_FRAME + 1)
            if not raw:
                record({"event": "eof"})
                return
            if len(raw) > MAX_FRAME or not raw.endswith(b"\n"):
                raise ValueError("Owned ordinary MCP frame bound")
            request = json.loads(raw)
            method = request.get("method")
            if request.get("jsonrpc") != "2.0" or method not in counts:
                raise ValueError("Owned ordinary MCP unexpected method")
            counts[method] += 1
            if counts[method] != 1:
                raise ValueError("Owned ordinary MCP duplicate discovery")
            if method == "notifications/initialized":
                if "id" in request or counts["initialize"] != 1 or counts["tools/list"] != 0:
                    raise ValueError("Owned ordinary MCP initialization order")
                record({"event": "notification", "method": method})
                continue
            if type(request.get("id")) not in (int, str):
                raise ValueError("Owned ordinary MCP request identity")
            if method == "initialize":
                if counts["notifications/initialized"] or counts["tools/list"]:
                    raise ValueError("Owned ordinary MCP startup order")
                result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                          "serverInfo": {"name": "owned-ordinary-cached-peer", "version": "1"}}
            else:
                if counts["notifications/initialized"] != 1:
                    raise ValueError("Owned ordinary MCP catalog before initialized")
                result = {"tools": [TOOL]}
            record({"event": "request", "method": method, "request": request,
                    "raw": raw.decode()})
            wire = {"jsonrpc": "2.0", "id": request["id"], "result": result}
            encoded = (json.dumps(wire, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
            if len(encoded) > MAX_FRAME:
                raise ValueError("Owned ordinary MCP reply bound")
            sys.stdout.buffer.write(encoded)
            sys.stdout.buffer.flush()
            record({"event": "reply", "method": method, "raw": encoded.decode()})
    except (ValueError, TypeError, KeyError, OSError) as error:
        record({"event": "fatal", "kind": type(error).__name__})
        raise SystemExit(2) from error


if __name__ == "__main__":
    main()
