#!/usr/bin/env python3
"""Owned ordinary connector metadata; native Codex owns every app-server frame.

One synchronous loopback listener supplies inert tools/list and directory data.
Only metadata discovery is supported. No model or tool execution handler exists.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import time
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 64
MAX_EVENTS = 64
MCP_PATH = "/backend-api/ps/mcp"
ALPHA = "owned-installed-alpha"
BETA = "owned-installed-beta"
GAMMA = "owned-installed-gamma"
DELTA = "owned-directory-delta"


def descriptor(connector, suffix, name=None):
    meta = {"connector_id": connector}
    if name is not None:
        meta["connector_name"] = name
    return {"name": "owned_" + suffix, "description": "Owned inert discovery descriptor " + suffix,
            "inputSchema": {"type": "object", "properties": {}}, "_meta": meta}


def catalog(generation):
    if generation == 1:
        return [descriptor(ALPHA, "alpha_lookup", "  Owned Alpha λ🙂  "),
                descriptor(ALPHA, "alpha_notes", "  Owned Alpha λ🙂  "),
                descriptor(BETA, "beta_lookup")]
    if generation == 2:
        return [descriptor(ALPHA, "alpha_lookup", "Owned Alpha refreshed β🙂"),
                descriptor(GAMMA, "gamma_lookup")]
    raise RuntimeError("ordinary installed catalog generation")


def directory():
    # Different canonical names and an extra directory-only row make the final
    # native merged projection distinguishable from runtime-only interim rows.
    return [{"id": ALPHA, "name": "Owned canonical Alpha λ🙂",
             "description": "Owned directory Alpha description β",
             "logo_url": "https://synthetic.invalid/ordinary-alpha.svg",
             "logo_url_dark": "https://synthetic.invalid/ordinary-alpha-dark.svg"},
            {"id": GAMMA, "name": "Owned canonical Gamma γ",
             "description": "Owned directory Gamma description 🙂",
             "logo_url": None, "logo_url_dark": None},
            {"id": DELTA, "name": "Owned directory Delta δ",
             "description": "Owned directory-only description λ",
             "logo_url": "https://synthetic.invalid/ordinary-delta.svg",
             "logo_url_dark": None}]


class Fixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.http_count = self.initialize_count = self.tools_count = self.directory_count = 0
        self.generation = 1
        self.journal = self.root / "ordinary-installed-apps-journal.json"
        write_json(self.root / "ordinary-installed-apps-inputs.json",
                   {"generation1": catalog(1), "generation2": catalog(2), "directory": directory()})
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def log_message(self, *_args):
                pass

            def count(self):
                owner.http_count += 1
                if owner.http_count > MAX_HTTP or len(self.path.encode()) > 4096:
                    raise RuntimeError("ordinary installed HTTP request bound")

            def reply(self, status, value=None):
                data = b"" if value is None else json.dumps(value, ensure_ascii=False).encode()
                if len(data) > MAX_BODY:
                    raise RuntimeError("ordinary installed response byte bound")
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True
                return data

            def do_GET(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    query = parse_qs(parsed.query, keep_blank_values=True, max_num_fields=8)
                    if parsed.path == MCP_PATH:
                        owner.record("mcp_get")
                        self.reply(405)
                    elif parsed.path == "/backend-api/connectors/directory/list":
                        owner.directory_count += 1
                        if query != {"external_logos": ["true"]} or owner.directory_count != 1:
                            raise RuntimeError("ordinary installed directory route/count")
                        rows = directory()
                        owner.record("directory", sequence=owner.directory_count, path=parsed.path,
                                     query=query, rows=rows)
                        data = self.reply(200, {"apps": rows, "next_token": None})
                        owner.record("directory_response_sent", sequence=owner.directory_count,
                                     raw=data.decode(), sha256=hashlib.sha256(data).hexdigest())
                    elif parsed.path == "/backend-api/wham/config/bundle":
                        self.reply(200, {})
                    elif parsed.path == "/backend-api/wham/accounts/check":
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif parsed.path == "/backend-api/wham/settings/user":
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=parsed.path)
                        self.reply(404, {})
                except Exception as error:
                    owner.record("fixture_error", stage="ordinary-installed-get", kind=type(error).__name__)
                    self.reply(500, {"error": "owned ordinary metadata failed"})

            def do_POST(self):
                parsed = urlparse(self.path)
                try:
                    self.count()
                    if parsed.path != MCP_PATH or parsed.query:
                        owner.record("unexpected_http", method="POST", path=parsed.path)
                        self.reply(404, {})
                        return
                    # Content length is ordinary bounded body framing only.
                    size = int(self.headers.get("Content-Length", "0"))
                    if not 0 < size <= 8192:
                        raise RuntimeError("ordinary installed MCP input byte bound")
                    raw = self.rfile.read(size)
                    request = json.loads(raw)
                    if request.get("jsonrpc") != "2.0":
                        raise RuntimeError("ordinary installed MCP framing")
                    method = request.get("method")
                    if method == "notifications/initialized" and "id" not in request:
                        owner.record("mcp_initialized")
                        self.reply(202)
                        return
                    if "id" not in request:
                        raise RuntimeError("ordinary installed MCP request identity")
                    if method == "initialize":
                        owner.initialize_count += 1
                        if owner.initialize_count > 3:
                            raise RuntimeError("ordinary installed MCP startup count")
                        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                                  "serverInfo": {"name": "owned-ordinary-installed-apps", "version": "1"}}
                        event = "mcp_initialize"
                        sequence = owner.initialize_count
                    elif method == "tools/list":
                        owner.tools_count += 1
                        if owner.tools_count > 4:
                            raise RuntimeError("ordinary installed discovery count")
                        result = {"tools": catalog(owner.generation)}
                        event = "tools_list"
                        sequence = owner.tools_count
                    else:
                        owner.record("unexpected_mcp", method=method)
                        self.reply(404, {})
                        return
                    owner.record(event, sequence=sequence, generation=owner.generation,
                                 request=request, raw_request=raw.decode(), result=result)
                    response = {"jsonrpc": "2.0", "id": request["id"], "result": result}
                    data = self.reply(200, response)
                    owner.record(event + "_response_sent", sequence=sequence,
                                 raw=data.decode(), sha256=hashlib.sha256(data).hexdigest())
                except Exception as error:
                    owner.record("fixture_error", stage="ordinary-installed-post", kind=type(error).__name__)
                    self.reply(500, {"error": "owned ordinary discovery failed"})

            def do_DELETE(self):
                self.count()
                parsed = urlparse(self.path)
                if parsed.path == MCP_PATH and not parsed.query:
                    owner.record("mcp_closed")
                    self.reply(200, {})
                else:
                    owner.record("unexpected_http", method="DELETE", path=parsed.path)
                    self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 0.1
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        if len(self.events) >= MAX_EVENTS:
            raise RuntimeError("ordinary installed journal event bound")
        self.events.append({"event": event, **fields})
        write_json(self.journal, {"events": self.events})

    def apply_control(self):
        path = self.root / "ordinary-installed-apps-control.json"
        if not path.exists():
            return False
        if path.stat().st_size > 4096:
            raise RuntimeError("ordinary installed control byte bound")
        raw = path.read_bytes()
        if len(raw) > 4096:
            raise RuntimeError("ordinary installed control read bound")
        control = json.loads(raw)
        if control == {"action": "generation", "generation": 2} and self.generation == 1:
            self.generation = 2
            path.unlink()
            self.record("generation_changed", generation=2)
            return False
        if control == {"action": "close"}:
            self.record("close_started")
            return True
        raise RuntimeError("ordinary installed control transition")

    def close(self):
        self.http.server_close()
        self.record("fixture_closed", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-installed-apps"])
    args = parser.parse_args()
    fixture = Fixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        deadline = time.monotonic() + 50
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("ordinary installed helper lifetime bound")
            if fixture.apply_control():
                return
            fixture.http.handle_request()
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
