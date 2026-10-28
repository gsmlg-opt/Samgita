#!/usr/bin/env python3
"""Fixed ordinary catalog metadata and empty MCP discovery for stock Codex.

One bounded synchronous backend process. No model response, tool invocation,
app-server emulator, mutation or execution endpoint is implemented.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
from urllib.parse import parse_qs, urlparse

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import MAX_BODY, MAX_HTTP

DIRECTORY = "/backend-api/connectors/directory/list"
MCP_PATH = "/backend-api/ps/mcp"
TOKEN = "owned catalog β"


def apps():
    return [
        {"id": "catalog-alpha", "name": "Owned Catalog Alpha λ",
         "description": "Ordinary catalog Alpha metadata",
         "logo_url": "https://synthetic.invalid/catalog-alpha/light.svg",
         "logo_url_dark": "https://synthetic.invalid/catalog-alpha/dark.svg",
         "icon_assets": {"128_square": "https://synthetic.invalid/catalog-alpha/128.svg",
                         "label-λ": "opaque alpha asset β"},
         "icon_dark_assets": {"64_square": "https://synthetic.invalid/catalog-alpha/dark-64.svg"},
         "distribution_channel": "ORDINARY_CATALOG_METADATA",
         "labels": {"channel": "Owned display label", "λ": "β🙂"},
         "branding": {"category": "Owned branding category λ", "developer": "Owned branding developer β",
                      "website": "https://synthetic.invalid/catalog-alpha/site",
                      "privacyPolicy": "https://synthetic.invalid/catalog-alpha/privacy",
                      "termsOfService": "https://synthetic.invalid/catalog-alpha/terms",
                      "isDiscoverableApp": False},
         "app_metadata": {
             "categories": ["Owned category λ", "Other β", "Owned category λ"],
             "subCategories": ["subcategory-two", "subcategory-one"],
             "seoDescription": "Owned search description λ🙂",
             "screenshots": [
                 {"url": "https://synthetic.invalid/catalog-alpha/screenshot.png",
                  "file_id": "owned-screenshot-alpha", "user_prompt": "Show ordinary Alpha λ🙂"},
                 {"url": None, "fileId": None, "userPrompt": "Screenshot with no link β"}],
             "developer": "Owned metadata developer γ", "version": "1.2.3-λ",
             "versionId": "owned-version-alpha", "versionNotes": "Owned version notes β🙂",
             "review": None, "firstPartyRequiresInstall": None, "showInComposerWhenUnlinked": None}},
        {"id": "catalog-beta", "name": "Owned Catalog Beta β",
         "description": "Ordinary catalog Beta metadata", "app_metadata": None,
         "branding": None, "labels": None, "logo_url": None, "logo_url_dark": None,
         "icon_assets": None, "icon_dark_assets": None, "distribution_channel": None},
        {"id": "catalog-gamma", "name": "Owned Catalog Gamma γ",
         "description": "Ordinary catalog Gamma metadata", "app_metadata": {},
         "branding": {"isDiscoverableApp": False}, "labels": {}, "logo_url": "",
         "logo_url_dark": "", "icon_assets": {}, "icon_dark_assets": {},
         "distribution_channel": ""},
    ]


class CatalogFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-catalog-metadata-journal.json"
        self.http_count = 0
        self.directory_count = 0
        self.mcp_count = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None):
                data = b"" if value is None else json.dumps(value).encode()
                assert len(data) <= MAX_BODY, "Owned catalog reply bound"
                self.send_response(status)
                if value is not None:
                    self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def count(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"

            def do_GET(self):
                self.count()
                parsed = urlparse(self.path)
                path = parsed.path
                try:
                    if path == DIRECTORY:
                        query = parse_qs(parsed.query, keep_blank_values=True)
                        owner.directory_count += 1
                        assert owner.directory_count <= 4, "Owned directory-read bound"
                        owner.record("directory", sequence=owner.directory_count, path=path, query=query)
                        records = apps()
                        if query == {"external_logos": ["true"]}:
                            self.reply(200, {"apps": [records[1], records[0]], "next_token": TOKEN})
                        elif query == {"token": [TOKEN], "external_logos": ["true"]}:
                            self.reply(200, {"apps": [records[2]], "next_token": None})
                        else:
                            raise AssertionError("Unexpected ordinary directory query")
                    elif path == MCP_PATH:
                        self.reply(405)
                    elif path == "/backend-api/wham/config/bundle":
                        self.reply(200, {})
                    elif path == "/backend-api/wham/accounts/check":
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif path == "/backend-api/wham/settings/user":
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=path)
                        self.reply(404, {})
                except Exception:
                    owner.record("fatal", stage="ordinary-catalog-get")
                    self.reply(500, {"error": "owned catalog fixture failed"})

            def do_POST(self):
                self.count()
                path = urlparse(self.path).path
                if path != MCP_PATH:
                    owner.record("unexpected_http", method="POST", path=path)
                    self.reply(404, {})
                    return
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 65_536, "Owned MCP discovery input bound"
                    wire = json.loads(self.rfile.read(size))
                    method = wire.get("method")
                    owner.mcp_count += 1
                    assert owner.mcp_count <= 32, "Owned MCP discovery count bound"
                    owner.record("mcp", method=method)
                    if method == "notifications/initialized":
                        self.reply(202)
                        return
                    if method == "initialize":
                        result = {"protocolVersion": wire["params"]["protocolVersion"],
                                  "capabilities": {"tools": {}},
                                  "serverInfo": {"name": "owned-empty-catalog-discovery", "version": "1"}}
                    elif method == "tools/list":
                        result = {"tools": []}
                    elif method == "ping":
                        result = {}
                    else:
                        raise AssertionError("Unexpected ordinary discovery method")
                    self.reply(200, {"jsonrpc": "2.0", "id": wire["id"], "result": result})
                except Exception:
                    owner.record("fatal", stage="ordinary-catalog-discovery")
                    self.reply(500, {"error": "owned discovery fixture failed"})

            def do_DELETE(self):
                self.count()
                path = urlparse(self.path).path
                if path == MCP_PATH:
                    owner.record("mcp_closed")
                    self.reply(204)
                else:
                    owner.record("unexpected_http", method="DELETE", path=path)
                    self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-catalog-metadata"])
    args = parser.parse_args()
    fixture = CatalogFixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}"}), flush=True)
        fixture.http.serve_forever(poll_interval=0.1)
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
