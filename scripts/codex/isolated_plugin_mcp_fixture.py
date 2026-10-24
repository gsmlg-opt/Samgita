#!/usr/bin/env python3
"""Owned stdio MCP peer and pinned isolated Codex launcher.

Only --peer handles synthetic MCP. The default mode delegates to the existing
hash-pinned isolated_plugin_fixture; no HTTP/model backend or socket is created.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import sys

sys.dont_write_bytecode = True
LAUNCHER_SHA256 = "f2ba1e6f507d2e26e58cea4498cb8b73c46f92ce636266d525af705760e97122"
MESSAGE = "owned plugin capability λ"
MAX_LINE = 65_536
MAX_JOURNAL = 1_048_576
MAX_ROWS = 128
CREDENTIAL_NAMES = ("OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_ACCESS_TOKEN",
                    "ANTHROPIC_API_KEY", "GH_TOKEN", "GITHUB_TOKEN")


def journal(root, row):
    path = root / "plugin-mcp.jsonl"
    encoded = (json.dumps({"pid": os.getpid(), **row}, ensure_ascii=False) + "\n").encode()
    assert len(encoded) <= MAX_LINE, "Owned journal row bound"
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        existing = os.read(fd, MAX_JOURNAL + 1)
        assert len(existing) + len(encoded) <= MAX_JOURNAL, "Owned journal byte bound"
        assert existing.count(b"\n") < MAX_ROWS, "Owned journal row count bound"
        assert os.write(fd, encoded) == len(encoded), "Owned journal short write"
    finally:
        os.close(fd)


def tools():
    return [{"name": name, "description": "Owned synthetic " + name,
             "inputSchema": {"type": "object",
                             "properties": {"message": {"type": "string"}},
                             "required": ["message"], "additionalProperties": False},
             "annotations": {"readOnlyHint": True, "destructiveHint": False}}
            for name in ("echo", "hidden")]


def reply(message):
    method, params = message.get("method"), message.get("params", {})
    if method == "initialize":
        assert params["protocolVersion"] == "2025-06-18", "Legacy protocol prerequisite"
        return {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                "serverInfo": {"name": "owned-plugin-peer", "version": "1"}}
    if method == "tools/list":
        return {"tools": tools()}
    if method == "resources/list":
        return {"resources": []}
    if method == "resources/templates/list":
        return {"resourceTemplates": []}
    if method == "ping":
        return {}
    if method == "tools/call":
        assert params["name"] == "echo", "Disabled tool reached owned peer"
        assert params["arguments"] == {"message": MESSAGE}, "Unexpected synthetic arguments"
        thread = params["_meta"]["threadId"]
        assert isinstance(thread, str) and thread, "Missing native thread identity"
        return {"content": [{"type": "text",
                             "text": "Synthetic plugin MCP result: " + MESSAGE}],
                "structuredContent": {"echo": MESSAGE, "association": "owned-plugin-echo-1",
                                      "threadId": thread},
                "isError": False}
    raise AssertionError("Unexpected owned MCP method")


def peer(root):
    root = root.resolve(strict=True)
    parent_namespace = (root / "parent-netns").read_text()
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace != parent_namespace, "Peer escaped private namespace"
    assert os.environ.get("HOME") == str(root / "home"), "Peer HOME ownership"
    assert not any(os.environ.get(name) for name in CREDENTIAL_NAMES), "Unexpected credential"
    journal(root, {"event": "start", "namespace": namespace, "ppid": os.getppid(),
                   "processGroup": os.getpgrp(), "credentialsPresent": False})

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        for _index in range(MAX_ROWS):
            raw = sys.stdin.buffer.readline(MAX_LINE + 1)
            if not raw:
                return
            assert len(raw) <= MAX_LINE and raw.endswith(b"\n"), "Owned MCP line bound"
            message = json.loads(raw)
            assert message.get("jsonrpc") == "2.0", "Owned JSON-RPC envelope"
            method = message.get("method")
            row = {"event": "request", "method": method, "id": message.get("id")}
            if method == "tools/call":
                params = message["params"]
                assert params.get("arguments") == {"message": MESSAGE}, "Unexpected arguments"
                assert params.get("name") in {"echo", "hidden"}, "Unexpected synthetic tool"
                row["params"] = {"name": params["name"], "arguments": params["arguments"],
                                 "_meta": {"threadId": params.get("_meta", {}).get("threadId")}}
            journal(root, row)
            if "id" not in message:
                assert method in {"notifications/initialized", "notifications/cancelled"}, \
                    "Unexpected owned MCP notification"
                continue
            response = {"jsonrpc": "2.0", "id": message["id"], "result": reply(message)}
            print(json.dumps(response, ensure_ascii=False), flush=True)
        raise AssertionError("Owned MCP request count bound")
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        journal(root, {"event": "fatal", "reason": str(error)})
        raise
    finally:
        journal(root, {"event": "exit"})


def main():
    if "--peer" in sys.argv[1:]:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("--peer", action="store_true")
        parser.add_argument("--root", required=True, type=Path)
        args = parser.parse_args()
        peer(args.root)
        return
    launcher = Path(__file__).with_name("isolated_plugin_fixture.py")
    assert hashlib.sha256(launcher.read_bytes()).hexdigest() == LAUNCHER_SHA256, \
        "Pinned isolated launcher source changed"
    from isolated_plugin_fixture import main as native_main
    native_main()


if __name__ == "__main__":
    main()
