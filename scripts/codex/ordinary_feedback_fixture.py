#!/usr/bin/env python3
"""Owned ordinary feedback dependency; never emits app-server frames.

Standard-library only. Native stdio bytes pass
through unchanged. CONNECT, child CA and private-loopback setup are fixed transport
setup, not TLS/header/auth/isolation/permission tests. No historical helper imports.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import zlib


BINARY_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SENTRY_HOST = "o33249.ingest.us.sentry.io"
SENTRY_PATH = "/api/4510195390611458/envelope/"
BASE = "Owned  ordinary\r\nfeedback base\tinstructions λ 🙂."
MARKER = "Owned ordinary feedback context λ 🙂."
ANSWER = "Owned ordinary feedback turn completed λ 🙂."
MAX_WIRE = 262_144
MAX_BODY = 1_048_576
MAX_EVENT = 262_144
MAX_JOURNAL = 3_145_728


def atomic_json(path, value):
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    if len(data) > MAX_JOURNAL:
        raise ValueError("ordinary feedback journal bound")
    pending = path.with_suffix(".pending")
    pending.write_bytes(data)
    pending.replace(path)


def certificates(root):
    directory = root / "tls"
    directory.mkdir()
    (directory / "extensions.cnf").write_text(
        f"subjectAltName=DNS:{SENTRY_HOST}\nbasicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
    commands = [
        ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
         "-subj", "/CN=Owned ordinary feedback dependency", "-addext", "basicConstraints=critical,CA:TRUE",
         "-keyout", str(directory / "ca.key"), "-out", str(directory / "ca.pem")],
        ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
         "-subj", f"/CN={SENTRY_HOST}", "-keyout", str(directory / "server.key"),
         "-out", str(directory / "server.csr")],
        ["x509", "-req", "-in", str(directory / "server.csr"), "-CA", str(directory / "ca.pem"),
         "-CAkey", str(directory / "ca.key"), "-CAcreateserial", "-days", "1", "-sha256",
         "-extfile", str(directory / "extensions.cnf"), "-out", str(directory / "server.pem")],
    ]
    for arguments in commands:
        subprocess.run(["openssl", *arguments], check=True, timeout=10,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def request_head(stream):
    line = stream.readline(2049)
    if len(line) > 2048 or not line.endswith(b"\r\n"):
        raise ValueError("ordinary request-line framing bound")
    used, fields = len(line), {}
    for _ in range(33):
        part = stream.readline(2049)
        used += len(part)
        if used > 16_384 or len(part) > 2048 or not part.endswith(b"\r\n"):
            raise ValueError("ordinary request-head framing bound")
        if part == b"\r\n":
            return line[:-2].decode("ascii"), fields
        name, value = part[:-2].decode("ascii").split(":", 1)
        fields[name.lower()] = value.strip()
    raise ValueError("ordinary request-head count bound")


def request_body(stream, fields, limit):
    size = int(fields.get("content-length", "0"))
    if not 0 < size <= limit:
        raise ValueError("ordinary request-body size bound")
    body = stream.read(size)
    if len(body) != size:
        raise ValueError("ordinary request-body framing")
    return body


def decode_envelope(body, encoding):
    if encoding == "gzip":
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        decoded = decoder.decompress(body, MAX_EVENT + 1)
        if not decoder.eof or decoder.unconsumed_tail or decoder.unused_data:
            raise ValueError("ordinary decoded envelope bound")
    elif encoding in (None, "identity"):
        decoded = body
    else:
        raise ValueError("ordinary unsupported envelope encoding")
    if not 0 < len(decoded) <= MAX_EVENT:
        raise ValueError("ordinary decoded envelope size bound")
    return decoded


class OrdinaryFeedback:
    def __init__(self, root):
        self.root = root
        self.lock = threading.RLock()
        self.closing = threading.Event()
        self.sockets = set()
        self.events = []
        self.connections = 0
        self.model_calls = 0
        self.uploads = 0
        self.servers = []
        self.threads = []
        self.record("fixture_started", pid=os.getpid(), namespace_owner_pid=os.getppid())
        fixture = self

        class Server(socketserver.ThreadingTCPServer):
            daemon_threads = False
            block_on_close = True

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="dependency", kind=sys.exc_info()[0].__name__)

        class Handler(socketserver.BaseRequestHandler):
            feedback = False

            def handle(self):
                connection = self.request
                connection.settimeout(5)
                with fixture.lock:
                    fixture.connections += 1
                    if fixture.connections > 8:
                        raise ValueError("ordinary connection count bound")
                    fixture.sockets.add(connection)
                try:
                    with connection.makefile("rb") as stream:
                        line, fields = request_head(stream)
                        if not self.feedback:
                            body = request_body(stream, fields, MAX_BODY)
                    if self.feedback:
                        # The official fixed HTTPS destination is consumed locally.
                        # No upstream socket is opened and no transport/header assertion is made.
                        connection.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                        wrapped = fixture.context.wrap_socket(connection, server_side=True)
                        with fixture.lock:
                            fixture.sockets.discard(connection)
                            fixture.sockets.add(wrapped)
                        connection = wrapped
                        with connection.makefile("rb") as stream:
                            line, fields = request_head(stream)
                            body = request_body(stream, fields, MAX_EVENT)
                        fixture.feedback(connection, line, body, fields.get("content-encoding"))
                    else:
                        fixture.model(connection, line, body)
                finally:
                    with fixture.lock:
                        fixture.sockets.discard(connection)
                    connection.close()

        class FeedbackHandler(Handler):
            feedback = True

        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.set_alpn_protocols(["http/1.1"])
        self.context.load_cert_chain(root / "tls/server.pem", root / "tls/server.key")
        try:
            for handler in (Handler, FeedbackHandler):
                server = Server(("127.0.0.1", 0), handler)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                self.servers.append(server)
                self.threads.append(thread)
                thread.start()
        except BaseException:
            self.close()
            raise

    def record(self, event, **fields):
        with self.lock:
            if len(self.events) >= 64:
                raise ValueError("ordinary journal event count bound")
            self.events.append({"event": event, **fields})
            atomic_json(self.root / "ordinary-feedback-journal.json", {"events": self.events})

    def model(self, connection, line, body):
        if line != "POST /v1/responses HTTP/1.1":
            self.record("unexpected_model_request", line=line)
            connection.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            return
        request = json.loads(body)
        with self.lock:
            self.model_calls += 1
            index = self.model_calls
        if index != 1:
            raise ValueError("ordinary single model request bound")
        self.record("model_request", sequence=index, raw=body.decode("utf-8"), request=request)
        identity = "owned-ordinary-feedback-response"
        item = {"type": "message", "role": "assistant", "id": "owned-ordinary-feedback-answer",
                "content": [{"type": "output_text", "text": ANSWER}]}
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": item},
            {"type": "response.completed", "response": {"id": identity, "usage": {
                "input_tokens": 0, "input_tokens_details": None, "output_tokens": 0,
                "output_tokens_details": None, "total_tokens": 0}}},
        ]
        response = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                           for event in events).encode()
        connection.sendall((f"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
                            f"Content-Length: {len(response)}\r\nConnection: close\r\n\r\n").encode()
                           + response)
        self.record("model_response_sent", sequence=index)

    def feedback(self, connection, line, body, encoding):
        if line != f"POST {SENTRY_PATH} HTTP/1.1":
            self.record("unexpected_feedback_request", line=line)
            connection.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            return
        decoded = decode_envelope(body, encoding)
        with self.lock:
            self.uploads += 1
            index = self.uploads
        if index > 2:
            raise ValueError("ordinary two explicit feedback requests bound")
        # Original decoded native bytes are the oracle input. No expected tags,
        # prompt hash, thread ID or report identity are manufactured by the peer.
        self.record("feedback_consumed", sequence=index, raw=decoded.decode("utf-8"),
                    size=len(decoded), sha256=hashlib.sha256(decoded).hexdigest(),
                    encoded_size=len(body), encoded_sha256=hashlib.sha256(body).hexdigest())
        connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        self.record("feedback_response_sent", sequence=index)

    def configure(self):
        codex = self.root / "codex"
        catalog = codex / "models.json"
        atomic_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned ordinary feedback model",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": BASE}, "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000}, "experimental_supported_tools": []}]})
        model = f"http://127.0.0.1:{self.servers[0].server_address[1]}"
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "ephemeral"
mcp_oauth_credentials_store = "file"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{model}"
openai_base_url = "{model}/v1"
[feedback]
enabled = true
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
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
codex_hooks = false
shell_snapshot = false
memories = false
[model_providers.fixture]
name = "Owned ordinary feedback model"
base_url = "{model}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        proxy = f"http://127.0.0.1:{self.servers[1].server_address[1]}"
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(codex),
                "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"], "SHELL": "/bin/sh",
                "HTTPS_PROXY": proxy, "https_proxy": proxy,
                "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost",
                "SSL_CERT_FILE": str(self.root / "tls/ca.pem"),
                "NO_COLOR": "1", "RUST_LOG": "off", "CODEX_DISABLE_REMOTE_CONTROL": "1",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_TERMINAL_PROMPT": "0", "PYTHONDONTWRITEBYTECODE": "1"}

    def close(self):
        self.closing.set()
        for server, thread in zip(self.servers, self.threads):
            if thread.ident is not None:
                server.shutdown()
        with self.lock:
            sockets = list(self.sockets)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        for server in self.servers:
            server.server_close()
        for thread in self.threads:
            if thread.ident is None:
                continue
            thread.join(5)
            if thread.is_alive():
                raise RuntimeError("ordinary dependency thread shutdown bound")
        self.record("fixture_closed", pid=os.getpid())


def isolated(args):
    # Fixed local dependency setup, never an assertion about isolation behavior.
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture, native, reader, stderr_reader = None, None, None, None

    def stop(_signum, _frame):
        raise SystemExit(0)

    def deadline(_signum, _frame):
        raise TimeoutError("ordinary feedback fixture lifetime bound")

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGALRM, deadline)
    signal.setitimer(signal.ITIMER_REAL, 50)
    try:
        certificates(args.root)
        fixture = OrdinaryFeedback(args.root)
        environment = fixture.configure()
        native = subprocess.Popen([
            str(args.codex), "-c", 'approval_policy="never"',
            "-c", 'sandbox_mode="danger-full-access"', "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=args.root / "workspace", env=environment)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid())

        def output():
            try:
                count, total = 0, 0
                while line := native.stdout.readline(MAX_WIRE + 1):
                    count += 1
                    total += len(line)
                    if count > 128 or total > 2_097_152 or len(line) > MAX_WIRE or not line.endswith(b"\n"):
                        raise ValueError("ordinary native output bound")
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="native-output", kind=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()

        def stderr_output():
            try:
                total = 0
                with (args.root / "native-stderr.log").open("xb") as destination:
                    while data := native.stderr.read(4096):
                        total += len(data)
                        if total > 262_144:
                            fixture.record("fixture_error", stage="native-stderr", kind="size_bound")
                            native.terminate()
                            return
                        destination.write(data)
            except Exception as error:
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="native-stderr", kind=type(error).__name__)

        stderr_reader = threading.Thread(target=stderr_output, daemon=True)
        stderr_reader.start()
        count, total, pending = 0, 0, bytearray()
        while True:
            control = args.root / "ordinary-feedback-close.json"
            if control.exists():
                if control.stat().st_size > 4096:
                    raise ValueError("ordinary close control byte bound")
                raw = control.read_bytes()
                if len(raw) > 4096 or json.loads(raw) != {"action": "close"}:
                    raise ValueError("ordinary close control framing")
                fixture.record("close_started")
                return
            readable, _, _ = select.select([sys.stdin.buffer], [], [], 0.1)
            if not readable:
                continue
            chunk = os.read(sys.stdin.fileno(), 65_536)
            if not chunk:
                return
            total += len(chunk)
            pending.extend(chunk)
            if total > 262_144 or len(pending) > MAX_WIRE:
                raise ValueError("ordinary native input byte bound")
            while b"\n" in pending:
                line, _, remainder = pending.partition(b"\n")
                pending = bytearray(remainder)
                count += 1
                if count > 24:
                    raise ValueError("ordinary native input count bound")
                native.stdin.write(line + b"\n")
                native.stdin.flush()
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.closing.set()
        cleanup_errors = []
        if native is not None:
            try:
                native.stdin.close()
            except (BrokenPipeError, OSError):
                pass
            try:
                if native.poll() is None:
                    native.terminate()
            except ProcessLookupError:
                pass
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
        if reader is not None:
            reader.join(5)
            if reader.is_alive():
                cleanup_errors.append("ordinary native reader shutdown bound")
        if stderr_reader is not None:
            stderr_reader.join(5)
            if stderr_reader.is_alive():
                cleanup_errors.append("ordinary native stderr shutdown bound")
        if fixture is not None:
            fixture.close()
            fixture.record("native_closed", pid=native.pid if native is not None else None)
        if cleanup_errors:
            raise RuntimeError("; ".join(cleanup_errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    if hashlib.sha256(args.codex.read_bytes()).hexdigest() != BINARY_SHA:
        raise ValueError("immutable Codex binary hash mismatch")
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                  "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside"])
    isolated(args)


if __name__ == "__main__":
    main()
