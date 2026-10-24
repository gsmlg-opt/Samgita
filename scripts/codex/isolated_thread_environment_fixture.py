#!/usr/bin/env python3
"""Real native thread/executor lifecycle with a held, read-only wire proxy.

The retained environment fixture owns the real authenticated exec-server. This
draft forwards actual native bytes only. A WebSocket firewall rejects process,
filesystem and HTTP RPCs before forwarding, and controls only owned sockets.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time

from isolated_environment_fixture import Fixture as EnvironmentFixture, TOKEN


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
ALLOWED = {"initialize", "initialized", "environment/add", "environment/info",
           "environment/status", "thread/start", "thread/read", "thread/loaded/list"}
EXEC_ALLOWED = {"initialize", "initialized", "environment/info", "environment/status"}
ENVIRONMENTS = {"selected-环境λ", "unselected", "missing"}
MAX_FRAME = 65_536


class Fixture(EnvironmentFixture):
    def __init__(self, root, namespace):
        self.gate = threading.Event()
        self.workers, self.worker_lock = [], threading.Lock()
        self.accepted = 0
        super().__init__(root, namespace)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 320, "owned environment journal bound"
            self.journal["events"].append({"event": event, **fields})
            pending = self.root / "isolated-environment-journal.pending"
            pending.write_text(json.dumps(self.journal))
            pending.replace(self.root / "isolated-environment-journal.json")

    def remember(self, thread=None):
        thread = thread or threading.current_thread()
        with self.worker_lock:
            if thread not in self.workers:
                self.workers.append(thread)

    def configure(self):
        before = set(threading.enumerate())
        secret = super().configure()
        for thread in set(threading.enumerate()) - before:
            self.remember(thread)
        for name in ["app", "executor"]:
            path = self.root / name / "config.toml"
            text = path.read_text().replace("[features]\n", "[features]\n"
                "deferred_executor = true\nhooks = false\napps = false\n")
            path.write_text(text + "\n[analytics]\nenabled = false\n")
        return secret

    def environment(self, name):
        return {**super().environment(name), "CODEX_DISABLE_REMOTE_CONTROL": "1",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_TERMINAL_PROMPT": "0", "PYTHONDONTWRITEBYTECODE": "1"}

    def accept_proxy(self):
        self.remember()
        while not self.closed.is_set():
            try:
                downstream, _ = self.proxy.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            self.accepted += 1
            assert self.accepted <= 16, "owned executor connection bound"
            downstream.settimeout(0.1)
            with self.proxy_lock:
                self.connections.add(downstream)
            self.record("proxy_waiting", connection=self.accepted)
            thread = threading.Thread(target=self.connection,
                args=(downstream, self.accepted), daemon=True)
            self.remember(thread)
            thread.start()

    def read_exact(self, conn, size, deadline=None):
        data = b""
        while len(data) < size and not self.closed.is_set():
            if deadline is not None:
                assert time.monotonic() < deadline, "owned proxy frame deadline"
            try:
                block = conn.recv(size - len(data))
            except socket.timeout:
                continue
            if not block:
                raise EOFError
            data += block
        if len(data) != size:
            raise EOFError
        return data

    def headers(self, conn):
        data, deadline = b"", time.monotonic() + 10
        while not data.endswith(b"\r\n\r\n"):
            assert len(data) < 16_384, "owned upgrade header bound"
            data += self.read_exact(conn, 1, deadline)
        return data

    def frames(self, source, target, client, identity):
        count = 0
        while not self.closed.is_set():
            prefix = self.read_exact(source, 2)
            deadline = time.monotonic() + 5
            opcode, masked, size = prefix[0] & 15, bool(prefix[1] & 128), prefix[1] & 127
            assert prefix[0] & 128 and not prefix[0] & 112, "fragmented/compressed frame unqualified"
            assert masked == client and opcode in (1, 2, 8, 9, 10)
            extension = b""
            if size in (126, 127):
                extension = self.read_exact(source, 2 if size == 126 else 8, deadline)
                size = struct.unpack("!H" if size == 126 else "!Q", extension)[0]
            assert size <= MAX_FRAME and (opcode < 8 or size <= 125)
            mask = self.read_exact(source, 4, deadline) if masked else b""
            payload = self.read_exact(source, size, deadline)
            count += 1
            assert count <= 96, "owned exec-server frame count"
            if client and opcode in (1, 2):
                decoded = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
                wire = json.loads(decoded)
                method = wire.get("method")
                if method not in EXEC_ALLOWED:
                    self.record("forbidden_exec_rpc", method=method)
                    raise AssertionError("unapproved executor operation")
                assert TOKEN.encode() not in decoded
                self.record("exec_rpc", method=method, connection=identity, id=wire.get("id"))
            target.sendall(prefix + extension + mask + payload)
            if opcode == 8:
                return

    def connection(self, downstream, identity):
        upstream = None
        reverse = None
        try:
            deadline = time.monotonic() + 12
            while not self.gate.wait(0.01):
                if self.closed.is_set():
                    return
                assert time.monotonic() < deadline, "owned proxy gate deadline"
            if self.closed.is_set():
                return
            upstream = socket.create_connection(self.executor_address, timeout=2)
            upstream.settimeout(0.1)
            with self.proxy_lock:
                self.connections.add(upstream)
            request = self.headers(downstream)
            assert ("Authorization: Bearer " + TOKEN).lower().encode() in request.lower()
            upstream.sendall(request)
            response = self.headers(upstream)
            downstream.sendall(response)
            assert int(response.split(b"\r\n", 1)[0].split()[1]) == 101
            self.record("proxy_connected", connection=identity, bearer_verified=True)

            def back():
                try:
                    self.frames(upstream, downstream, False, identity)
                except (EOFError, OSError):
                    pass
                except Exception as error:
                    self.record("fixture_error", stage="executor-output", error_type=type(error).__name__)
                finally:
                    try:
                        downstream.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass

            reverse = threading.Thread(target=back, daemon=True)
            self.remember(reverse)
            reverse.start()
            self.frames(downstream, upstream, True, identity)
        except (EOFError, OSError):
            pass
        except Exception as error:
            self.record("fixture_error", stage="executor-input", error_type=type(error).__name__)
        finally:
            for conn in [downstream, upstream]:
                if conn is not None:
                    try:
                        conn.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    with self.proxy_lock:
                        self.connections.discard(conn)
                    conn.close()
            if reverse is not None:
                reverse.join(5)
                assert not reverse.is_alive()
            self.record("proxy_disconnected", connection=identity)

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
            action = control["action"]
            if action == "resume_proxy":
                self.gate.set()
            elif action in ("pause_proxy", "stop_executor"):
                self.gate.clear()
                self.disconnect()
                if action == "stop_executor":
                    self.executor.terminate()
                    self.executor.wait(timeout=5)
                    self.record("executor_stopped", pid=self.executor.pid)
                    # Let later metadata recovery see real connection refusal,
                    # rather than manufacturing a held-handshake timeout.
                    self.gate.set()
            else:
                self.record("fixture_error", stage="invalid-control")
                return
            self.record("control_completed", id=seen, action=action)

    def close(self):
        super().close()
        joined = {threading.current_thread()}
        while True:
            with self.worker_lock:
                workers = [worker for worker in self.workers if worker not in joined]
            if not workers:
                break
            for worker in workers:
                worker.join(5)
                assert not worker.is_alive(), "owned environment worker did not stop"
                joined.add(worker)
        for name in ["app", "executor"]:
            path = self.root / f"{name}-stderr.log"
            if path.exists():
                data = path.read_bytes()
                assert len(data) <= 262_144 and TOKEN.encode() not in data
        assert TOKEN not in (self.root / "isolated-environment-journal.json").read_text()
        self.record("resources_closed", children_reaped=all(c.poll() is not None for c in self.children),
                    workers_stopped=True, redaction_checked=True)


def validate(wire, fixture):
    root = fixture.root
    method, params = wire.get("method"), wire.get("params")
    assert method in ALLOWED
    if method == "environment/add":
        assert set(params) == {"environmentId", "execServerUrl", "authBearerToken", "connectTimeoutMs"}
        assert params["environmentId"] in ENVIRONMENTS - {"missing"}
        assert params["execServerUrl"] == fixture.url and params["connectTimeoutMs"] == 15_000
        assert params["authBearerToken"] == TOKEN
    elif method in ("environment/status", "environment/info"):
        assert params["environmentId"] in ENVIRONMENTS
    elif method == "thread/start":
        assert set(params) <= {"model", "modelProvider", "cwd", "sandbox", "approvalPolicy", "ephemeral", "environments"}
        assert params["model"] == "mock-model" and params["modelProvider"] == "fixture"
        assert params["cwd"] == str(root / "workspace") and params["sandbox"] == "read-only"
        assert params["approvalPolicy"] == "on-request" and params["ephemeral"] is False
        assert isinstance(params["environments"], list) and len(params["environments"]) <= 1
        for environment in params["environments"]:
            assert environment["environmentId"] in ENVIRONMENTS
            assert environment["cwd"] == str(root / "executor-workspace")
            roots = environment.get("runtimeWorkspaceRoots")
            assert roots is None or roots == [str(root / "executor-workspace")] * 2
    elif method == "thread/read":
        assert set(params) == {"threadId", "includeTurns"} and isinstance(params["includeTurns"], bool)


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    net, user = os.readlink("/proc/self/ns/net"), os.readlink("/proc/self/ns/user")
    assert net != args.parent_netns and user != args.parent_userns
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    assert os.getuid() == 0 and [link["ifname"] for link in links] == ["lo"]
    for family in [[], ["-6"]]:
        routes = json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
        for route in routes:
            assert route.get("dst") != "default" and route.get("dev") == "lo"
            assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback
    fixture = Fixture(args.root, {"parent": args.parent_netns, "child": net,
        "parent_user": args.parent_userns, "child_user": user, "interfaces": ["lo"],
        "default_route": False, "ipv6_default_route": False})
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
        secret = fixture.configure()
        fixture.start_executor(args.codex, secret)
        native = fixture.spawn(str(args.codex), ["app-server", "--listen", "stdio://"],
                               "app", args.root / "workspace")
        fixture.record("native_started", pid=native.pid, executor_pid=fixture.executor.pid,
            controller_pid=os.getpid(), namespace_owner_pid=os.getppid(), executor_url=fixture.url)
        controller = threading.Thread(target=fixture.controls, daemon=True)
        fixture.remember(controller)
        controller.start()

        def output():
            try:
                count = 0
                while line := native.stdout.readline(MAX_FRAME + 1):
                    count += 1
                    assert len(line.encode()) <= MAX_FRAME and line.endswith("\n") and count <= 128
                    assert TOKEN not in line
                    wire = json.loads(line)
                    fixture.record("native_output", method=wire.get("method"), id=wire.get("id"),
                                   error=wire.get("error"))
                    sys.stdout.write(line)
                    sys.stdout.flush()
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)
                native.terminate()

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.readline(16_385):
            count += 1
            assert len(line.encode()) <= 16_384 and line.endswith("\n") and count <= 64
            wire = json.loads(line)
            validate(wire, fixture)
            fixture.record("native_input", method=wire["method"], id=wire.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        fixture.close()
        if reader is not None:
            reader.join(5)
            assert not reader.is_alive()
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
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
