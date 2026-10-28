#!/usr/bin/env python3
"""Finite ordinary usage/quota/message data for the real pinned app-server.

This is a synchronous loopback business dependency, not an app-server emulator.
Only OrdinarySetup.configure/close and write_json are reused. Fixed synthetic
identity is setup only; request headers and identity outcomes are never read.
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
from ordinary_app_context_fixture import write_json

MAX_BODY = 131_072
MAX_HTTP = 48
THREAD_ID = "019fc8ab-1fb2-7000-8000-000000000211"
RATES = "/backend-api/wham/usage"
DETAILS = "/backend-api/wham/rate-limit-reset-credits"
PROFILE = "/backend-api/wham/profiles/me"
MESSAGES = "/backend-api/wham/workspace-messages"
THREAD = "/backend-api/wham/usage/thread_usage/query"


def rate_data():
    # Required backend DTO booleans are fixed setup, never selected as an oracle.
    return {"plan_type": "pro", "rate_limit": {
        "allowed": True, "limit_reached": False,
        "primary_window": {"used_percent": 37, "limit_window_seconds": 3600,
                           "reset_after_seconds": 120, "reset_at": 2_000_000_100},
        "secondary_window": {"used_percent": 12, "limit_window_seconds": 86400,
                             "reset_after_seconds": 240, "reset_at": 2_000_000_200}}}


def profile_data(sequence):
    assert sequence in (1, 2), "Owned two profile reads"
    if sequence == 1:
        return {"stats": {"lifetime_tokens": 1234, "peak_daily_tokens": 345,
            "longest_running_turn_sec": 67, "current_streak_days": 8,
            "longest_streak_days": 9, "daily_usage_buckets": [
                {"start_date": "2026-10-26", "tokens": 111},
                {"start_date": "2026-10-27", "tokens": 222}]}}
    return {"stats": {"lifetime_tokens": 2345, "peak_daily_tokens": 456,
        "longest_running_turn_sec": 78, "current_streak_days": 9,
        "longest_streak_days": 10, "daily_usage_buckets": [
            {"start_date": "2026-10-27", "tokens": 333},
            {"start_date": "2026-10-28", "tokens": 444}]}}


def thread_data():
    return {"threads": [{"thread_id": THREAD_ID,
        "estimated_usage_credits_micros": 46_000_000,
        "estimated_usage_usd_micros": 2_500_000,
        "native_usage_usd_micros": 2_000_000,
        "groups": [{"model": "owned-descriptive-model-λ", "reasoning_effort": "high",
            "speed": "standard", "estimated_usage_credits_micros": 46_000_000,
            "native_usage_usd_micros": 2_000_000, "net_new_input_tokens": 80,
            "cached_input_tokens": 20, "input_tokens": 100, "output_tokens": 40,
            "total_tokens": 140}]}]}


def message_data():
    return {"messages": [
        {"message_id": "owned-headline-1024", "message_type": "headline",
         "message_body": "Owned ordinary headline λ🙂",
         "created_at": "1970-01-01T00:01:40Z",
         "archived_at": "1970-01-01T01:03:20+01:00"},
        {"message_id": "owned-announcement-1024", "message_type": "announcement",
         "message_body": "Owned descriptive announcement β🙂",
         "created_at": "1970-01-01T00:05:00Z", "archived_at": None}]}


class ReadMetadataFixture(OrdinarySetup):
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.events = []
        self.journal = self.root / "ordinary-account-read-metadata-journal.json"
        self.http_count = 0
        self.read_counts = {kind: 0 for kind in ("rates", "thread", "profile", "messages")}
        self.read_counts["rate_details"] = 0
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                data = json.dumps(value, ensure_ascii=False).encode()
                assert len(data) <= MAX_BODY, "Owned reply bound"
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def request_location(self):
                owner.http_count += 1
                assert owner.http_count <= MAX_HTTP, "Owned request count bound"
                parsed = urlparse(self.path)
                return parsed.path, parse_qs(parsed.query, keep_blank_values=True,
                    strict_parsing=True, max_num_fields=4)

            def failure(self, error):
                owner.record("fixture_error", kind=type(error).__name__,
                    line=traceback.extract_tb(error.__traceback__)[-1].lineno)
                self.reply(500, {"error": "owned ordinary data dependency failed"})

            def do_GET(self):
                try:
                    path, query = self.request_location()
                    assert query == {}, "Owned empty read query"
                    if path == RATES:
                        sequence = owner.read("rates", "GET", path, query)
                        assert sequence <= 2
                        # Journal only ordinary numeric data; fixed DTO setup stays opaque.
                        owner.record("rate_data", sequence=sequence, primary_percent=37,
                            primary_seconds=3600, primary_reset=2_000_000_100,
                            secondary_percent=12, secondary_seconds=86400,
                            secondary_reset=2_000_000_200)
                        self.reply(200, rate_data())
                    elif (path == DETAILS and
                          owner.args.scenario == "ordinary-account-null-rate"):
                        owner.read("rate_details", "GET", path, query)
                        # Complete fixed read DTO; not an account/eligibility oracle.
                        self.reply(200, {"available_count": 0, "credits": []})
                    elif path == PROFILE:
                        sequence = owner.read("profile", "GET", path, query)
                        value = profile_data(sequence)
                        owner.record("profile_data", sequence=sequence, body=value)
                        self.reply(200, value)
                    elif path == MESSAGES:
                        sequence = owner.read("messages", "GET", path, query)
                        value = message_data()
                        owner.record("message_data", sequence=sequence, body=value)
                        self.reply(200, value)
                    elif path == "/backend-api/wham/config/bundle":
                        owner.record("startup_read", path=path, query=query)
                        self.reply(200, {})
                    elif path == "/backend-api/wham/accounts/check":
                        owner.record("startup_read", path=path, query=query)
                        self.reply(200, {"accounts": [{"id": "owned-app-context-account",
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]})
                    elif path == "/backend-api/wham/settings/user":
                        owner.record("startup_read", path=path, query=query)
                        self.reply(200, {"commit_attribution_enabled": False})
                    else:
                        owner.record("unexpected_http", method="GET", path=path, query=query)
                        self.reply(404, {})
                except Exception as error:
                    self.failure(error)

            def do_POST(self):
                try:
                    path, query = self.request_location()
                    if path != THREAD:
                        owner.record("unexpected_http", method="POST", path=path, query=query)
                        self.reply(404, {})
                        return
                    assert query == {}, "Owned empty thread query"
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 8192, "Owned read-query framing bound"
                    body = json.loads(self.rfile.read(size))
                    assert body == {"thread_ids": [THREAD_ID]}, "Owned thread reference forwarding"
                    sequence = owner.read("thread", "POST", path, query, request_body=body)
                    value = thread_data()
                    owner.record("thread_data", sequence=sequence, body=value)
                    self.reply(200, value)
                except Exception as error:
                    self.failure(error)

            def unexpected(self):
                try:
                    path, query = self.request_location()
                    owner.record("unexpected_http", method=self.command, path=path, query=query)
                    self.reply(404, {})
                except Exception as error:
                    self.failure(error)

            do_PUT = unexpected
            do_PATCH = unexpected
            do_DELETE = unexpected
            do_HEAD = unexpected
            do_OPTIONS = unexpected

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 96, "Owned event count bound"
        self.events.append({"event": event, **fields})
        value = {"events": self.events}
        assert len(json.dumps(value).encode()) <= MAX_BODY, "Owned journal bound"
        write_json(self.journal, value)

    def read(self, kind, method, path, query, **fields):
        self.read_counts[kind] += 1
        sequence = self.read_counts[kind]
        assert sequence <= 2, "Owned two reads per data route"
        self.record("business_read", kind=kind, sequence=sequence,
            method=method, path=path, query=query, status=200, **fields)
        return sequence

    def configure(self):
        super().configure()
        path = self.args.codex_home / "config.toml"
        text = path.read_text()
        marker = "apps = true\nplugins = false\nrecommended_plugins = false\n"
        assert text.count(marker) == 1, "Owned inert ordinary configuration fragment"
        path.write_text(text.replace(marker,
            "apps = false\nplugins = false\nremote_plugin = false\ncodex_hooks = false\n"
            "plugin_sharing = false\nrecommended_plugins = false\n"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=[
        "ordinary-account-read-metadata", "ordinary-account-null-rate"])
    args = parser.parse_args()
    fixture = ReadMetadataFixture(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        fixture.configure()
        print(json.dumps({"url": f"http://127.0.0.1:{fixture.http.server_port}",
                          "pid": os.getpid()}), flush=True)
        fixture.http.serve_forever(poll_interval=0.1)
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
