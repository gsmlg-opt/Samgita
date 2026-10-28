#!/usr/bin/env python3
"""Finite ordinary native plugin/list marketplace metadata.

One synchronous owned dependency, no app-server emulator or mutation/model/tool.
Reuse only inert setup, bounded journal and cleanup from the ordinary helper.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import traceback
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from ordinary_app_context_fixture import Fixture as OrdinarySetup
from ordinary_app_context_fixture import MAX_BODY, MAX_HTTP

PREFIX = "/backend-api/ps/plugins/"
EMPTY = {"plugins": [], "pagination": {"next_page_token": None}}
STARTUP = {
    "featured": ("/backend-api/plugins/featured", {"platform": ["codex"]}, []),
    "suggested": (PREFIX + "suggested/codex", {"scope": ["GLOBAL"]},
                  {"enabled": False, "plugins": []}),
    "catalog": (PREFIX + "list", {"scope": ["GLOBAL"], "limit": ["200"]}, EMPTY),
    "installed_cache": (PREFIX + "installed", {"limit": ["200"]}, EMPTY),
    "installed_bundles": (PREFIX + "installed",
                          {"limit": ["200"], "includeDownloadUrls": ["true"]}, EMPTY),
}


def plugin(bucket, suffix, scope, discoverability=None):
    row = {
        "id": f"plugins~Plugin_owned_{bucket}_{suffix}",
        "name": f"owned-{bucket}-{suffix}", "scope": scope,
        # Required backend literals are fixed inert setup. No computed native
        # policy/share context or permission outcome is inspected by this case.
        "installation_policy": "AVAILABLE", "authentication_policy": "ON_USE",
        "release": {
            "version": "1.0.0" if suffix == "alpha" else "2.3.0",
            "display_name": f"Owned {bucket} {suffix} λ🙂",
            "description": f"Ordinary {bucket} descriptive catalog metadata",
            "keywords": [f"{bucket}-metadata", "ordinary-λ", suffix],
            "interface": {},
        },
    }
    if discoverability is not None:
        row["discoverability"] = discoverability
    return row


def page(bucket):
    scope, discoverability = {
        "workspace": ("WORKSPACE", "LISTED"),
        "shared": ("WORKSPACE", "PRIVATE"),
        "created": ("USER", None),
        "vertical": ("GLOBAL", None),
    }[bucket]
    # Deliberate beta/alpha input order. Real catalog conversion preserves this
    # order; independently specified native expectations live in the test.
    return {"plugins": [plugin(bucket, suffix, scope, discoverability)
                        for suffix in ["beta", "alpha"]],
            "pagination": {"next_page_token": None}}


class MarketplaceKindsFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-marketplace-kinds-journal.json"
        self.http_count = 0
        self.startup_counts = {kind: 0 for kind in STARTUP}
        self.startup_generation = 0
        self.catalog_count = 0
        self.vertical = args.scenario == "ordinary-marketplace-vertical"
        self.cold_cache_scopes = {"USER", "WORKSPACE"}
        self.business_installed_count = 0
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
                assert len(data) <= MAX_BODY, "Owned marketplace reply bound"
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
                    elif path == "/backend-api/wham/config/bundle" and query == {}:
                        self.reply(200, {})
                    elif path == "/backend-api/wham/accounts/check" and query == {}:
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif path == "/backend-api/wham/settings/user" and query == {}:
                        self.reply(200, {"commit_attribution_enabled": False})
                    elif path == PREFIX + "installed" and query in [
                            {"scope": ["WORKSPACE"]}, {"scope": ["USER"]},
                            {"scope": ["GLOBAL"]}]:
                        owner.business_installed_count += 1
                        assert owner.business_installed_count <= 7, "Owned business snapshot bound"
                        owner.record("business_installed", sequence=owner.business_installed_count,
                                     path=path, query=query)
                        self.reply(200, EMPTY)
                    elif path == PREFIX + "list" and query in [
                            {"scope": ["WORKSPACE"], "limit": ["200"]},
                            {"scope": ["USER"], "limit": ["200"]}]:
                        bucket = "workspace" if query["scope"] == ["WORKSPACE"] else "created"
                        if not owner.cached_catalog_served(path, query):
                            owner.catalog_served(bucket, path, query)
                        self.reply(200, page(bucket))
                    elif path == PREFIX + "workspace/shared" and query == {"limit": ["200"]}:
                        owner.catalog_served("shared", path, query)
                        self.reply(200, page("shared"))
                    elif path == PREFIX + "list" and query == {
                            "scope": ["GLOBAL"], "limit": ["200"], "collection": ["vertical"]}:
                        owner.catalog_served("vertical", path, query)
                        self.reply(200, page("vertical"))
                    else:
                        owner.record("unexpected_http", method="GET", path=path, query=query)
                        self.reply(404, {})
                except Exception as error:
                    line = traceback.extract_tb(error.__traceback__)[-1].lineno
                    owner.record("fatal", stage="ordinary-marketplace-handler",
                                 kind=type(error).__name__, line=line,
                                 catalogCount=owner.catalog_count,
                                 catalogs=[event["bucket"] for event in owner.events
                                           if event["event"] == "business_catalog"],
                                 startupCounts=dict(owner.startup_counts))
                    self.reply(500, {"error": "owned marketplace fixture failed"})

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

    def catalog_served(self, bucket, path, query):
        self.catalog_count += 1
        assert self.catalog_count <= 7, "Owned descriptive catalog bound"
        self.record("business_catalog", sequence=self.catalog_count,
                    bucket=bucket, path=path, query=query)

    def startup_served(self, kind, path, query):
        self.startup_counts[kind] += 1
        # Catalog listing may start extra empty background installed/suggested
        # refreshes. These retain exact query shapes and bounded counts rather
        # than being miscounted as the seven explicit scoped business reads.
        limit = 2 if kind in ["featured", "catalog"] else 16
        assert self.startup_counts[kind] <= limit, "Owned startup-read bound"
        self.record("startup", kind=kind, sequence=self.startup_counts[kind],
                    path=path, query=query)
        self.maybe_startup_ready()

    def cached_catalog_served(self, path, query):
        marker = self.root / "cold-start.json"
        scope = query["scope"][0]
        if self.vertical or not marker.exists() or scope not in self.cold_cache_scopes:
            return False
        data = marker.read_bytes()
        assert len(data) <= 256
        assert json.loads(data) == {"phase": "cold", "cachedScopes": ["USER", "WORKSPACE"]}
        # No explicit cold list is issued until this barrier. These are the
        # real startup refreshes of catalogs populated by the warm native.
        assert self.startup_generation == 1
        self.cold_cache_scopes.remove(scope)
        self.record("startup_cached_catalog", path=path, query=query)
        self.maybe_startup_ready()
        return True

    def maybe_startup_ready(self):
        generation = self.startup_generation + 1
        if generation == 2 and (not (self.root / "cold-start.json").exists()
                                or self.cold_cache_scopes):
            return
        if generation <= 2 and all(count >= generation for count in self.startup_counts.values()):
            self.startup_generation = generation
            self.record("startup_ready", generation=generation)
            print(json.dumps({"event": "startup_ready", "generation": generation}), flush=True)

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        original = path.read_text()
        if self.vertical:
            # Exact existing NativeLaunchFixture.local_plugins_after_initialize
            # fragment: launch without plugin startup tasks, restore this fixed
            # positive profile before the real vertical list requests.
            marker = "[features]\napps = true\nplugins = false\nrecommended_plugins = false\n"
            assert original.count(marker) == 1, "Reviewed vertical setup feature block"
            path.write_text(original.replace(marker,
                "[features]\nplugins = true\nremote_plugin = false\napps = false\n"
                "recommended_plugins = false\n"))
            return
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert original.count(marker) == 1, "Reviewed ordinary setup feature block"
        path.write_text(original.replace(marker,
            "apps = false\nplugins = true\nremote_plugin = true\nplugin_sharing = true\n"
            "recommended_plugins = false\n"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=[
        "ordinary-marketplace-kinds", "ordinary-marketplace-vertical"])
    fixture = MarketplaceKindsFixture(parser.parse_args())

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
