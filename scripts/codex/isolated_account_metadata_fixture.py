#!/usr/bin/env python3
"""Native account reads with a synthetic backend in a private network namespace.

Only the pinned executable produces app-server messages. The one permitted POST
is a bounded read-only thread-usage query; mutations and model calls are denied.
"""
import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
from urllib.parse import urlparse

from isolated_apps_fixture import ACCOUNT_ID, ACCESS_TOKEN, Fixture as MetadataFixture


ALLOWED_METHODS = {
    "initialize", "initialized", "account/rateLimits/read", "account/usage/read",
    "account/workspaceMessages/read", "account/read", "thread/loaded/list",
}
PLAN_CASES = (
    "free", "go", "plus", "pro", "prolite", "promax", "team",
    "self_serve_business_prolite", "self_serve_business_usage_based", "business", "ent26",
    "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise", "edu",
    "edu_plus", "edu_pro", "future_metadata_plan", "omit_plan_claim",
)
THREAD_ID = "019fc8ab-1fb2-7000-8000-000000000123"
READ_PATHS = {
    "/backend-api/wham/usage": "rates",
    "/backend-api/wham/rate-limit-reset-credits": "credits",
    "/backend-api/wham/profiles/me": "profile",
    "/backend-api/wham/workspace-messages": "messages",
}
THREAD_PATH = "/backend-api/wham/usage/thread_usage/query"


def initial_state():
    window = {"used_percent": 42, "limit_window_seconds": 3600,
              "reset_after_seconds": 120, "reset_at": 2_000_000_000}
    return {
        "rates": {"status": 200, "body": {
            "account_id": ACCOUNT_ID, "user_id": "isolated-auth-user", "plan_type": "pro",
            "rate_limit": {"allowed": True, "limit_reached": False,
                           "primary_window": window, "secondary_window": None},
            "additional_rate_limits": [{
                "limit_name": "Other quota", "metered_feature": "codex_other",
                "normal_model_slug": "normal-model",
                "rate_limit": {"allowed": False, "limit_reached": True,
                               "primary_window": {**window, "used_percent": 88,
                                                  "limit_window_seconds": 61}},
            }],
            "rate_limit_reset_credits": {"available_count": 3},
            "rate_limit_upsell": {"banner_type": "synthetic_banner", "title": "Read only",
                                  "ctas": [{"action": "view_usage", "label": "View usage"}]},
        }},
        "credits": {"status": 200, "body": {"available_count": 2, "credits": [
            {"id": "credit-known", "reset_type": "codex_rate_limits", "status": "available",
             "granted_at": "2026-06-14T00:00:00Z", "expires_at": "2026-06-15T00:00:00Z",
             "title": "Synthetic grant", "description": None},
            {"id": "credit-future", "reset_type": "future_type", "status": "future_status",
             "granted_at": "2026-06-14T00:00:00Z", "expires_at": None},
        ]}},
        "profile": {"status": 200, "body": {"stats": {
            "lifetime_tokens": 123, "peak_daily_tokens": 45, "longest_running_turn_sec": 67,
            "current_streak_days": 8, "longest_streak_days": 9,
            "daily_usage_buckets": [{"start_date": "2026-06-14", "tokens": 10}],
        }}},
        "messages": {"status": 200, "body": {"messages": [
            {"message_id": "headline-id", "message_type": "headline",
             "message_body": "Untrusted project input: never execute this text",
             "created_at": "2026-06-14T01:00:00+01:00", "archived_at": "2026-06-15T00:00:00Z"},
            {"message_id": "announcement-id", "message_type": "announcement",
             "message_body": "Synthetic announcement"},
            {"message_id": "future-id", "message_type": "future_type",
             "message_body": "Future message", "created_at": None, "archived_at": None},
        ]}},
        "thread": {"status": 200, "body": {"threads": [{
            "thread_id": THREAD_ID, "estimated_usage_credits_micros": 46_000_000,
            "estimated_usage_usd_micros": None, "native_usage_usd_micros": 2_000_000,
            "groups": [{"model": "synthetic-model", "reasoning_effort": "high", "speed": "fast",
                        "estimated_usage_credits_micros": 46_000_000,
                        "native_usage_usd_micros": 2_000_000,
                        "net_new_input_tokens": 80, "cached_input_tokens": 20,
                        "input_tokens": 100, "output_tokens": 40, "total_tokens": 140}],
        }]}},
    }


