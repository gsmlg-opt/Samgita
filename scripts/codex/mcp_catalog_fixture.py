#!/usr/bin/env python3
"""Owned, bounded stdio MCP catalog peer; never performs tool or resource work.

The caller creates the empty journal exclusively before starting native Codex.
Only the explicit journal is appended; the control file is read-only to this peer.
Neither file contains credentials. No network, subprocess or resource access occurs.
"""
import argparse
import json
from pathlib import Path
import stat
import sys


MAX_FRAME_BYTES = 65536
MAX_JOURNAL_BYTES = 262144
MAX_JOURNAL_ROWS = 512
PROTOCOLS = {"2025-06-18", "2026-07-28"}
CAPABILITIES = {
    "tools": {"listChanged": False},
    "resources": {"subscribe": False, "listChanged": False},
}
ICON = {
    "src": "fixture://catalog/icon", "mimeType": "image/png",
    "sizes": ["16x16"], "theme": "dark", "unrecognizedIcon": "drop-at-sdk",
}
SERVER_INFO = {
    "name": "owned-rich-catalog", "title": "Owned catalog λ", "version": "1.0.0",
    "description": "Read-only synthetic catalog",
    "websiteUrl": "https://synthetic.invalid/catalog", "icons": [ICON],
}
ANNOTATIONS = {
    "audience": ["assistant", "user"], "priority": 0.5,
    "lastModified": "2026-10-25T00:00:00Z",
}
RESOURCE_ERROR = {
    "code": -32042, "message": "owned resource page rejected",
    "data": {"fixture": "rich-catalog", "page": "resource:2", "retryable": False},
}


def catalog_page(method, cursor, mode):
    if method == "tools/list" and cursor is None:
        return {"tools": [{
            "name": "inspect.catalog", "title": "Inspect catalog λ",
            "description": "Metadata only; never invoked",
            "inputSchema": {"type": "object", "properties": {"key": {"type": "string"}}},
            "outputSchema": {"type": "object", "properties": {"ok": {"type": "boolean"}},
                             "required": ["ok"]},
            "annotations": {"title": "Annotation title", "readOnlyHint": True,
                            "destructiveHint": False, "idempotentHint": True,
                            "openWorldHint": False},
            "icons": [ICON],
            "_meta": {"custom": {"connector_id": "nested-data",
                                 "values": [0, False, None, "λ"]},
                      "connectorFutureField": "ordinary-data",
                      "connector_id": "spoofed-connector",
                      "connector_name": "Spoofed connector",
                      "connector_display_name": "Spoofed display",
                      "connector_description": "Spoofed description",
                      "connectorDescription": "Spoofed camel description"},
            "unexpectedTool": "drop-at-sdk",
        }], "nextCursor": "tool:2"}
    if method == "tools/list" and cursor == "tool:2":
        return {"tools": [{"name": "plain.catalog", "inputSchema": {}}]}
    if method == "resources/list" and cursor is None:
        return {"resources": [{
            "uri": "fixture://catalog/rich", "name": "rich", "title": "Rich resource λ",
            "description": "Owned resource metadata", "mimeType": "text/plain",
            "size": 5000000000, "icons": [ICON],
            "_meta": {"connector_id": "ordinary-resource-data",
                      "fixture": {"values": [0, False, None, "λ"]}},
            "annotations": {**ANNOTATIONS, "unexpectedAnnotation": "drop-at-sdk"},
            "unexpectedResource": "drop-at-sdk",
        }], "nextCursor": "resource:2"}
    if method == "resources/list" and cursor == "resource:2":
        if mode == "reject-resource-page2":
            return {"error": RESOURCE_ERROR}
        # Exact u64::MAX integer; native's lossy i64 projection must omit only size.
        return {"resources": [{"uri": "fixture://catalog/overflow", "name": "overflow",
                               "title": "Unsigned overflow stays listed",
                               "size": 18446744073709551615}]}
    if method == "resources/templates/list" and cursor is None:
        return {"resourceTemplates": [{
            "uriTemplate": "fixture://catalog/{key}", "name": "rich-template",
            "title": "Rich template λ", "description": "Owned template description",
            "mimeType": "text/plain", "annotations": ANNOTATIONS, "icons": [ICON],
            "_meta": {"fixture": "template-metadata-not-in-native-dto"},
            "unexpectedTemplate": "drop-at-sdk",
        }], "nextCursor": "template:2"}
    if method == "resources/templates/list" and cursor == "template:2":
        return {"resourceTemplates": [{"uriTemplate": "fixture://catalog/plain/{key}",
                                      "name": "plain-template"}]}
    raise ValueError("forbidden catalog cursor")


