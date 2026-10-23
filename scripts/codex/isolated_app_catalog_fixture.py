#!/usr/bin/env python3
"""Private native app catalog profile with discovery-only synthetic HTTP peers.

The app-server is the immutable release executable. Only directory facts and
MCP discovery are synthesized; tools/call and model/turn execution are forbidden.
"""
import argparse
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
from urllib.parse import parse_qs, urlparse

from isolated_apps_fixture import ACCOUNT_ID, ACCESS_TOKEN, Fixture as MetadataFixture


ALLOWED_METHODS = {"initialize", "initialized", "app/list", "app/installed", "thread/loaded/list"}
MCP_PATH = "/backend-api/ps/mcp"


def tool(app_id, suffix="", synthetic=False):
    meta = {"connector_id": app_id, "connector_name": f"{app_id.capitalize()} Runtime"}
    if synthetic:
        meta["_codex_apps"] = {"synthetic_link": True}
    return {
        "name": f"connector_{app_id}{suffix}", "description": "Synthetic discovery only",
        "inputSchema": {"type": "object", "additionalProperties": False},
        "annotations": {"readOnlyHint": True}, "_meta": meta,
    }


def directory_app(app_id):
    return {"id": app_id, "name": f"{app_id.capitalize()} Directory",
            "description": f"Directory {app_id}"}


class Fixture(MetadataFixture):
    def __init__(self, root, scenario, namespace):
        # Reuse configuration/auth/lifetime helpers, not the metadata handler.
        self.root = root
        self.scenario = scenario
        self.product_sku = "codex"
        self.lock = threading.Lock()
        self.closing = threading.Event()
        self.journal = {"namespace": namespace, "events": []}
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_args):
                pass

            def reply(self, status, value=None):
                body = b"" if value is None else json.dumps(value).encode()
                self.send_response(status)
                if value is not None:
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

            def verified_headers(self, mcp=False):
                if mcp:
                    # The pinned release intentionally withholds ChatGPT
                    # credentials from this untrusted loopback MCP origin.
                    return {
                        "bearer_absent": self.headers.get("Authorization") is None,
                        "account_absent": self.headers.get("chatgpt-account-id") is None,
                        "sku_verified": self.headers.get("X-OpenAI-Product-Sku") == "codex",
                    }
                return {
                    "bearer_verified": self.headers.get("Authorization") == f"Bearer {ACCESS_TOKEN}",
                    "account_verified": self.headers.get("chatgpt-account-id") == ACCOUNT_ID,
                    "sku_verified": self.headers.get("oai-product-sku") == "codex",
                }

            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path in ["/backend-api/connectors/directory/list",
                                   "/backend-api/connectors/directory/list_workspace"]:
                    state = fixture.state()
                    query = parse_qs(parsed.query)
                    page = query.get("token", [None])[0]
                    assert query.get("external_logos") == ["true"]
                    assert page in [None, "page 2"]
                    verified = self.verified_headers()
                    status = state["directory_status"]
                    fixture.record("directory", token=page, status=status, **verified)
                    if not all(verified.values()):
                        self.reply(401, {"error": "synthetic directory auth mismatch"})
                        return
                    if status != 200:
                        self.reply(status, {"error": "synthetic directory failure"})
                        return
                    ids = state["directory_ids"]
                    if parsed.path.endswith("list_workspace"):
                        selected, next_token = [], None
                    elif page is None:
                        selected, next_token = ids[:2], "page 2" if len(ids) > 2 else None
                    else:
                        selected, next_token = ids[2:], None
                    self.reply(200, {"apps": [directory_app(app_id) for app_id in selected],
                                     "next_token": next_token})
                    fixture.record("directory_sent", token=page)
                elif parsed.path == MCP_PATH:
                    # Streamable HTTP's optional unsolicited SSE stream is absent.
                    fixture.record("mcp_stream_unavailable")
                    self.reply(405)
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
                    fixture.record("unexpected_http", method="GET", path=parsed.path)
                    self.reply(404, {})

            def do_POST(self):
                path = urlparse(self.path).path
                if path != MCP_PATH:
                    fixture.record("unexpected_http", method="POST", path=path)
                    self.reply(404, {})
                    return
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size <= 65_536
                wire = json.loads(self.rfile.read(size))
                method = wire.get("method")
                verified = self.verified_headers(mcp=True)
                fixture.record("mcp", method=method, **verified)
                if not all(verified.values()):
                    self.reply(401, {"error": "synthetic MCP auth mismatch"})
                    return
                result = {}
                error = None
                if method == "initialize":
                    version = wire["params"]["protocolVersion"]
                    fixture.record("mcp_initialize", protocol_version=version)
                    result = {"protocolVersion": version, "capabilities": {"tools": {}},
                              "serverInfo": {"name": "owned-catalog-fixture", "version": "1"}}
                elif method == "notifications/initialized":
                    self.reply(202)
                    return
                elif method == "ping":
                    pass
                elif method == "tools/list":
                    state = fixture.state()
                    fixture.record("tools_list", failed=state["fail_tools"])
                    if state["hold_tools"]:
                        fixture.record("tools_waiting")
                        released = fixture.root / "release-tools"
                        for _ in range(1_000):
                            if released.exists() or fixture.closing.wait(0.01):
                                break
                        else:
                            fixture.record("fixture_error", stage="tools-barrier-timeout")
                            self.reply(500, {})
                            return
                    if state["fail_tools"]:
                        error = {"code": -32603, "message": "injected discovery failure"}
                    else:
                        tools = [tool(app_id) for app_id in state["tool_ids"]]
                        if fixture.scenario == "installed" and state["tool_ids"] == ["alpha", "blocked", "disabled"]:
                            tools.extend([
                                tool("alpha", "_duplicate"),
                                tool(""),
                                {"name": "missing_connector", "inputSchema": {"type": "object"}},
                                tool("link-only", synthetic=True),
                            ])
                        result = {"tools": tools}
                else:
                    fixture.record("forbidden_mcp", method=method)
                    self.reply(403, {})
                    return
                response = {"jsonrpc": "2.0", "id": wire["id"]}
                response["error" if error else "result"] = error or result
                self.reply(200, response)

            def do_DELETE(self):
                if urlparse(self.path).path == MCP_PATH:
                    fixture.record("mcp_closed")
                    self.reply(204)
                else:
                    fixture.record("unexpected_http", method="DELETE")
                    self.reply(404)

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
            pending = self.root / "isolated-app-catalog-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-app-catalog-journal.json")

    def configure(self):
        environment = super().configure()
        config = self.root / "codex" / "config.toml"
        config.write_text('mcp_oauth_credentials_store = "file"\n' + config.read_text() + '''
[apps.blocked]
default_tools_enabled = false
[apps.disabled]
enabled = false
''')
        (self.root / "release-tools").unlink(missing_ok=True)
        (self.root / "catalog-state.json").write_text(json.dumps({
            "directory_ids": ["alpha", "beta", "gamma"], "directory_status": 200,
            "tool_ids": ["alpha", "blocked", "disabled"] if self.scenario == "installed" else ["beta"],
            "fail_tools": False, "hold_tools": False,
        }))
        return environment

    def state(self):
        return json.loads((self.root / "catalog-state.json").read_text())

    def close(self):
        self.closing.set()
        super().close()


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
        fixture.close()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--scenario", required=True,
                        choices=["catalog", "installed", "disabled", "api_key"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux isolated-app-catalog profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])
    isolated(args)


if __name__ == "__main__":
    main()
