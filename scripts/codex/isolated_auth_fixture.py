#!/usr/bin/env python3
"""Owned loopback OAuth/backend fixture around the immutable native app-server.

The outer process execs a private user/network namespace. Only native Codex wire
messages use stdout; fixture observations are allowlisted in an atomic journal.
This qualifies a synthetic-backend profile, never live account authentication.
"""
import argparse
import base64
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
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request


def encoded(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")


def token():
    return ".".join([
        encoded({"alg": "none", "typ": "JWT"}),
        encoded({"email": "isolated-auth@synthetic.invalid", "exp": int(time.time()) + 3600,
                 "https://api.openai.com/auth": {
                     "chatgpt_account_id": "isolated-auth-account",
                     "chatgpt_user_id": "isolated-auth-user", "chatgpt_plan_type": "pro"}}),
        "c3ludGhldGlj",
    ])


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args):
        return None


class Fixture:
    def __init__(self, root, scenario, namespace):
        self.root = root
        self.scenario = scenario
        self.lock = threading.Lock()
        self.journal = {"namespace": namespace, "events": []}
        self.release_poll = threading.Event()
        self.browser_challenge = None
        self.device_verifier = "isolated-device-pkce-verifier"
        self.tokens = {"id_token": token(), "access_token": token(),
                       "refresh_token": "synthetic-isolated-refresh-canary"}
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
                path = urlparse(self.path).path
                fixture.record("backend_get", path=path)
                if path == "/backend-api/wham/config/bundle":
                    self.reply(200, {})
                elif path == "/backend-api/wham/accounts/check":
                    self.reply(200, {"accounts": [{
                        "id": "isolated-auth-account",
                        "workspace_backend_origin": "https://isolated.synthetic.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]})
                elif path == "/backend-api/wham/settings/user":
                    self.reply(200, {"commit_attribution_enabled": False})
                else:
                    fixture.record("unexpected_request", method="GET", path=path)
                    self.reply(404, {"error": "synthetic route absent"})

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65_536:
                    self.reply(413, {})
                    return
                body = self.rfile.read(size)
                path = urlparse(self.path).path
                if path == "/api/accounts/deviceauth/usercode":
                    payload = json.loads(body)
                    assert payload == {"client_id": "isolated-auth-client"}
                    fixture.record("device_usercode")
                    if fixture.scenario == "device_disabled":
                        self.reply(404, {})
                    else:
                        self.reply(200, {"device_auth_id": "isolated-device-id",
                                         "user_code": "SYNTHETIC-CODE", "interval": "1"})
                elif path == "/api/accounts/deviceauth/token":
                    payload = json.loads(body)
                    assert payload == {"device_auth_id": "isolated-device-id",
                                       "user_code": "SYNTHETIC-CODE"}
                    fixture.record("device_poll_started")
                    if fixture.scenario == "device_cancel":
                        if not fixture.release_poll.wait(15):
                            fixture.record("fixture_error", stage="cancel-barrier")
                        self.reply(404, {})
                    elif fixture.scenario == "device_error":
                        self.reply(500, {})
                    else:
                        self.reply(200, {
                            "authorization_code": "isolated-device-code",
                            "code_verifier": fixture.device_verifier,
                            "code_challenge": fixture.challenge(fixture.device_verifier)})
                elif path == "/oauth/token":
                    form = parse_qs(body.decode(), keep_blank_values=True)
                    grant = form.get("grant_type", [None])[0]
                    assert form.get("client_id") == ["isolated-auth-client"]
                    if grant == "authorization_code":
                        expected = (fixture.challenge(fixture.device_verifier)
                                    if fixture.scenario.startswith("device_")
                                    else fixture.browser_challenge)
                        verified = fixture.challenge(form["code_verifier"][0]) == expected
                        assert verified
                        fixture.record("authorization_code_exchange", pkce_verified=verified)
                        self.reply(200, fixture.tokens)
                    elif grant == "urn:ietf:params:oauth:grant-type:token-exchange":
                        assert form["subject_token"] == [fixture.tokens["id_token"]]
                        fixture.record("api_key_exchange")
                        self.reply(200, {"access_token": "sk-synthetic-isolated-exchange-canary"})
                    elif grant == "refresh_token":
                        fixture.record("refresh_exchange")
                        self.reply(200, fixture.tokens)
                    else:
                        fixture.record("unexpected_request", method="POST", path=path)
                        self.reply(400, {})
                elif path == "/oauth/revoke":
                    payload = json.loads(body)
                    assert payload["token"] == fixture.tokens["refresh_token"]
                    fixture.record("revocation", token_type=payload["token_type_hint"])
                    self.reply(200, {})
                else:
                    fixture.record("unexpected_request", method="POST", path=path)
                    self.reply(404, {})

        class OwnedServer(ThreadingHTTPServer):
            def handle_error(self, _request, _client_address):
                fixture.record("fixture_error", stage="http-handler",
                               error_type=sys.exc_info()[0].__name__)

        self.server = OwnedServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.record("fixture_ready")

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    @staticmethod
    def challenge(verifier):
        return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            pending = self.root / "isolated-auth-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-auth-journal.json")

    def configure(self):
        home = self.root / "home"
        codex = self.root / "codex"
        workspace = self.root / "workspace"
        for directory in [home, codex, workspace]:
            directory.mkdir(exist_ok=True)
        catalog = codex / "isolated-auth-models.json"
        catalog.write_text(json.dumps({"models": [{
            "slug": "mock-model", "display_name": "Isolated synthetic auth",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No model calls in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]}))
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "{self.url}/backend-api"
openai_base_url = "{self.url}/v1"
[features]
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned isolated fixture"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        return home, codex, workspace

    def browser_callback(self, auth_url):
        try:
            parsed = urlparse(auth_url)
            assert f"{parsed.scheme}://{parsed.netloc}" == self.url
            query = parse_qs(parsed.query)
            assert query["client_id"] == ["isolated-auth-client"]
            callback = query["redirect_uri"][0]
            destination = urlparse(callback)
            assert destination.hostname == "127.0.0.1" and destination.port in [1455, 1457]
            assert destination.path == "/auth/callback"
            self.browser_challenge = query["code_challenge"][0]
            opener = build_opener(ProxyHandler({}), NoRedirect())

            def get(url):
                try:
                    return opener.open(Request(url), timeout=10)
                except HTTPError as error:
                    return error

            wrong = get(callback + "?" + urlencode({"state": "wrong-synthetic-state", "code": "synthetic"}))
            assert wrong.status == 400
            wrong.close()
            self.record("browser_wrong_state", status=400)
            target = callback + "?" + urlencode({"state": query["state"][0], "code": "synthetic-browser-code"})
            response = get(target)
            assert response.status == 302
            location = response.headers["Location"]
            response.close()
            redirect = urlparse(location)
            assert redirect.scheme == destination.scheme and redirect.netloc == destination.netloc
            assert redirect.path == "/success"
            self.record("browser_callback", status=302, local_redirect=True)
            response = get(location)
            assert response.status == 200
            response.close()
            self.record("browser_success_page", status=200)
        except Exception as error:
            self.record("fixture_error", stage="browser-callback", error_type=type(error).__name__)

    def close(self):
        self.release_poll.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)


def isolated(args):
    child = os.readlink("/proc/self/ns/net")
    assert child != args.parent_netns, "BLOCKED_ENV: network namespace unchanged"
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert len(links) == 1 and links[0]["ifname"] == "lo", "BLOCKED_ENV: nonloopback interface"
    assert not any(row.get("dst") == "default" for row in routes), "BLOCKED_ENV: default route"
    assert all(row.get("dev") == "lo" for row in routes), "BLOCKED_ENV: nonloopback route"
    for row in routes:
        if row.get("prefsrc"):
            assert ipaddress.ip_address(row["prefsrc"]).is_loopback
    fixture = Fixture(Path(args.root), args.scenario, {
        "parent": args.parent_netns, "child": child, "interfaces": ["lo"], "default_route": False})
    home, codex_home, workspace = fixture.configure()
    environment = {
        "HOME": str(home), "CODEX_HOME": str(codex_home),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "NO_COLOR": "1", "RUST_LOG": "off",
        "CODEX_APP_SERVER_LOGIN_ISSUER": fixture.url,
        "CODEX_APP_SERVER_LOGIN_CLIENT_ID": "isolated-auth-client",
        "CODEX_REFRESH_TOKEN_URL_OVERRIDE": fixture.url + "/oauth/token",
        "CODEX_REVOKE_TOKEN_URL_OVERRIDE": fixture.url + "/oauth/revoke",
        "NO_PROXY": "*", "no_proxy": "*",
    }
    native = subprocess.Popen([args.codex, "app-server", "--listen", "stdio://"],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, cwd=workspace, env=environment,
                              text=True, bufsize=1)
    fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                   namespace_owner_pid=os.getppid())
    pending = {}
    pending_lock = threading.Lock()

    def output():
        for line in native.stdout:
            wire = json.loads(line)
            if "id" in wire and "method" not in wire:
                with pending_lock:
                    method = pending.pop(wire["id"], None)
                result = wire.get("result", {})
                if method == "account/login/start" and result.get("type") == "chatgpt":
                    fixture.record("browser_started")
                    if args.scenario == "browser_success":
                        threading.Thread(target=fixture.browser_callback,
                                         args=(result["authUrl"],), daemon=True).start()
                if method == "account/login/cancel" and result.get("status") == "canceled":
                    fixture.record("native_cancelled")
                    fixture.release_poll.set()
            sys.stdout.write(line)
            sys.stdout.flush()

    reader = threading.Thread(target=output, daemon=True)
    reader.start()

    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        if stopping:
            return
        stopping = True
        native.terminate()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        for line in sys.stdin:
            wire = json.loads(line)
            if "id" in wire and "method" in wire:
                with pending_lock:
                    pending[wire["id"]] = wire["method"]
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        fixture.release_poll.set()
        native.stdin.close()
        if native.poll() is None:
            native.terminate()
        try:
            native.wait(timeout=5)
        except subprocess.TimeoutExpired:
            native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
        reader.join(5)
        fixture.close()
        fixture.record("native_closed", returncode=native.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--scenario", required=True, choices=[
        "browser_success", "browser_cancel", "device_success", "device_cancel",
        "device_error", "device_disabled"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux isolated-auth profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])
    isolated(args)


if __name__ == "__main__":
    main()
