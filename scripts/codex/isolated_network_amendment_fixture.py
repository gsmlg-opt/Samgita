#!/usr/bin/env python3
"""Draft real native proxy approval fixture; all peers and commands are owned.

This file has received static review only. A private mount/user/net namespace,
read-only child managed configuration and the native nested sandbox must work;
there is no debug config override, sandbox fallback or external destination.
"""
import argparse
import ctypes
import errno
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit

BINARY_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
BWRAP_SHA = "77360cb751ccedc5971391444ac86a8a33c15b04d6b4a6fe45f5d25496e62c4c"
REQUIREMENTS = '''[experimental_network]
enabled = true
http_port = 0
socks_port = 0
allow_upstream_proxy = false
allow_local_binding = true

[experimental_network.domains]
"127.0.0.2" = "allow"
'''
SUCCESS = b"owned network destination response"
CLEANUP_SECONDS = 0.75
SERVER_POLL_SECONDS = 0.02
STDERR_LIMIT = 65_536


def write_json(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def fixed(command, timeout=4):
    return subprocess.check_output(command, timeout=timeout, stderr=subprocess.STDOUT).decode()


def isolate(args):
    current = {name: os.readlink(f"/proc/self/ns/{name}") for name in ["user", "mnt", "net"]}
    for name in current:
        assert current[name] != getattr(args, "parent_" + name), "BLOCKED_ENV: unchanged " + name
    assert os.geteuid() == 0, "BLOCKED_ENV: private mapped root required"
    fixed(["ip", "link", "set", "lo", "up"])
    interfaces = json.loads(fixed(["ip", "-j", "link", "show"]))
    assert [row["ifname"] for row in interfaces] == ["lo"]
    for family in ["-4", "-6"]:
        routes = json.loads(fixed(["ip", family, "-j", "route", "show", "table", "all"]))
        assert all(row.get("dev") == "lo" and row.get("dst") not in ["default", "0.0.0.0/0", "::/0"]
                   for row in routes), "BLOCKED_ENV: nonlocal route"
        assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
                   for row in routes)
    return {"namespaces": current,
            "parents": {name: getattr(args, "parent_" + name) for name in current},
            "interfaces": ["lo"], "default_route": False, "ipv6_default_route": False}


def child_requirements(root):
    # Must be called only after isolate() verifies the new mount namespace.
    source = root / "system"
    assert source.is_dir() and not source.is_symlink()
    (source / "requirements.toml").write_text(REQUIREMENTS)
    fixed(["mount", "--make-rprivate", "/"])
    fixed(["mount", "-t", "tmpfs", "-o", "mode=0755,nodev,nosuid,noexec", "tmpfs", "/etc"])
    Path("/etc/codex").mkdir()
    fixed(["mount", "--bind", str(source), "/etc/codex"])
    fixed(["mount", "-o", "remount,bind,ro,nodev,nosuid,noexec", "/etc/codex"])
    assert Path("/etc/codex/requirements.toml").read_text() == REQUIREMENTS
    rows = [row.split() for row in Path("/proc/self/mountinfo").read_text().splitlines()]
    mounted = [row for row in rows if row[4] == "/etc/codex"]
    assert len(mounted) == 1 and "ro" in mounted[0][5].split(",")
    assert any(row[4] == "/etc" and "tmpfs" in row for row in rows)
    return {"requirements_sha256": hashlib.sha256(REQUIREMENTS.encode()).hexdigest(),
            "requirements_path": "/etc/codex/requirements.toml", "requirements_read_only": True,
            "private_etc_tmpfs": True}