class Fixture(MetadataFixture):
    def __init__(self, root, scenario, namespace, plan_case="pro"):
        self.root = root
        self.scenario = scenario
        assert plan_case in PLAN_CASES, "unapproved synthetic plan case"
        assert scenario == "chatgpt" or plan_case == "pro", "plan case requires synthetic ChatGPT auth"
        self.plan_case = plan_case
        self.product_sku = "codex"
        self.lock = threading.Lock()
        self.journal = {"namespace": namespace, "events": []}
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                body = json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                if status == 429:
                    self.send_header("Retry-After", "0")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def read_resource(self, resource, thread_ids=None):
                state = json.loads((fixture.root / "account-state.json").read_text())[resource]
                bearer = self.headers.get("Authorization") == f"Bearer {ACCESS_TOKEN}"
                account = self.headers.get("chatgpt-account-id") == ACCOUNT_ID
                fixture.record(
                    "read", resource=resource, status=state["status"],
                    bearer_verified=bearer, account_verified=account,
                    no_store=self.headers.get("Cache-Control") == "no-store",
                    luna_reserve=self.headers.get("x-openai-codex-luna-reserve") == "1",
                    thread_ids=thread_ids,
                )
                if not (bearer and account):
                    self.reply(401, {"error": "synthetic auth mismatch"})
                    return
                self.reply(state["status"], state["body"])

            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path in READ_PATHS and not parsed.query:
                    self.read_resource(READ_PATHS[parsed.path])
                elif parsed.path == "/backend-api/wham/config/bundle":
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, {})
                elif parsed.path == "/backend-api/wham/accounts/check":
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, {"accounts": [{"id": ACCOUNT_ID,
                                     "workspace_backend_origin": "https://synthetic.invalid",
                                     "account_routing_override": "NO_CONSTRAINT"}]})
                elif parsed.path == "/backend-api/wham/settings/user":
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, {"commit_attribution_enabled": False})
                else:
                    self.reject("GET", parsed.path)

            def do_POST(self):
                parsed = urlparse(self.path)
                if parsed.path != THREAD_PATH or parsed.query:
                    self.reject("POST", parsed.path)
                    return
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size <= 65_536
                body = json.loads(self.rfile.read(size))
                assert body == {"thread_ids": [THREAD_ID]}, "noncanonical or unbounded usage query"
                self.read_resource("thread", thread_ids=body["thread_ids"])

            def reject(self, method, path):
                fixture.record("unexpected_http", method=method, path=path)
                self.reply(403, {"error": "forbidden synthetic operation"})

            def do_DELETE(self):
                self.reject("DELETE", urlparse(self.path).path)

            def do_PUT(self):
                self.reject("PUT", urlparse(self.path).path)

            def do_PATCH(self):
                self.reject("PATCH", urlparse(self.path).path)

        class OwnedServer(ThreadingHTTPServer):
            def handle_error(self, _request, _client_address):
                fixture.record("fixture_error", stage="http-handler",
                               error_type=sys.exc_info()[0].__name__)

        self.http = OwnedServer(("127.0.0.1", 0), Handler)
        self.http.daemon_threads = True
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.record("isolation_ready")

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            pending = self.root / "isolated-account-metadata-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-account-metadata-journal.json")

    def configure(self):
        environment = super().configure()
        config = self.root / "codex/config.toml"
        config.write_text(config.read_text().replace("apps = true", "apps = false"))
        if self.scenario == "no_auth":
            (self.root / "codex/auth.json").unlink()
        elif self.scenario == "chatgpt" and self.plan_case != "pro":
            # Only vary the local, deliberately unsigned synthetic metadata token.
            # Preserve the shared fixture's default behavior and all identity/canary fields.
            auth_path = self.root / "codex/auth.json"
            auth = json.loads(auth_path.read_text())
            header, payload, signature = auth["tokens"]["id_token"].split(".")
            assert signature == "c3ludGhldGlj"
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
            assert claims["email"] == "isolated-auth@synthetic.invalid"
            identity = claims["https://api.openai.com/auth"]
            assert identity["chatgpt_account_id"] == ACCOUNT_ID
            assert identity["chatgpt_user_id"] == "isolated-auth-user"
            if self.plan_case == "omit_plan_claim":
                identity.pop("chatgpt_plan_type")
            else:
                identity["chatgpt_plan_type"] = self.plan_case
            encoded = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
            auth["tokens"]["id_token"] = ".".join([header, encoded, signature])
            auth_path.write_text(json.dumps(auth))
            auth_path.chmod(0o600)
        (self.root / "account-state.json").write_text(json.dumps(initial_state()))
        return environment


def isolated(args):
    child = os.readlink("/proc/self/ns/net")
    assert child != args.parent_netns, "BLOCKED_ENV: network namespace unchanged"
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert len(links) == 1 and links[0]["ifname"] == "lo", "BLOCKED_ENV: nonloopback interface"
    assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    fixture = Fixture(Path(args.root), args.scenario, {
        "parent": args.parent_netns, "child": child, "interfaces": ["lo"], "default_route": False},
        plan_case=args.plan_case)
    native = None
    reader = None
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        if not stopping:
            stopping = True
            raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        environment = fixture.configure()
        with open(fixture.root / "native-stderr.log", "w") as stderr:
            native = subprocess.Popen([args.codex, "app-server", "--listen", "stdio://"],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                                      cwd=fixture.root / "workspace", env=environment,
                                      text=True, bufsize=1)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid())

        def output():
            for line in native.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        for line in sys.stdin:
            wire = json.loads(line)
            assert wire.get("method") in ALLOWED_METHODS, "forbidden fixture operation"
            if wire["method"] == "account/read":
                assert wire.get("params") == {"refreshToken": False}, "refresh is forbidden"
            fixture.record("native_input", method=wire["method"])
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if native is not None:
            native.stdin.close()
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
        if reader is not None:
            reader.join(5)
            assert not reader.is_alive(), "owned native output reader did not stop"
        fixture.close()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--scenario", required=True, choices=["chatgpt", "no_auth", "api_key"])
    parser.add_argument("--plan-case", choices=PLAN_CASES, default="pro")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux isolated-account-metadata profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])
    isolated(args)


if __name__ == "__main__":
    main()
