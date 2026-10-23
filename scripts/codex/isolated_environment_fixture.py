#!/usr/bin/env python3
"""Private-loopback real Codex app-server and authenticated executor profile.

Native JSONL is forwarded unchanged. The proxy copies bytes without synthesizing
RPCs. Its only fault injection closes owned sockets; all credentials are synthetic.
"""
import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse


TOKEN = "synthetic-isolated-executor-credential-canary"
ALLOWED_METHODS = {"initialize", "initialized", "environment/add", "environment/info",
                   "environment/status", "thread/loaded/list"}


class Fixture:
    def __init__(self, root, namespace):
        self.root = root
        self.lock = threading.Lock()
        self.journal = {"namespace": namespace, "events": []}
        self.closed = threading.Event()
        self.children = []
        self.connections = set()
        self.proxy_lock = threading.Lock()
        self.record("isolation_ready")

    def record(self, event, **fields):
        with self.lock:
            self.journal["events"].append({"event": event, **fields})
            pending = self.root / "isolated-environment-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-environment-journal.json")

    def configure(self):
        for name in ["home", "app", "executor", "workspace", "executor-workspace", "tmp"]:
            (self.root / name).mkdir(exist_ok=True)
        fixture = self

        class DenyHTTP(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                fixture.record("unexpected_http", method="GET")
                self.send_error(500)

            def do_POST(self):
                fixture.record("unexpected_http", method="POST")
                self.send_error(500)

        self.http = ThreadingHTTPServer(("127.0.0.1", 0), DenyHTTP)
        self.http.daemon_threads = True
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        endpoint = f"http://127.0.0.1:{self.http.server_port}"
        catalog = self.root / "app" / "models.json"
        catalog.write_text(json.dumps({"models": [{
            "slug": "mock-model", "display_name": "No inference environment profile",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]}))
        config = f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "{endpoint}/backend-api"
openai_base_url = "{endpoint}/v1"
[features]
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned no-inference fixture"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        for name in ["app", "executor"]:
            (self.root / name / "config.toml").write_text(config)
        secret = self.root / "executor-token"
        secret.write_text(TOKEN)
        secret.chmod(0o600)
        return secret

    def environment(self, name):
        # No inherited credentials, proxy, cloud or exporter settings.
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(self.root / name),
                "TMPDIR": str(self.root / "tmp"), "SHELL": "/bin/sh",
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "NO_COLOR": "1", "RUST_LOG": "off", "NO_PROXY": "*", "no_proxy": "*"}

    def spawn(self, binary, args, name, cwd):
        log = open(self.root / f"{name}-stderr.log", "w")
        try:
            child = subprocess.Popen([binary, *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=log, cwd=cwd, env=self.environment(name),
                                     text=True, bufsize=1)
        finally:
            log.close()
        self.children.append(child)
        return child

    def start_executor(self, binary, secret):
        self.executor = self.spawn(binary, ["exec-server", "--listen", "ws://127.0.0.1:0",
                                           "--ws-auth", "capability-token", "--ws-token-file",
                                           str(secret)], "executor", self.root / "executor-workspace")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            readable, _, _ = select.select([self.executor.stdout], [], [], deadline - time.monotonic())
            assert readable, "native executor listener deadline"
            line = self.executor.stdout.readline()
            assert line, "native executor exited before listener readiness"
            if line.startswith("ws://"):
                parsed = urlparse(line.strip())
                assert parsed.scheme == "ws" and parsed.hostname == "127.0.0.1"
                assert parsed.port and parsed.port > 0
                self.executor_address = (parsed.hostname, parsed.port)
                self.record("executor_started", pid=self.executor.pid)
                break
        else:
            raise AssertionError("native executor listener deadline")
        self.probe_upgrade(None, 401)
        self.probe_upgrade("incorrect-synthetic-token", 401)
        self.probe_upgrade(TOKEN, 101)
        self.proxy = socket.socket()
        self.proxy.bind(("127.0.0.1", 0))
        self.proxy.listen()
        self.proxy.settimeout(0.1)
        self.url = f"ws://127.0.0.1:{self.proxy.getsockname()[1]}"
        threading.Thread(target=self.accept_proxy, daemon=True).start()

    def probe_upgrade(self, token, expected):
        with socket.create_connection(self.executor_address, timeout=5) as conn:
            headers = ["GET / HTTP/1.1", f"Host: 127.0.0.1:{self.executor_address[1]}",
                       "Connection: Upgrade", "Upgrade: websocket", "Sec-WebSocket-Version: 13",
                       "Sec-WebSocket-Key: " + base64.b64encode(b"owned-exec-probe").decode()]
            if token is not None:
                headers.append("Authorization: Bearer " + token)
            conn.sendall(("\r\n".join(headers) + "\r\n\r\n").encode())
            status = int(conn.makefile("rb").readline(4096).split()[1])
            assert status == expected, "native executor upgrade status"
        self.record("native_auth_probe", credential="absent" if token is None else
                    "valid" if token == TOKEN else "wrong", status=status)

    def accept_proxy(self):
        while not self.closed.is_set():
            try:
                downstream, _ = self.proxy.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                upstream = socket.create_connection(self.executor_address, timeout=1)
            except OSError:
                downstream.close()
                self.record("proxy_destination_unavailable")
                continue
            with self.proxy_lock:
                self.connections.update([downstream, upstream])
            self.record("proxy_connected")
            threading.Thread(target=self.copy_connection, args=(downstream, upstream), daemon=True).start()

    def copy_connection(self, first, second):
        try:
            while not self.closed.is_set():
                readable, _, _ = select.select([first, second], [], [], 0.1)
                for source in readable:
                    data = source.recv(65_536)
                    if not data:
                        return
                    (second if source is first else first).sendall(data)
        except OSError:
            pass
        finally:
            with self.proxy_lock:
                self.connections.difference_update([first, second])
            first.close()
            second.close()
            self.record("proxy_disconnected")

    def disconnect(self):
        with self.proxy_lock:
            for conn in list(self.connections):
                try:
                    conn.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass

    def controls(self):
        seen = None
        while not self.closed.wait(0.01):
            path = self.root / "control.json"
            if not path.exists():
                continue
            control = json.loads(path.read_text())
            if control["id"] == seen:
                continue
            seen = control["id"]
            if control["action"] == "disconnect":
                self.disconnect()
            elif control["action"] == "stop_executor":
                self.executor.terminate()
                self.executor.wait(timeout=5)
                self.disconnect()
                self.record("executor_stopped", pid=self.executor.pid)
            else:
                self.record("fixture_error", stage="invalid-control")
                return
            self.record("control_completed", id=seen)

    def close(self):
        self.closed.set()
        if hasattr(self, "proxy"):
            self.proxy.close()
            self.disconnect()
        for child in reversed(self.children):
            if child.poll() is None:
                child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
        if hasattr(self, "http"):
            self.http.shutdown()
            self.http.server_close()


def isolated(args):
    child_ns = os.readlink("/proc/self/ns/net")
    assert child_ns != args.parent_netns, "BLOCKED_ENV: network namespace unchanged"
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert len(links) == 1 and links[0]["ifname"] == "lo", "BLOCKED_ENV: nonloopback interface"
    assert all(row.get("dst") != "default" and row.get("dev") == "lo" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    fixture = Fixture(Path(args.root), {"parent": args.parent_netns, "child": child_ns,
                                       "interfaces": ["lo"], "default_route": False})
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        if not stopping:
            stopping = True
            raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    reader = None
    try:
        secret = fixture.configure()
        fixture.start_executor(args.codex, secret)
        native = fixture.spawn(args.codex, ["app-server", "--listen", "stdio://"],
                               "app", fixture.root / "workspace")
        fixture.record("native_started", pid=native.pid, executor_pid=fixture.executor.pid,
                       controller_pid=os.getpid(), namespace_owner_pid=os.getppid(),
                       executor_url=fixture.url)
        threading.Thread(target=fixture.controls, daemon=True).start()

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
        fixture.close()
        if reader is not None:
            reader.join(5)
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux environment profile required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        parent = os.readlink("/proc/self/ns/net")
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", parent])
    isolated(args)


if __name__ == "__main__":
    main()
