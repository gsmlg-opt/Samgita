#!/usr/bin/env python3
"""Owned synthetic credit/nudge backend around immutable native Codex.

Only native Codex produces app-server output. Two fixed loopback POST routes
return synthetic responses; no credit service, email, model or command is run.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
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
import time
from urllib.parse import urlparse


BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
ACCESS = "synthetic-owned-account-control-access"
REFRESH = "synthetic-owned-account-control-refresh"
API_KEY = "sk-synthetic-owned-account-control-api"
ACCOUNT = "isolated-auth-account"
ALLOWED_METHODS = {"initialize", "initialized", "thread/loaded/list",
                   "account/rateLimitResetCredit/consume", "account/sendAddCreditsNudgeEmail"}


def atomic_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value, ensure_ascii=False))
    pending.replace(path)


def synthetic_token():
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return ".".join([encoded({"alg": "none", "typ": "JWT"}), encoded({
        "email": "account-control@synthetic.invalid", "exp": int(time.time()) + 3600,
        "https://api.openai.com/auth": {"chatgpt_account_id": ACCOUNT,
            "chatgpt_user_id": "isolated-auth-user", "chatgpt_plan_type": "pro"}}), "c3ludGhldGlj"])


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"], timeout=5))
    routes6 = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent, "BLOCKED_ENV: private network namespace required"
    assert [row["ifname"] for row in links] == ["lo"], "BLOCKED_ENV: nonloopback interface"
    for row in routes + routes6:
        assert row.get("dst") != "default" and row.get("dev") == "lo"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent": parent, "child": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


class Fixture:
    def __init__(self, root, route, auth, proof):
        self.root, self.route, self.auth = root, route, auth
        self.lock, self.closing = threading.RLock(), threading.Event()
        self.journal = {"namespace": proof, "events": []}
        self.prefix = "/api/codex" if route == "codex" else "/backend-api/wham"
        self.paths = {self.prefix + "/rate-limit-reset-credits/consume": "consume",
                      self.prefix + "/accounts/send_add_credits_nudge_email": "nudge"}
        self.secrets = [ACCESS, REFRESH, API_KEY]
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = False

            def handle_error(self, _request, _address):
                fixture.record("fixture_error", error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value, raw=None):
                body = (raw.encode() if raw is not None else
                        json.dumps(value, ensure_ascii=False).encode()) if status != 204 else b""
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

            def reject(self):
                fixture.record("unexpected_http", method=self.command, path=urlparse(self.path).path)
                self.reply(403, {"error": "unapproved synthetic operation"})

            def do_GET(self):
                parsed = urlparse(self.path)
                startup = {fixture.prefix + suffix for suffix in
                           ["/config/bundle", "/accounts/check", "/settings/user"]}
                if parsed.path not in startup or parsed.query or parsed.fragment:
                    self.reject()
                    return
                body = {}
                if parsed.path.endswith("/accounts/check"):
                    body = {"accounts": [{"id": ACCOUNT,
                        "workspace_backend_origin": "https://synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]}
                elif parsed.path.endswith("/settings/user"):
                    body = {"commit_attribution_enabled": False}
                fixture.record("startup_metadata", path=parsed.path)
                self.reply(200, body)

            def do_POST(self):
                parsed = urlparse(self.path)
                resource = fixture.paths.get(parsed.path)
                if resource is None or parsed.query or parsed.fragment:
                    self.reject()
                    return
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 16_384 or self.headers.get("Transfer-Encoding"):
                    fixture.record("forbidden_body", reason="unbounded request")
                    self.reply(413, {})
                    return
                body = json.loads(self.rfile.read(size))
                state = json.loads((fixture.root / "responses.json").read_text())[resource]
                bearer = self.headers.get("Authorization") == f"Bearer {ACCESS}"
                account = self.headers.get("chatgpt-account-id") == ACCOUNT
                content_type = self.headers.get("Content-Type") == "application/json"
                host = self.headers.get("Host") == urlparse(fixture.endpoint).netloc
                matches = body == state["expected"]
                fixture.record("post", resource=resource, route=fixture.route,
                    path=parsed.path, body=body, status=state["status"],
                    bearer_verified=bearer, account_verified=account,
                    content_type_verified=content_type, host_verified=host, body_verified=matches)
                if not matches:
                    fixture.record("forbidden_body", reason="unexpected fixed synthetic payload")
                if not (bearer and account and content_type and host and matches):
                    self.reply(403, {"error": "synthetic request rejected"})
                    return
                if state.get("hold"):
                    deadline = time.monotonic() + 5
                    while not (fixture.root / "release-response").exists():
                        if fixture.closing.wait(0.01):
                            return
                        assert time.monotonic() < deadline, "owned response release deadline"
                self.reply(state["status"], state["body"], state.get("raw_response"))
                fixture.record("response_sent", resource=resource)

            do_DELETE = reject
            do_PUT = reject
            do_PATCH = reject
            do_HEAD = reject

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = f"http://127.0.0.1:{self.server.server_port}"
        atomic_json(root / "responses.json", {
            name: {"status": 200, "expected": None, "body": {}} for name in ["consume", "nudge"]})
        self.record("isolation_ready", route=route, auth=auth)

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    def configure(self):
        codex = self.root / "codex"
        catalog = codex / "models.json"
        atomic_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "No inference authorized",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        backend = self.endpoint + ("/backend-api" if self.route == "chatgpt" else "")
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "{backend}"
openai_base_url = "{self.endpoint}/v1"
[features]
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned account control, no inference"
base_url = "{self.endpoint}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        if self.auth != "no_auth":
            identity = synthetic_token()
            self.secrets.append(identity)
            auth = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
                "tokens": {"id_token": identity, "access_token": ACCESS,
                           "refresh_token": REFRESH, "account_id": ACCOUNT},
                "last_refresh": datetime.now(timezone.utc).isoformat()}
            if self.auth == "api_key":
                auth = {"auth_mode": "apikey", "OPENAI_API_KEY": API_KEY, "tokens": None,
                        "last_refresh": None}
            atomic_json(codex / "auth.json", auth)
            (codex / "auth.json").chmod(0o600)
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(codex),
            "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"],
            "NO_COLOR": "1", "RUST_LOG": "off", "NO_PROXY": "*", "no_proxy": "*",
            "CODEX_DISABLE_REMOTE_CONTROL": "1", "PYTHONDONTWRITEBYTECODE": "1",
            "CODEX_REFRESH_TOKEN_URL_OVERRIDE": self.endpoint + "/forbidden-refresh",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}

    def close(self):
        self.closing.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned account backend did not stop"
        self.record("backend_closed")
        with self.lock:
            texts = [(self.root / name).read_text() for name in ["journal.json", "native-stderr.log"]]
            self.journal["redaction_checked"] = [all(secret not in text for text in texts)
                                                  for secret in self.secrets]
            atomic_json(self.root / "journal.json", self.journal)


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture, native, reader = None, None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args.root, args.route, args.auth, isolation(args.parent_netns))
        environment = fixture.configure()
        with (args.root / "native-stderr.log").open("w") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment, text=True, bufsize=1)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid())

        def output():
            for line in native.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        for line in sys.stdin:
            assert len(line.encode()) <= 16_384, "oversized native fixture input"
            wire = json.loads(line)
            if wire.get("method") not in ALLOWED_METHODS:
                fixture.record("forbidden_native")
                raise AssertionError("unapproved native method")
            fixture.record("native_input", method=wire["method"], id=wire.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.closing.set()
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
        if fixture is not None:
            fixture.close()
            fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--route", required=True, choices=["codex", "chatgpt"])
    parser.add_argument("--auth", required=True, choices=["chatgpt", "no_auth", "api_key"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == BINARY_SHA256
    assert all((args.root / name).is_dir() for name in ["home", "codex", "workspace", "tmp"])
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"]), \
            "BLOCKED_ENV: Linux user/network namespace and ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
