#!/usr/bin/env python3
"""Bounded read-only synthetic quota backend around immutable native Codex.

Only the native child emits app-server frames. This fixture imports
the retained account fixture's synthetic-auth/configuration/close helpers, but
overrides its HTTP server and never admits any POST or account mutation.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse

from isolated_account_control_fixture import (
    ACCESS, ACCOUNT, BINARY_SHA256, REFRESH, Fixture as ControlFixture, atomic_json,
)


ALLOWED = {"initialize", "initialized", "account/rateLimits/read", "thread/loaded/list"}
MAX_INPUT = 16_384
MAX_OUTPUT = 65_536
MAX_MESSAGES = 96
MAX_EVENTS = 256
MAX_HTTP_READS = 64


def isolation(args):
    net, user = os.readlink("/proc/self/ns/net"), os.readlink("/proc/self/ns/user")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes.extend(json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5)))
    assert net != args.parent_netns and user != args.parent_userns
    assert os.getuid() == 0 and [link["ifname"] for link in links] == ["lo"]
    for route in routes:
        assert route.get("dst") != "default" and route.get("dev") == "lo"
        assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback
    return {"parent": args.parent_netns, "child": net,
            "parent_user": args.parent_userns, "child_user": user,
            "interfaces": ["lo"], "default_route": False, "ipv6_default_route": False}


class Fixture(ControlFixture):
    def __init__(self, root, route, proof):
        self.root, self.route, self.auth = root, route, "chatgpt"
        self.lock, self.closing = threading.RLock(), threading.Event()
        self.journal = {"namespace": proof, "events": []}
        self.secrets = [ACCESS, REFRESH]
        self.prefix = "/api/codex" if route == "codex" else "/backend-api/wham"
        self.paths = {self.prefix + "/usage": "rates",
                      self.prefix + "/rate-limit-reset-credits": "credits"}
        self.read_count = 0
        self.peer_sockets, self.peer_threads = set(), set()
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            block_on_close = False

            def process_request_thread(self, request, client_address):
                thread = threading.current_thread()
                with fixture.lock:
                    if fixture.closing.is_set():
                        request.close()
                        return
                    fixture.peer_sockets.add(request)
                    fixture.peer_threads.add(thread)
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    with fixture.lock:
                        fixture.peer_sockets.discard(request)
                        fixture.peer_threads.discard(thread)

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, value):
                body = json.dumps(value, ensure_ascii=False).encode()
                assert len(body) <= MAX_OUTPUT
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
                fixture.record("unexpected_http", method=self.command,
                               path=urlparse(self.path).path)
                self.reply(403, {"error": "unapproved synthetic operation"})

            def do_GET(self):
                parsed = urlparse(self.path)
                host = self.headers.get("Host") == urlparse(fixture.endpoint).netloc
                bodyless = self.headers.get("Content-Length") in (None, "0") and \
                    self.headers.get("Transfer-Encoding") is None
                if parsed.query or parsed.fragment or not host or not bodyless:
                    self.reject()
                    return
                resource = fixture.paths.get(parsed.path)
                if resource is None:
                    startup = {fixture.prefix + suffix for suffix in
                               ["/config/bundle", "/accounts/check", "/settings/user"]}
                    if parsed.path not in startup:
                        self.reject()
                        return
                    value = {}
                    if parsed.path.endswith("/accounts/check"):
                        value = {"accounts": [{"id": ACCOUNT,
                            "workspace_backend_origin": "https://synthetic.invalid",
                            "account_routing_override": "NO_CONSTRAINT"}]}
                    elif parsed.path.endswith("/settings/user"):
                        value = {"commit_attribution_enabled": False}
                    fixture.record("startup_metadata", path=parsed.path)
                    self.reply(200, value)
                    return
                state = json.loads((root / "rate-read-state.json").read_text())[resource]
                bearer = self.headers.get("Authorization") == f"Bearer {ACCESS}"
                account = self.headers.get("chatgpt-account-id") == ACCOUNT
                reserve = self.headers.get("x-openai-codex-luna-reserve") == "1"
                with fixture.lock:
                    fixture.read_count += 1
                    assert fixture.read_count <= MAX_HTTP_READS
                fixture.record("read", resource=resource, path=parsed.path,
                    route=route, status=state["status"], bearer_verified=bearer,
                    account_verified=account, host_verified=host,
                    bodyless_verified=bodyless, luna_reserve=reserve)
                if not (bearer and account) or (resource == "credits" and reserve):
                    fixture.record("forbidden_headers")
                    self.reply(401, {})
                    return
                if state.get("hold"):
                    assert resource == "credits"
                    fixture.record("detail_waiting")
                    deadline = time.monotonic() + 8
                    while not (root / "release-credit-details").exists():
                        if fixture.closing.wait(0.01):
                            return
                        assert time.monotonic() < deadline, "owned detail release deadline"
                self.reply(state["status"], state["body"])
                fixture.record("read_finished", resource=resource)

            do_POST = reject
            do_DELETE = reject
            do_PUT = reject
            do_PATCH = reject
            do_HEAD = reject

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)
        self.thread.start()
        self.endpoint = f"http://127.0.0.1:{self.server.server_port}"
        atomic_json(root / "rate-read-state.json", {
            "rates": {"status": 200, "body": {"plan_type": "pro"}},
            "credits": {"status": 200, "body": {"available_count": 0, "credits": []}},
        })
        self.record("isolation_ready", route=route)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < MAX_EVENTS, "owned journal bound exceeded"
            self.journal["events"].append({"event": event, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    def configure(self):
        environment = super().configure()
        path = self.root / "codex" / "config.toml"
        text = path.read_text().replace("[features]\n", "[features]\nhooks = false\n")
        path.write_text(text + "\n[analytics]\nenabled = false\n")
        return environment

    def close(self, deadline):
        self.closing.set()
        with self.lock:
            peers, workers = list(self.peer_sockets), list(self.peer_threads)
        for peer in peers:
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(remaining(deadline, 0.1))
        assert not self.thread.is_alive(), "owned quota backend did not stop"
        for worker in workers:
            worker.join(remaining(deadline, 0.1))
            assert not worker.is_alive(), "owned quota HTTP worker did not stop"
        self.record("backend_closed")
        with self.lock:
            texts = [(self.root / name).read_text() for name in ["journal.json", "native-stderr.log"]]
            self.journal["redaction_checked"] = [all(secret not in text for text in texts)
                                                  for secret in self.secrets]
            atomic_json(self.root / "journal.json", self.journal)


def remaining(deadline, cap):
    return max(0.0, min(cap, deadline - time.monotonic()))


def validate(wire):
    method, params = wire.get("method"), wire.get("params")
    assert method in ALLOWED and set(wire) <= {"jsonrpc", "id", "method", "params"}
    if method == "account/rateLimits/read":
        assert params is None or (isinstance(params, dict) and
            set(params) <= {"excludeResetCreditDetails", "supportsLunaReserve"} and
            all(isinstance(value, bool) for value in params.values()))
    elif method == "thread/loaded/list":
        assert params in (None, {})
    elif method == "initialize":
        assert params["clientInfo"]["name"] == "samgita_rate_read"
        assert not params.get("capabilities", {}).get("experimentalApi", False)


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture, native = None, None
    readers, failed = [], threading.Event()

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args.root, args.route, isolation(args))
        (args.root / "native-stderr.log").touch()
        native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=args.root / "workspace", env=fixture.configure(), bufsize=0)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid())

        def output():
            try:
                count = 0
                while line := native.stdout.readline(MAX_OUTPUT + 1):
                    count += 1
                    assert len(line) <= MAX_OUTPUT and line.endswith(b"\n")
                    assert count <= MAX_MESSAGES
                    assert all(secret.encode() not in line for secret in fixture.secrets)
                    wire = json.loads(line)
                    fixture.record("native_output", method=wire.get("method"), id=wire.get("id"))
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                failed.set()
                fixture.record("fixture_error", error_type=type(error).__name__)
                native.terminate()

        def errors():
            total = 0
            try:
                with (args.root / "native-stderr.log").open("wb") as target:
                    while block := native.stderr.read(4096):
                        total += len(block)
                        assert total <= 262_144, "owned stderr bound exceeded"
                        target.write(block)
            except Exception as error:
                failed.set()
                fixture.record("fixture_error", error_type=type(error).__name__)
                native.terminate()

        for target in (output, errors):
            reader = threading.Thread(target=target, daemon=True)
            reader.start()
            readers.append(reader)
        count = 0
        while line := sys.stdin.buffer.readline(MAX_INPUT + 1):
            count += 1
            assert len(line) <= MAX_INPUT and line.endswith(b"\n") and count <= 64
            wire = json.loads(line)
            validate(wire)
            fixture.record("native_input", method=wire["method"], id=wire.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        deadline = time.monotonic() + 0.75
        if fixture is not None:
            fixture.closing.set()
        if native is not None:
            native.stdin.close()
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=remaining(deadline, 0.25))
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=remaining(deadline, 0.15))
        for reader in readers:
            reader.join(remaining(deadline, 0.1))
            assert not reader.is_alive(), "owned quota reader did not stop"
        if fixture is not None:
            fixture.close(deadline)
            if native is not None:
                fixture.record("native_closed", native_reaped=native.poll() is not None,
                               readers_stopped=all(not r.is_alive() for r in readers),
                               output_valid=not failed.is_set())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--route", required=True, choices=["codex", "chatgpt"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == BINARY_SHA256
    assert all((args.root / name).is_dir() for name in ["home", "codex", "workspace", "tmp"])
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter fixture"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net"),
            "--parent-userns", os.readlink("/proc/self/ns/user")])
    isolated(args)


if __name__ == "__main__":
    main()