def probe(args):
    # Native exec_command runs this exact fixed mode under its real sandbox.
    target = urlsplit(args.target)
    assert target.scheme == "http" and target.hostname == "127.0.0.3"
    assert target.path == "/owned-network-probe" and target.port
    assert not target.username and not target.password and not target.query and not target.fragment
    assert os.readlink("/proc/self/ns/net") != args.outer_net
    try:
        connection = socket.create_connection((target.hostname, target.port), timeout=2)
    except OSError as error:
        assert error.errno in [errno.ECONNREFUSED, errno.ENETUNREACH, errno.EPERM, errno.EACCES,
                               errno.EHOSTUNREACH], error
    else:
        connection.close()
        raise AssertionError("native sandbox permitted direct origin access")
    print("owned direct access blocked", flush=True)
    proxy = urlsplit(os.environ["HTTP_PROXY"])
    assert proxy.scheme == "http" and ipaddress.ip_address(proxy.hostname).is_loopback and proxy.port
    assert not proxy.username and not proxy.password
    request = f"GET {args.target} HTTP/1.0\r\nHost: {target.netloc}\r\nConnection: close\r\n\r\n"
    with socket.create_connection((proxy.hostname, proxy.port), timeout=5) as connection:
        connection.settimeout(15)
        connection.sendall(request.encode("ascii"))
        result = b""
        while len(result) <= 65_536:
            part = connection.recv(4096)
            if not part:
                break
            result += part
    assert len(result) <= 65_536 and b" 200 " in result.split(b"\r\n", 1)[0]
    assert result.split(b"\r\n\r\n", 1)[1] == SUCCESS
    print("owned network request succeeded", flush=True)


class TrackedServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def __init__(self, address, handler):
        self.registry_lock = threading.Lock()
        self.closing = False
        self.sockets, self.workers = set(), set()
        super().__init__(address, handler)
        self.thread = threading.Thread(target=self.serve_forever,
            kwargs={"poll_interval": SERVER_POLL_SECONDS}, daemon=True)

    def process_request(self, request, address):
        request.settimeout(0.2)

        def handle():
            try:
                self.process_request_thread(request, address)
            finally:
                with self.registry_lock:
                    self.sockets.discard(request)
                    self.workers.discard(threading.current_thread())

        with self.registry_lock:
            if self.closing:
                self.shutdown_request(request)
                return
            worker = threading.Thread(target=handle, daemon=True)
            self.sockets.add(request)
            self.workers.add(worker)
            worker.start()

    def start(self):
        self.thread.start()

    def stop(self, deadline):
        with self.registry_lock:
            self.closing = True
            sockets = list(self.sockets)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        self.shutdown()
        self.server_close()
        self.thread.join(timeout=max(0, deadline - time.monotonic()))
        with self.registry_lock:
            workers = list(self.workers)
        for worker in workers:
            worker.join(timeout=max(0, deadline - time.monotonic()))
        with self.registry_lock:
            return {"stopped": not self.thread.is_alive(), "workers": len(self.workers),
                    "sockets": len(self.sockets)}


class StderrCapture:
    def __init__(self, path):
        self.path = path
        self.file = path.open("wb", buffering=0)
        self.seen = 0
        self.eof = False

    def drain(self, pipe):
        # Bound each pass as well as stored bytes; no capture worker can outlive teardown.
        for _ in range(16):
            try:
                part = os.read(pipe.fileno(), 4096)
            except BlockingIOError:
                break
            if not part:
                self.eof = True
                break
            remaining = max(0, STDERR_LIMIT - self.seen)
            self.file.write(part[:remaining])
            self.seen += len(part)

    def metadata(self):
        return {"stderr_path": str(self.path), "stderr_bytes_seen": self.seen,
                "stderr_truncated": self.seen > STDERR_LIMIT}


def signal_group(group, signum):
    try:
        os.killpg(group, signum)
    except ProcessLookupError:
        pass


