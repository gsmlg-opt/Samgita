#!/usr/bin/env python3
"""Disposable stdio MCP peer for immutable Codex direct-operation tests.

This process performs no network, filesystem resource access, or execution.
Its only file write is the explicitly supplied synthetic request journal.
"""
import argparse
import base64
import json
from pathlib import Path
import sys


def handle(message, protocol):
    method = message.get("method")
    params = message.get("params", {})
    if method == "server/discover":
        return {"supportedVersions": [protocol], "capabilities": {"tools": {}, "resources": {}},
                "_meta": {"io.modelcontextprotocol/serverInfo": {
                    "name": "synthetic-direct", "version": "1"}},
                "ttlMs": 0, "cacheScope": "private"}
    if method == "initialize":
        return {"protocolVersion": protocol, "capabilities": {"tools": {}, "resources": {}},
                "serverInfo": {"name": "synthetic-direct", "version": "1"}}
    if method == "tools/list":
        return {"tools": [{"name": "echo", "description": "Synthetic echo only",
                           "inputSchema": {"type": "object", "properties": {}},
                           "annotations": {"readOnlyHint": True, "destructiveHint": False}}]}
    if method == "resources/list":
        return {"resources": [{"uri": "fixture://contents", "name": "Synthetic resource",
                               "mimeType": "text/plain"}]}
    if method == "resources/templates/list":
        return {"resourceTemplates": []}
    if method == "tools/call":
        arguments = params.get("arguments")
        if params.get("name") != "echo":
            return error(-32601, "synthetic tool absent", {"tool": params.get("name")})
        if (arguments or {}).get("protocolError"):
            return operation_error(-32043, "synthetic tool failure", protocol)
        return {"content": [{"type": "text", "text": "Synthetic direct MCP result\n",
                             "_meta": {"fixture": "content-preserved"}}],
                "structuredContent": {"arguments": arguments,
                                      "threadId": params.get("_meta", {}).get("threadId")},
                "isError": bool((arguments or {}).get("toolError")),
                "_meta": {"fixture": {"preserved": True}}}
    if method == "resources/read":
        uri = params.get("uri")
        if uri == "fixture://error":
            return operation_error(-32042, "synthetic resource failure", protocol)
        if uri == "fixture://normalization-bundle":
            # Fixed input intentionally differs from the native projection oracle.
            return {"contents": [
                {"uri": "fixture://bundle/repeated", "text": "Owned text wins\nλ",
                 "blob": "RElTQ0FSRA==", "mimeType": "", "_meta": {},
                 "unexpected": "discard-me"},
                {"uri": "fixture://bundle/repeated", "text": None, "blob": "not_base64!",
                 "mimeType": None,
                 "_meta": {"fixture": {"values": [0, False, None, "λ"], "empty": {}}},
                 "unexpected": "discard-me-too"},
                {"uri": "fixture://bundle/empty-text", "text": "", "mimeType": "text/plain"},
                {"uri": "fixture://bundle/empty-blob", "blob": "",
                 "mimeType": "application/octet-stream"},
            ], "_meta": {"fixture": "resource-envelope-only"},
                "ttlMs": 0, "cacheScope": "private"}
        if uri == "fixture://bundle-denied":
            return error(-32042, "owned bundle denied", {
                "fixture": "normalization-bundle", "partial": False,
                "nested": {"values": [0, False, None, "λ"]},
            })
        if uri == "fixture://empty-bundle":
            return {"contents": []}
        if uri == "fixture://optional-contents":
            blob = base64.b64encode(bytes([0, 1, 127, 128, 255])).decode("ascii")
            return {"contents": [
                {"uri": "fixture://optional/text-omitted", "text": "Owned omitted text\nλ"},
                {"uri": "fixture://optional/text-null", "text": "Owned null text\nλ",
                 "mimeType": None, "_meta": None},
                {"uri": "fixture://optional/blob-omitted", "blob": blob},
                {"uri": "fixture://optional/blob-null", "blob": blob,
                 "mimeType": None, "_meta": None},
            ]}
        if uri != "fixture://contents":
            return error(-32044, "synthetic resource absent", {"uri": uri})
        return {"contents": [
            {"uri": uri, "mimeType": "text/plain", "text": "Synthetic resource text\nλ",
             "_meta": {"fixture": {"kind": "text"}}},
            {"uri": uri, "mimeType": "application/octet-stream",
             "blob": base64.b64encode(bytes([0, 1, 127, 128, 255])).decode("ascii"),
             "_meta": {"fixture": {"kind": "blob"}}},
        ]}
    if method == "ping":
        return {}
    return error(-32601, "synthetic method absent", {"method": method})


def error(code, message, data):
    return {"error": {"code": code, "message": message, "data": data}}


def operation_error(code, message, protocol):
    return error(code, message, {"protocolVersion": protocol, "nested": {"values": [1, None]},
                                 "_meta": {"fixture": "error-preserved"}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", required=True)
    args = parser.parse_args()
    protocol = None
    for line in sys.stdin:
        message = json.loads(line)
        with Path(args.journal).open("a", encoding="utf-8") as journal:
            journal.write(json.dumps(message, ensure_ascii=False) + "\n")
        if "id" not in message:
            continue
        if message.get("method") == "initialize":
            protocol = message["params"]["protocolVersion"]
        elif message.get("method") == "server/discover":
            protocol = message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"]
            assert protocol == "2026-07-28"
        result = handle(message, protocol)
        if protocol == "2026-07-28" and "error" not in result:
            result["resultType"] = "complete"
        response = {"jsonrpc": "2.0", "id": message["id"]}
        response.update(result if "error" in result else {"result": result})
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
