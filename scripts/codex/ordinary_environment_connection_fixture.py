#!/usr/bin/env python3
"""Owned native environment lifecycle with an opaque held/cut byte proxy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse


BINARY_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SELECTED = {"thread/environment/connected", "thread/environment/disconnected"}
MAX_LINE = 65_536
MAX_SELECTED = 8
MAX_SELECTED_BYTES = 524_288
MAX_JOURNAL = 160
YOLO = ["-c", 'approval_policy="never"', "-c", 'sandbox_mode="danger-full-access"',
        "-c", "features.plugins=false", "-c", "features.recommended_plugins=false"]


class Fixture:
    def __init__(self, root, binary):
        self.root = root
        self.binary = binary
        self.lock = threading.RLock()
        self.socket_lock = threading.Lock()
        self.worker_lock = threading.Lock()
        self.events = []
        self.processes = []
        self.reaped = set()
        self.workers = []
        self.proxy_sockets = set()
        self.sink_sockets = set()
        self.stopping = threading.Event()
        self.proxy_stopped = threading.Event()
        self.sink_stopped = threading.Event()
        self.gate = threading.Event()
        self.selected_count = 0
        self.selected_bytes = 0
        self.input_count = 0
        self.output_count = 0
        self.proxy_count = 0
        self.sink_count = 0
        self.failed = False
        self.close_control = None
        self.control_sequence = 0
        self.record("owner_started", pid=os.getpid())

    def record(self, event, **fields):
        with self.lock:
            if len(self.events) >= MAX_JOURNAL:
                raise RuntimeError("ordinary environment journal overflow")
            entry = {"captureId": len(self.events) + 1,
                     "monoNs": time.monotonic_ns(), "wallMs": time.time_ns() // 1_000_000,
                     "event": event, **fields}
            self.events.append(entry)
            temporary = self.root / "journal.pending"
            temporary.write_text(json.dumps({"events": self.events}, ensure_ascii=False))
            temporary.replace(self.root / "journal.json")
            return entry

    def fault(self, stage, error):
        with self.lock:
            if not self.failed:
                self.failed = True
                self.record("fixture_error", stage=stage, errorType=type(error).__name__)
        self.stopping.set()
        self.gate.set()

    def worker(self, name, action):
        def guarded():
            try:
                action()
            except Exception as error:
                self.fault(name, error)

        thread = threading.Thread(name=name, target=guarded)
        with self.worker_lock:
            if len(self.workers) >= 16:
                raise RuntimeError("ordinary environment worker overflow")
            self.workers.append(thread)
            thread.start()
        return thread

    def track(self, connection, group):
        with self.socket_lock:
            group.add(connection)
        return connection

    def close_socket(self, connection, group):
        try:
            connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()
        with self.socket_lock:
            group.discard(connection)

    def close_group(self, group):
        with self.socket_lock:
            connections = list(group)
        for connection in connections:
            self.close_socket(connection, group)

    def listener(self, group):
        listener = self.track(socket.socket(), group)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen(8)
        listener.settimeout(0.1)
        return listener

    def start_sink(self):
        self.sink_listener = self.listener(self.sink_sockets)
        address = self.sink_listener.getsockname()

        def handle(connection):
            try:
                connection.settimeout(1)
                if connection.recv(1):
                    with self.lock:
                        self.sink_count += 1
                        self.record("provider_request", count=self.sink_count)
                    connection.sendall(b"HTTP/1.1 503 Service Unavailable\r\n"
                                       b"Content-Length: 0\r\nConnection: close\r\n\r\n")
            except (OSError, TimeoutError):
                if not self.stopping.is_set():
                    raise
            finally:
                self.close_socket(connection, self.sink_sockets)

        def accept():
            accepted = 0
            while not self.sink_stopped.is_set() and not self.stopping.is_set():
                try:
                    connection, _ = self.sink_listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if self.sink_stopped.is_set() or self.stopping.is_set():
                        return
                    raise
                self.track(connection, self.sink_sockets)
                if self.sink_stopped.is_set() or self.stopping.is_set():
                    self.close_socket(connection, self.sink_sockets)
                    return
                accepted += 1
                if accepted > 4:
                    self.close_socket(connection, self.sink_sockets)
                    raise RuntimeError("ordinary environment sink connection overflow")
                self.worker(f"sink-{accepted}", lambda connection=connection: handle(connection))

        self.worker("sink-accept", accept)
        return f"http://{address[0]}:{address[1]}"

    def configure(self):
        for name in ["home", "app", "executor", "workspace", "executor-workspace", "tmp"]:
            (self.root / name).mkdir(exist_ok=True)
        endpoint = self.start_sink()
        catalog = self.root / "app" / "models.json"
        catalog.write_text(json.dumps({"models": [{
            "slug": "mock-model", "display_name": "Owned metadata-only environment fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned metadata-only fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]}))
        config = f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "ephemeral"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
chatgpt_base_url = "{endpoint}/backend-api"
openai_base_url = "{endpoint}/v1"
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[memories]
generate_memories = false
use_memories = false
[features]
deferred_executor = true
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
memories = false
[model_providers.fixture]
name = "Owned metadata-only fixture"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        for name in ["app", "executor"]:
            (self.root / name / "config.toml").write_text(config)
        runtime_value = secrets.token_urlsafe(32)
        self.runtime_file = self.root / "executor-runtime-value"
        self.runtime_file.write_text(runtime_value)
        return runtime_value

    def environment(self, name):
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(self.root / name),
                "TMPDIR": str(self.root / "tmp"), "SHELL": "/bin/sh",
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "NO_COLOR": "1",
                "RUST_LOG": "off", "CODEX_DISABLE_REMOTE_CONTROL": "1"}

    def spawn(self, name, args, cwd):
        process = subprocess.Popen([str(self.binary), *YOLO, *args],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, cwd=cwd,
                                   env=self.environment(name), bufsize=0)
        self.processes.append((name, process))
        return process

    def read_line(self, stream, deadline):
        result = bytearray()
        while len(result) <= MAX_LINE:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("ordinary environment listener deadline")
            ready, _, _ = select.select([stream], [], [], remaining)
            if not ready:
                raise TimeoutError("ordinary environment listener deadline")
            byte = os.read(stream.fileno(), 1)
            if not byte:
                raise RuntimeError("ordinary environment listener exited")
            result.extend(byte)
            if byte == b"\n":
                return bytes(result)
        raise RuntimeError("ordinary environment listener line overflow")

    def start_executor(self, runtime_value):
        self.executor = self.spawn("executor", ["exec-server", "--listen", "ws://127.0.0.1:0",
            "--ws-auth", "capability-token", "--ws-token-file", str(self.runtime_file)],
            self.root / "executor-workspace")
        deadline = time.monotonic() + 10
        for _ in range(8):
            line = self.read_line(self.executor.stdout, deadline)
            if line.startswith(b"ws://"):
                parsed = urlparse(line.decode().strip())
                if parsed.scheme != "ws" or parsed.hostname != "127.0.0.1" or not parsed.port:
                    raise RuntimeError("ordinary environment listener address")
                self.executor_address = (parsed.hostname, parsed.port)
                break
        else:
            raise RuntimeError("ordinary environment listener readiness")
        self.record("executor_started", pid=self.executor.pid)
        self.proxy_listener = self.listener(self.proxy_sockets)
        address = self.proxy_listener.getsockname()
        self.worker("proxy-accept", self.accept_proxy)
        setup = {"execServerUrl": f"ws://{address[0]}:{address[1]}",
                 "authBearerToken": runtime_value}
        temporary = self.root / "connection-setup.pending"
        temporary.write_text(json.dumps(setup))
        temporary.replace(self.root / "connection-setup.json")

    def accept_proxy(self):
        while not self.proxy_stopped.is_set() and not self.stopping.is_set():
            try:
                downstream, _ = self.proxy_listener.accept()
            except socket.timeout:
                continue
            except OSError:
                if self.proxy_stopped.is_set() or self.stopping.is_set():
                    return
                raise
            self.track(downstream, self.proxy_sockets)
            if self.proxy_stopped.is_set() or self.stopping.is_set():
                self.close_socket(downstream, self.proxy_sockets)
                return
            self.proxy_count += 1
            if self.proxy_count > 8:
                self.close_socket(downstream, self.proxy_sockets)
                raise RuntimeError("ordinary environment proxy connection overflow")
            identity = self.proxy_count
            self.record("proxy_held", connection=identity)
            self.worker(f"proxy-{identity}",
                        lambda downstream=downstream, identity=identity:
                        self.forward(downstream, identity))

    def forward(self, downstream, identity):
        upstream = None
        try:
            deadline = time.monotonic() + 20
            while not self.gate.wait(0.05):
                if self.stopping.is_set() or self.proxy_stopped.is_set():
                    return
                if time.monotonic() >= deadline:
                    raise TimeoutError("ordinary environment release deadline")
            if self.stopping.is_set() or self.proxy_stopped.is_set():
                return
            upstream = self.track(socket.create_connection(self.executor_address, timeout=2),
                                  self.proxy_sockets)
            downstream.settimeout(1)
            upstream.settimeout(1)
            self.record("proxy_forwarding", connection=identity)
            total = 0
            while not self.stopping.is_set() and not self.proxy_stopped.is_set():
                readable, _, _ = select.select([downstream, upstream], [], [], 0.1)
                for source in readable:
                    data = source.recv(MAX_LINE)
                    if not data:
                        return
                    total += len(data)
                    if total > 1_048_576:
                        raise RuntimeError("ordinary environment proxy byte overflow")
                    target = upstream if source is downstream else downstream
                    target.sendall(data)
        except (OSError, ValueError):
            if not self.stopping.is_set() and not self.proxy_stopped.is_set():
                raise
        finally:
            self.close_socket(downstream, self.proxy_sockets)
            if upstream is not None:
                self.close_socket(upstream, self.proxy_sockets)
            self.record("proxy_connection_closed", connection=identity)

    def output(self):
        while True:
            line = self.native.stdout.readline(MAX_LINE + 1)
            if not line:
                if not self.stopping.is_set():
                    raise RuntimeError("ordinary environment app-server exited")
                return
            self.output_count += 1
            if len(line) > MAX_LINE or not line.endswith(b"\n") or self.output_count > 96:
                raise RuntimeError("ordinary environment native output overflow")
            wire = json.loads(line)
            method = wire.get("method")
            self.record("native_output", method=method,
                        kind="notification" if method else "response")
            if method in SELECTED:
                self.selected_count += 1
                self.selected_bytes += len(line)
                if self.selected_count > MAX_SELECTED or self.selected_bytes > MAX_SELECTED_BYTES:
                    raise RuntimeError("ordinary environment selected capture overflow")
                self.record("original_notification", method=method, encoded=line.decode("utf-8"))
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()

    def reap(self, name, process, deadline):
        if process.poll() is None:
            try:
                process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        if name not in self.reaped:
            self.reaped.add(name)
            self.record("owned_process_exit", name=name, pid=process.pid,
                        exitCode=process.returncode)

    def join_workers(self, prefix=None):
        deadline = time.monotonic() + 5
        joined = {threading.current_thread()}
        while True:
            with self.worker_lock:
                workers = [w for w in self.workers if w not in joined
                           and (prefix is None or w.name.startswith(prefix))]
            if not workers:
                return
            for worker in workers:
                worker.join(max(0, deadline - time.monotonic()))
                if worker.is_alive():
                    raise RuntimeError("ordinary environment worker did not stop")
                joined.add(worker)

    def stop_executor(self):
        if self.executor.poll() is None:
            self.executor.terminate()
        self.proxy_stopped.set()
        self.gate.set()
        self.close_group(self.proxy_sockets)
        self.reap("executor", self.executor, time.monotonic() + 5)
        self.join_workers("proxy")
        self.record("executor_stopped", pid=self.executor.pid)

    def controls(self):
        seen = None
        while not self.stopping.wait(0.01):
            path = self.root / "control.json"
            if not path.exists():
                continue
            raw = path.read_bytes()
            if len(raw) > 4096:
                raise RuntimeError("ordinary environment control overflow")
            control = json.loads(raw)
            identity, sequence, action = control["id"], control["sequence"], control["action"]
            if identity == seen:
                continue
            if sequence != self.control_sequence + 1 or sequence > 3:
                raise RuntimeError("ordinary environment control sequence")
            seen = identity
            self.control_sequence = sequence
            self.record("control_started", id=identity, sequence=sequence, action=action)
            if action == "release_executor_connection":
                self.gate.set()
            elif action == "stop_executor":
                self.stop_executor()
            elif action == "close":
                self.close_control = control
                self.stopping.set()
                self.gate.set()
                return
            else:
                raise RuntimeError("ordinary environment unknown control")
            self.record("control_completed", id=identity, sequence=sequence, action=action)

    def run(self):
        runtime_value = self.configure()
        self.start_executor(runtime_value)
        self.native = self.spawn("app", ["app-server", "--listen", "stdio://"],
                                 self.root / "workspace")
        self.record("native_started", pid=self.native.pid, executorPid=self.executor.pid,
                    controllerPid=os.getpid())
        self.worker("native-output", self.output)
        self.worker("controls", self.controls)
        pending = bytearray()
        while not self.stopping.is_set():
            readable, _, _ = select.select([sys.stdin.buffer], [], [], 0.1)
            if not readable:
                continue
            chunk = os.read(sys.stdin.fileno(), MAX_LINE)
            if not chunk:
                return
            pending.extend(chunk)
            if len(pending) > MAX_LINE:
                raise RuntimeError("ordinary environment native input overflow")
            while b"\n" in pending:
                line, _, rest = pending.partition(b"\n")
                pending = bytearray(rest)
                self.input_count += 1
                if self.input_count > 32:
                    raise RuntimeError("ordinary environment request count overflow")
                wire = json.loads(line)
                self.record("native_input", method=wire.get("method"))
                self.native.stdin.write(line + b"\n")
                self.native.stdin.flush()

    def close(self):
        self.stopping.set()
        self.proxy_stopped.set()
        self.sink_stopped.set()
        self.gate.set()
        self.close_group(self.proxy_sockets)
        self.close_group(self.sink_sockets)
        for _, process in self.processes:
            if process.poll() is None:
                process.terminate()
        deadline = time.monotonic() + 5
        for name, process in self.processes:
            self.reap(name, process, deadline)
        self.join_workers()
        for _, process in self.processes:
            for stream in [process.stdin, process.stdout]:
                if stream is not None:
                    stream.close()
        with self.worker_lock:
            live_workers = sum(worker.is_alive() for worker in self.workers)
        with self.socket_lock:
            live_sockets = len(self.proxy_sockets) + len(self.sink_sockets)
        self.record("resources_closed", childrenReaped=all(p.poll() is not None for _, p in self.processes),
                    liveWorkers=live_workers, liveSockets=live_sockets,
                    providerRequests=self.sink_count)
        if self.close_control is not None:
            self.record("control_completed", id=self.close_control["id"],
                        sequence=self.close_control["sequence"], action="close")
        self.record("owner_closed", failed=self.failed)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    args = parser.parse_args()
    binary = args.codex.resolve()
    if hashlib.sha256(binary.read_bytes()).hexdigest() != BINARY_SHA:
        raise RuntimeError("immutable ordinary environment binary mismatch")
    fixture = Fixture(args.root, binary)
    signal.signal(signal.SIGTERM, lambda *_: fixture.stopping.set())
    signal.signal(signal.SIGINT, lambda *_: fixture.stopping.set())
    try:
        fixture.run()
    except Exception as error:
        fixture.fault("controller", error)
    finally:
        try:
            fixture.close()
        except Exception as error:
            fixture.fault("close", error)
    return 1 if fixture.failed else 0


if __name__ == "__main__":
    sys.exit(main())