def group_exists(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def native_exit_code(native):
    # Keep the leader waitable until the final owned-group signal prevents PGID reuse.
    status = os.waitid(os.P_PID, native.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    if status is None:
        return None
    return status.si_status if status.si_code == os.CLD_EXITED else -status.si_status


def owned_children():
    return Path(f"/proc/self/task/{os.getpid()}/children").read_text().split()


def reap_owned_children(native):
    # Codex/bwrap creates new sessions. Reap actual adopted children irrespective
    # of PGID; never signal them or consume the leader behind Popen's back.
    for child in owned_children():
        pid = int(child)
        if pid == native.pid:
            continue
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass


class Provider:
    def __init__(self, root, target, outer_net):
        self.root, self.target, self.outer_net = root, target, outer_net
        self.requests, self.calls = [], {}
        self.lock = threading.Lock()
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                self.send_response(404)
                self.end_headers()

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                assert self.path == "/v1/responses" and 0 < size <= 4_194_304
                body = json.loads(self.rfile.read(size))
                markers = [part["text"] for item in body.get("input", [])
                           if item.get("role") == "user" for part in item.get("content", [])
                           if part.get("type") == "input_text"
                           and part.get("text") in ["synthetic:network:1", "synthetic:network:2"]]
                assert markers, "unapproved synthetic turn"
                marker = markers[-1]
                with fixture.lock:
                    fixture.requests.append(body)
                    write_json(root / "requests.json", fixture.requests)
                    count = fixture.calls.get(marker, 0) + 1
                    fixture.calls[marker] = count
                    index = len(fixture.requests)
                assert count <= 2
                if count == 1:
                    command = shlex.join([str(Path(sys.executable).resolve()), "-I", "-S",
                        str(Path(__file__).resolve()), "--probe", "--target", target,
                        "--outer-net", outer_net])
                    item = {"type": "function_call", "name": "exec_command",
                            "call_id": "owned-network-" + marker.rsplit(":", 1)[1],
                            "arguments": json.dumps({"cmd": command, "workdir": str(root / "workspace"),
                                "shell": str(root / "bin/sh"), "login": False, "yield_time_ms": 1000})}
                    write_json(root / "command.json", {"command": command})
                else:
                    item = {"type": "message", "role": "assistant", "id": f"owned-final-{index}",
                            "content": [{"type": "output_text", "text": "Owned network turn finished"}]}
                identity = f"owned-response-{index}"
                events = [{"type": "response.created", "response": {"id": identity}},
                          {"type": "response.output_item.done", "item": item},
                          {"type": "response.completed", "response": {"id": identity,
                              "usage": {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0,
                                        "input_tokens_details": None, "output_tokens_details": None}}}]
                payload = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                                  for event in events).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        self.server = TrackedServer(("127.0.0.1", 0), Handler)

    def start(self):
        self.server.start()


def configure(root, provider):
    catalog = root / "codex/models.json"
    write_json(catalog, {"models": [{"slug": "mock-model", "display_name": "Owned network fixture",
        "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
        "supported_in_api": True, "priority": 1, "model_messages": {
            "instructions_template": "Synthetic network qualification only."}, "support_verbosity": False,
        "truncation_policy": {"mode": "bytes", "limit": 10000}, "input_modalities": ["text"],
        "experimental_supported_tools": []}]})
    url = f"http://127.0.0.1:{provider.server.server_port}"
    (root / "codex/config.toml").write_text(f'''
model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
chatgpt_base_url = "{url}"
openai_base_url = "{url}/v1"
[features]
network_proxy = true
unified_exec = true
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
hooks = false
remote_models = false
[model_providers.fixture]
name = "Owned synthetic network provider"
base_url = "{url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')


def run(args):
    root, codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert root.name.startswith("samgita-network-amendment-") and not args.root.is_symlink()
    assert hashlib.sha256(codex.read_bytes()).hexdigest() == BINARY_SHA
    sidecar = codex.parent / "codex-resources/bwrap"
    assert sidecar.is_file() and not sidecar.is_symlink() and os.access(sidecar, os.X_OK)
    assert hashlib.sha256(sidecar.read_bytes()).hexdigest() == BWRAP_SHA
    assert all(shutil.which(tool) for tool in ["unshare", "ip", "mount"])
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--mount", "--net", "--fork",
            "--kill-child=TERM", sys.executable, "-I", str(Path(__file__).resolve()), *sys.argv[1:],
            "--inside", "--parent-user", os.readlink("/proc/self/ns/user"),
            "--parent-mnt", os.readlink("/proc/self/ns/mnt"),
            "--parent-net", os.readlink("/proc/self/ns/net")])
    proof = isolate(args)
    proof.update(child_requirements(root))
    hits, lock = [], threading.Lock()

    class Origin(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            assert self.path == "/owned-network-probe"
            with lock:
                hits.append({"path": self.path, "host": self.headers.get("Host")})
                write_json(root / "origin-hits.json", hits)
            self.send_response(200)
            self.send_header("Content-Length", str(len(SUCCESS)))
            self.end_headers()
            self.wfile.write(SUCCESS)

    # Adopt only this fixture's descendants; enumerate actual children before reaping.
    assert ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0, \
        "BLOCKED_ENV: child subreaper unavailable"
    origin = TrackedServer(("127.0.0.3", 0), Origin)
    origin.start()
    target = f"http://127.0.0.3:{origin.server_port}/owned-network-probe"
    provider = Provider(root, target, proof["namespaces"]["net"])
    provider.start()
    native = None
    capture = StderrCapture(root / "native-stderr.log")

    def terminate(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        configure(root, provider)
        env = {"PATH": str(root / "bin"), "HOME": str(root / "home"),
               "CODEX_HOME": str(root / "codex"), "TMPDIR": str(root / "tmp"),
               "SHELL": str(root / "bin/sh"), "CODEX_DISABLE_REMOTE_CONTROL": "1",
               "RUST_LOG": "off", "NO_COLOR": "1", "PYTHONDONTWRITEBYTECODE": "1"}
        native = subprocess.Popen([str(codex), "app-server", "--listen", "unix://" + str(root / "native.sock")],
            cwd=root / "workspace", env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, start_new_session=True)
        os.set_blocking(native.stderr.fileno(), False)
        deadline = time.monotonic() + 8
        while not (root / "native.sock").exists():
            capture.drain(native.stderr)
            returncode = native_exit_code(native)
            if returncode is not None or time.monotonic() >= deadline:
                capture.drain(native.stderr)
                failure = {"reason": "native exited" if returncode is not None else "startup deadline",
                           "returncode": returncode, **capture.metadata()}
                write_json(root / "startup-failure.json", failure)
                raise AssertionError("BLOCKED_ENV: " + json.dumps(failure))
            time.sleep(0.01)
        write_json(root / "state.json", {**proof, "controller_pid": os.getpid(), "native_pid": native.pid,
            "namespace_owner_pid": os.getppid(), "ready": True, "target": target})
        while True:
            readers = [sys.stdin.buffer] + ([] if capture.eof else [native.stderr])
            ready, _, _ = select.select(readers, [], [], SERVER_POLL_SECONDS)
            capture.drain(native.stderr)
            if sys.stdin.buffer in ready:
                assert not os.read(sys.stdin.fileno(), 1), "fixture accepts no mutation control"
                break
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_started = time.monotonic()
        deadline = cleanup_started + CLEANUP_SECONDS
        if native:
            signal_group(native.pid, signal.SIGTERM)
        provider_state = provider.server.stop(deadline)
        origin_state = origin.stop(deadline)
        if native:
            grace = min(deadline, cleanup_started + 0.15)
            while time.monotonic() < grace and native_exit_code(native) is None:
                capture.drain(native.stderr)
                time.sleep(0.005)
            # The unreaped leader reserves this owned group through its last signal.
            signal_group(native.pid, signal.SIGKILL)
            while time.monotonic() < deadline:
                capture.drain(native.stderr)
                if native.returncode is None and native_exit_code(native) is not None:
                    native.wait(timeout=0)
                reap_owned_children(native)
                if native.returncode is not None and not owned_children():
                    break
                time.sleep(0.005)
            capture.drain(native.stderr)
            native.stderr.close()
        capture.file.close()
        children = owned_children()
        child_states = []
        for child in children:
            try:
                fields = Path(f"/proc/{child}/stat").read_text().rsplit(") ", 1)[1].split()
            except FileNotFoundError:
                continue
            child_states.append({"pid": int(child), "state": fields[0], "parent": int(fields[1]),
                                 "group": int(fields[2]), "session": int(fields[3]),
                                 "start_ticks": int(fields[19])})
        closed = {"native_reaped": native is None or native.returncode is not None,
                  "native_group_gone": native is None or not group_exists(native.pid),
                  "owned_children_remaining": children, "owned_child_states": child_states,
                  "provider": provider_state, "origin": origin_state,
                  "cleanup_seconds": time.monotonic() - cleanup_started, **capture.metadata()}
        write_json(root / "closed.json", closed)
        assert closed["native_reaped"] and closed["native_group_gone"] and not children, closed
        assert provider_state == origin_state == {"stopped": True, "workers": 0, "sockets": 0}, closed
        assert closed["cleanup_seconds"] <= CLEANUP_SECONDS, closed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--codex", type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-user")
    parser.add_argument("--parent-mnt")
    parser.add_argument("--parent-net")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--target")
    parser.add_argument("--outer-net")
    args = parser.parse_args()
    if args.probe:
        assert args.target and args.outer_net and not args.inside and args.root is None and args.codex is None
        return probe(args)
    assert args.root and args.codex and not args.target and not args.outer_net
    return run(args)


if __name__ == "__main__":
    main()
