#!/usr/bin/env python3
"""Ordinary remote plugin descriptive metadata for stock Codex.

One bounded synchronous backend process; no model, MCP, tool or mutation handler.
Only inert runtime setup and journal/cleanup are reused from the reviewed helper.
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

PREFIX = "/backend-api/ps/plugins/"
IDS = ["plugins~Plugin_metadata_alpha", "plugins~Plugin_metadata_beta",
       "plugins~Plugin_metadata_empty"]
EMPTY_PAGE = {"plugins": [], "pagination": {"next_page_token": None}}
STARTUP = {
    "featured": ("/backend-api/plugins/featured", {"platform": ["codex"]}, []),
    "suggested": (PREFIX + "suggested/codex", {"scope": ["GLOBAL"]},
                  {"enabled": False, "plugins": []}),
    "catalog": (PREFIX + "list", {"scope": ["GLOBAL"], "limit": ["200"]}, EMPTY_PAGE),
    "installed_cache": (PREFIX + "installed", {"limit": ["200"]}, EMPTY_PAGE),
    "installed_bundles": (PREFIX + "installed",
                          {"limit": ["200"], "includeDownloadUrls": ["true"]}, EMPTY_PAGE),
}


def detail(plugin_id):
    release = {
        "version": "1.0.0", "display_name": "Owned template metadata",
        "description": "Ordinary descriptive plugin metadata only λ🙂", "interface": {},
        "skills": [{"name": "metadata-notes", "description": "Owned remote notes λ🙂"}],
    }
    if plugin_id == IDS[0]:
        release["app_templates"] = [
            {"template_id": "template-alpha", "name": "Alpha template λ🙂",
             "description": "Alpha descriptive metadata β", "category": "Owned category λ",
             "canonical_connector_id": "descriptive-canonical-alpha",
             "logo_url": "https://synthetic.invalid/template-alpha/light.svg",
             "logo_url_dark": "https://synthetic.invalid/template-alpha/dark.svg",
             "materialized_app_ids": ["descriptive-app-beta", "descriptive-app-alpha",
                                      "descriptive-app-beta"], "reason": None},
            {"template_id": "template-minimal", "name": "Minimal template β"},
            {"template_id": "template-alpha", "name": "Duplicate template name γ",
             "description": "Duplicate row must be preserved", "category": None,
             "canonical_connector_id": None, "logo_url": None, "logo_url_dark": None,
             "materialized_app_ids": ["descriptive-app-duplicate"], "reason": None},
        ]
    elif plugin_id == IDS[1]:
        release["app_templates"] = [
            {"template_id": "template-beta", "name": "Beta explicit nulls δ",
             "description": None, "category": None, "canonical_connector_id": None,
             "logo_url": None, "logo_url_dark": None, "materialized_app_ids": [],
             "reason": None},
        ]
    elif plugin_id == IDS[2]:
        release["skills"] = []
    else:
        raise AssertionError("Unknown ordinary metadata ID")
    # Fixed required backend literals are inert setup. Their behavior and the
    # native summary are neither varied nor inspected by this case.
    return {"id": plugin_id, "name": "owned-template-metadata", "scope": "GLOBAL",
            "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
            "release": release}


class TemplateFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-plugin-template-journal.json"
        self.http_count = 0
        self.detail_count = 0
        self.installed_count = 0
        self.startup_counts = {kind: 0 for kind in STARTUP}
        self.startup_generation = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = json.dumps(value).encode()
                assert len(data) <= MAX_BODY, "Owned template reply bound"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def do_GET(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                parsed = urlparse(self.path)
                path = parsed.path
                query = parse_qs(parsed.query, keep_blank_values=True)
                try:
                    startup = next((kind for kind, (route, params, _reply) in STARTUP.items()
                                    if path == route and query == params), None)
                    if startup:
                        self.reply(200, STARTUP[startup][2])
                        owner.startup_served(startup, path, query)
                    elif path == "/backend-api/wham/config/bundle":
                        self.reply(200, {})
                    elif path == "/backend-api/wham/accounts/check":
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif path == "/backend-api/wham/settings/user":
                        self.reply(200, {"commit_attribution_enabled": False})
                    elif path == PREFIX + "installed" and query == {"scope": ["GLOBAL"]}:
                        owner.installed_count += 1
                        assert owner.installed_count <= 6, "Owned installed-read bound"
                        owner.record("installed", sequence=owner.installed_count,
                                     path=path, query=query)
                        self.reply(200, {"plugins": [], "pagination": {"next_page_token": None}})
                    elif path in [PREFIX + value for value in IDS]:
                        owner.detail_count += 1
                        assert owner.detail_count <= 6, "Owned detail-read bound"
                        owner.record("detail", sequence=owner.detail_count, path=path, query=query)
                        self.reply(200, detail(path[len(PREFIX):]))
                    else:
                        owner.record("unexpected_http", method="GET", path=path)
                        self.reply(404, {})
                except Exception:
                    owner.record("fatal", stage="ordinary-template-handler")
                    self.reply(500, {"error": "owned template fixture failed"})

            def do_POST(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                owner.record("unexpected_http", method="POST", path=urlparse(self.path).path)
                self.reply(404, {})

            def do_DELETE(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned HTTP count bound"
                owner.record("unexpected_http", method="DELETE", path=urlparse(self.path).path)
                self.reply(404, {})

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def startup_served(self, kind, path, query):
        self.startup_counts[kind] += 1
        assert self.startup_counts[kind] <= 2, "Owned startup-read count bound"
        self.record("startup", kind=kind, sequence=self.startup_counts[kind],
                    path=path, query=query)
        generation = self.startup_generation + 1
        if all(count >= generation for count in self.startup_counts.values()):
            self.startup_generation = generation
            marker = {"event": "startup_ready", "generation": generation}
            self.record("startup_ready", generation=generation)
            print(json.dumps(marker), flush=True)

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        original = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert original.count(marker) == 1, "Reviewed ordinary setup feature block"
        path.write_text(original.replace(marker,
            "apps = false\nplugins = true\nremote_plugin = true\nrecommended_plugins = false\n"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["ordinary-plugin-templates"])
    args = parser.parse_args()
    fixture = TemplateFixture(args)

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