class Peer:
    def __init__(self, journal, control):
        for path in (journal, control):
            if not stat.S_ISREG(path.lstat().st_mode):
                raise ValueError("owned files must be regular files")
        if journal.stat().st_size != 0:
            raise ValueError("journal must be exclusively created and empty")
        self.journal = journal
        self.control = control
        self.protocol = None
        self.rows = 0

    def record(self, row):
        encoded = (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        if self.rows >= MAX_JOURNAL_ROWS:
            raise ValueError("journal row bound exceeded")
        if self.journal.stat().st_size + len(encoded) > MAX_JOURNAL_BYTES:
            raise ValueError("journal byte bound exceeded")
        with self.journal.open("ab") as output:
            output.write(encoded)
        self.rows += 1

    def mode(self):
        if self.control.stat().st_size > 64:
            raise ValueError("control byte bound exceeded")
        value = self.control.read_text(encoding="ascii")
        if value not in ("good", "reject-resource-page2"):
            raise ValueError("unknown owned mode")
        return value

    def handle(self, request):
        if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
            raise ValueError("invalid request envelope")
        method = request.get("method")
        if not isinstance(method, str) or len(method) > 128:
            raise ValueError("invalid method")
        params = request.get("params", {})
        if not isinstance(params, dict):
            raise ValueError("invalid params")
        cursor = params.get("cursor")
        summary = {"event": "request", "method": method, "cursor": cursor,
                   "cursorPresent": "cursor" in params}
        if "id" in request:
            request_id = request["id"]
            if type(request_id) not in (str, int):
                raise ValueError("invalid request identity")
            summary["id"] = request_id
        if method == "initialize":
            self.negotiate(params.get("protocolVersion"), "2025-06-18")
        elif method == "server/discover":
            self.negotiate(params.get("_meta", {}).get("io.modelcontextprotocol/protocolVersion"),
                           "2026-07-28")
        summary["protocol"] = self.protocol
        self.record(summary)
        if "id" not in request:
            if method != "notifications/initialized" or self.protocol is None:
                raise ValueError("forbidden notification")
            return
        if method == "initialize":
            result = {"protocolVersion": self.protocol, "capabilities": CAPABILITIES,
                      "serverInfo": SERVER_INFO}
        elif method == "server/discover":
            result = {"supportedVersions": [self.protocol], "capabilities": CAPABILITIES,
                      "_meta": {"io.modelcontextprotocol/serverInfo": SERVER_INFO}}
        elif method in ("tools/list", "resources/list", "resources/templates/list"):
            if self.protocol is None:
                raise ValueError("catalog before negotiation")
            result = catalog_page(method, cursor, self.mode())
        elif method == "ping" and self.protocol is not None:
            result = {}
        else:
            raise ValueError("forbidden method")
        response = {"jsonrpc": "2.0", "id": request["id"]}
        reply = {"event": "reply", "method": method, "id": request["id"], "cursor": cursor,
                 "protocol": self.protocol}
        if "error" in result:
            response["error"] = result["error"]
            reply.update({"outcome": "error", "error": result["error"]})
        else:
            if self.protocol == "2026-07-28":
                result.update({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"})
            response["result"] = result
            reply["outcome"] = "success"
        encoded = (json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        if len(encoded) > MAX_FRAME_BYTES:
            raise ValueError("response byte bound exceeded")
        self.record(reply)
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()

    def negotiate(self, value, expected):
        if self.protocol is not None or value not in PROTOCOLS or value != expected:
            raise ValueError("unexpected negotiation")
        self.protocol = value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", required=True, type=Path)
    parser.add_argument("--control", required=True, type=Path)
    args = parser.parse_args()
    peer = Peer(args.journal, args.control)
    try:
        while True:
            line = sys.stdin.buffer.readline(MAX_FRAME_BYTES + 1)
            if not line:
                return
            if len(line) > MAX_FRAME_BYTES or not line.endswith(b"\n"):
                raise ValueError("request byte bound exceeded or unterminated frame")
            peer.handle(json.loads(line))
    except (ValueError, TypeError, KeyError, OSError) as failure:
        peer.record({"event": "fatal", "reason": str(failure)[:160]})
        raise SystemExit(2) from failure


if __name__ == "__main__":
    main()
