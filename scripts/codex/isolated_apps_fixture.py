#!/usr/bin/env python3
"""Native app/read with an owned synthetic backend in a private network namespace.

Only the immutable app-server produces protocol output. This backend serves
metadata; it never implements an Agent, MCP execution, a model or live auth.
"""
import argparse
from datetime import datetime, timezone
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

from isolated_auth_fixture import token


ACCESS_TOKEN = "synthetic-isolated-apps-access-canary"
REFRESH_TOKEN = "synthetic-isolated-apps-refresh-canary"
API_KEY = "sk-synthetic-isolated-apps-canary"
ACCOUNT_ID = "isolated-auth-account"
ALLOWED_METHODS = {"initialize", "initialized", "app/read", "thread/loaded/list"}


def app_metadata(app_id):
    name = app_id.capitalize()
    return {
        "id": app_id, "name": name, "description": f"{name} description",
        "icon_url": None, "icon_dark_url": f"https://synthetic.invalid/icons/{app_id}-dark",
        "distribution_channel": "ECOSYSTEM_DIRECTORY",
        "tools": [{"name": f"{app_id}_tool", "title": f"{name} Tool",
                   "description": f"Use {name}", "is_enabled": False,
                   "disabled_reason": "disabled_by_admin", "is_read_only": True}],
        "actions": [{"name": "untrusted-not-a-callable-tool"}],
        "model_description": "must-not-escape-metadata-projection",
        "icon_assets": {"256_square": "must-not-escape-metadata-projection"},
    }


class Fixture:
    def __init__(self, root, scenario, namespace):
        self.root = root
        self.scenario = scenario
        self.lock = threading.Lock()
        self.journal = {"namespace": namespace, "events": []}
        self.product_sku = "synthetic-custom-sku" if scenario == "custom_sku" else "codex"
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
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                self.close_connection = True

            def do_GET(self):
                # Native startup may fetch account/config metadata. No route
                # returns a tool catalog or model response.
                path = self.path.split("?", 1)[0]
                if path == "/backend-api/wham/config/bundle":
                    response = {}
                elif path == "/backend-api/wham/accounts/check":
                    response = {"accounts": [{"id": ACCOUNT_ID,
                                "workspace_backend_origin": "https://synthetic.invalid",
                                "account_routing_override": "NO_CONSTRAINT"}]}
                elif path == "/backend-api/wham/settings/user":
                    response = {"commit_attribution_enabled": False}
                else:
                    fixture.record("unexpected_http", method="GET", path=path)
                    self.reply(404, {"error": "forbidden synthetic route"})
                    return
                fixture.record("startup_metadata", path=path)
                self.reply(200, response)

            def do_POST(self):
                path = self.path.split("?", 1)[0]
                if path != "/backend-api/ps/apps/batch":
                    fixture.record("unexpected_http", method="POST", path=path)
                    self.reply(404, {"error": "forbidden synthetic route"})
                    return
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65_536:
                    fixture.record("fixture_error", stage="body-size")
                    self.reply(413, {})
                    return
                body = json.loads(self.rfile.read(size))
                assert set(body) == {"app_ids", "include_tools"}
                assert isinstance(body["app_ids"], list) and len(body["app_ids"]) <= 100
                assert all(isinstance(app_id, str) for app_id in body["app_ids"])
                assert isinstance(body["include_tools"], bool)
                bearer = self.headers.get("Authorization") == f"Bearer {ACCESS_TOKEN}"
                account = self.headers.get("chatgpt-account-id") == ACCOUNT_ID
                sku = self.headers.get("oai-product-sku") == fixture.product_sku
                status = int((fixture.root / "status").read_text())
                fixture.record("batch", body=body, status=status,
                               bearer_verified=bearer, account_verified=account, sku_verified=sku)
                if not (bearer and account and sku):
                    self.reply(401, {"error": "synthetic request headers rejected"})
                    return
                if status != 200:
                    self.reply(status, {"error": "synthetic metadata backend failure"})
                    return
                # Deliberately return a different order, duplicate and unrelated
                # app. Native filtering and first-requested order must prevail.
                apps = [app_metadata(app_id) for app_id in ["alpha", "beta", "alpha", "extra"]
                        if app_id in body["app_ids"] or app_id == "extra"]
                if not body["include_tools"]:
                    for app in apps:
                        app["tools"] = None
                self.reply(200, {"apps": apps})

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
            pending = self.root / "isolated-apps-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-apps-journal.json")

    def configure(self):
        for name in ["home", "codex", "workspace", "tmp"]:
            (self.root / name).mkdir(exist_ok=True)
        codex = self.root / "codex"
        endpoint = f"http://127.0.0.1:{self.http.server_port}"
        catalog = codex / "models.json"
        catalog.write_text(json.dumps({"models": [{
            "slug": "mock-model", "display_name": "Metadata only, no inference",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]}))
        sku = f'apps_mcp_product_sku = "{self.product_sku}"\n' if self.scenario == "custom_sku" else ""
        enabled = "false" if self.scenario == "disabled" else "true"
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "{endpoint}/backend-api"
openai_base_url = "{endpoint}/v1"
{sku}[features]
apps = {enabled}
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned metadata-only fixture"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        auth = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                "tokens": {"id_token": token(), "access_token": ACCESS_TOKEN,
                           "refresh_token": REFRESH_TOKEN, "account_id": ACCOUNT_ID},
                "last_refresh": datetime.now(timezone.utc).isoformat()}
        if self.scenario == "api_key":
            auth = {"auth_mode": "apikey", "OPENAI_API_KEY": API_KEY, "tokens": None,
                    "last_refresh": None}
        auth_path = codex / "auth.json"
        auth_path.write_text(json.dumps(auth))
        auth_path.chmod(0o600)
        (self.root / "status").write_text("200")
        return {
            "HOME": str(self.root / "home"), "CODEX_HOME": str(codex),
            "TMPDIR": str(self.root / "tmp"), "SHELL": "/bin/sh",
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "NO_COLOR": "1", "RUST_LOG": "off", "NO_PROXY": "*", "no_proxy": "*",
            "CODEX_REFRESH_TOKEN_URL_OVERRIDE": endpoint + "/forbidden-refresh",
        }

    def close(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned metadata backend did not stop"


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
        "parent": args.parent_netns, "child": child, "interfaces": ["lo"], "default_route": False})
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
    parser.add_argument("--scenario", required=True,
                        choices=["enabled", "disabled", "api_key", "custom_sku"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux isolated-apps profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])
    isolated(args)


if __name__ == "__main__":
    main()
