#!/usr/bin/env python3
"""Owned model/MCP dependencies; stock native Codex emits app-server frames.

The elicitation URL is a loopback HTTP trap. It performs no authentication,
redirect, tool execution, browser launch, or external network operation.
"""
import argparse
import json
from pathlib import Path
import sys
from urllib.parse import urlparse

from model_fixture import ModelFixture
from server_interaction_fixture import InteractionFixture


META = {"fixture/request": {"kind": "url-decision"}}
MESSAGE = "Record a synthetic URL decision without opening it"
ELICITATION_ID = "owned-synthetic-url"


class UrlFixture(InteractionFixture):
    def __init__(self, modern, workspace, requests_file, codex_home):
        super().__init__("mcp", workspace, requests_file)
        self.modern = modern
        self.trap_journal = Path(codex_home, "url-trap.json")
        self.trap_journal.write_text("[]")
        fixture = self
        base_handler = self.server.RequestHandlerClass

        class Handler(base_handler):
            def trap(self):
                if not self.path.startswith("/url-trap/"):
                    return False
                with fixture.lock:
                    requests = json.loads(fixture.trap_journal.read_text())
                    requests.append({"method": self.command, "path": self.path})
                    temporary = fixture.trap_journal.with_suffix(".partial")
                    temporary.write_text(json.dumps(requests))
                    temporary.replace(fixture.trap_journal)
                self.send_response(418)
                self.end_headers()
                return True

            def do_GET(self):
                if not self.trap():
                    super().do_GET()

            def do_POST(self):
                if not self.trap():
                    super().do_POST()

            def do_HEAD(self):
                if not self.trap():
                    self.send_error(404)

        self.server.RequestHandlerClass = Handler

    def config(self, codex_home):
        ModelFixture.config(self, codex_home)
        url = self.url + "/url-trap/" + ELICITATION_ID
        args = [str(Path(__file__).resolve()), "--mcp", "--journal",
                str(Path(codex_home, "mcp-url.jsonl")), "--url", url]
        if self.modern:
            args.append("--modern")
        body = ("\n[features]\nshell_snapshot = false\nauth_elicitation = true\n"
                f"mcp_2026_07_28 = {str(self.modern).lower()}\n"
                "[mcp_servers.fixture]\ncommand = " + json.dumps(sys.executable)
                + "\nargs = " + json.dumps(args)
                + "\nstartup_timeout_sec = 10\ntool_timeout_sec = 10\n")
        if self.modern:
            body += 'env = { CODEX_MCP_PROTOCOL_VERSION = "2026-07-28" }\n'
        with Path(codex_home, "config.toml").open("a") as target:
            target.write(body)


def mcp_server(journal, modern, url):
    parsed = urlparse(url)
    assert parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
    assert parsed.path == "/url-trap/" + ELICITATION_ID
    protocol = "2026-07-28" if modern else "2025-06-18"
    pending = None

    def record(entry):
        with Path(journal).open("a", encoding="utf-8") as target:
            target.write(json.dumps(entry) + "\n")

    def send(message):
        message = {"jsonrpc": "2.0", **message}
        record({"direction": "out", "message": message})
        print(json.dumps(message), flush=True)

    def result(identity, value):
        if modern:
            value = {**value, "resultType": "complete"}
        send({"id": identity, "result": value})

    for line in sys.stdin:
        message = json.loads(line)
        record({"direction": "in", "message": message})
        method = message.get("method")
        identity = message.get("id")
        if method == "initialize":
            assert not modern
            assert message["params"]["protocolVersion"] == protocol
            result(identity, {"protocolVersion": protocol, "capabilities": {"tools": {}},
                              "serverInfo": {"name": "synthetic-url", "version": "1"}})
        elif method == "server/discover":
            assert modern
            assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == protocol
            result(identity, {"supportedVersions": [protocol], "capabilities": {"tools": {}},
                              "_meta": {"io.modelcontextprotocol/serverInfo": {
                                  "name": "synthetic-url", "version": "1"}},
                              "ttlMs": 0, "cacheScope": "private"})
        elif method == "tools/list":
            result(identity, {"tools": [{
                "name": "confirm", "description": "Record a synthetic URL decision only",
                "inputSchema": {"type": "object", "properties": {}},
                "annotations": {"readOnlyHint": True, "destructiveHint": False},
            }]})
        elif method == "tools/call":
            assert pending is None
            assert message["params"]["name"] == "confirm"
            pending = identity
            send({"id": "synthetic-url-request", "method": "elicitation/create", "params": {
                "mode": "url", "message": MESSAGE, "_meta": META,
                "url": url, "elicitationId": ELICITATION_ID,
            }})
        elif identity == "synthetic-url-request" and pending is not None:
            record({"decision_observed": message.get("result", {}).get("action")})
            result(pending, {"content": [{"type": "text", "text": json.dumps(message)}],
                             "isError": False})
            pending = None
        elif method == "ping":
            result(identity, {})
        elif identity is not None:
            send({"id": identity, "error": {"code": -32601,
                                              "message": "Synthetic method absent"}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--modern", action="store_true")
    parser.add_argument("--journal")
    parser.add_argument("--url")
    parser.add_argument("--codex-home")
    parser.add_argument("--workspace")
    parser.add_argument("--requests-file")
    parser.add_argument("--scenario")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.journal, args.modern, args.url)
        return
    fixture = UrlFixture(args.scenario == "modern", args.workspace,
                         args.requests_file, args.codex_home).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
