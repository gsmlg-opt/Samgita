#!/usr/bin/env python3
"""Owned Sentry HTTPS peer around immutable Codex, never an app-server emitter.

Source-only draft: parent must review/install/qualify before claiming evidence.
No upstream connection is opened. Only bounded synthetic feedback is admitted.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import time
import zlib


BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SENTRY_HOST = "o33249.ingest.us.sentry.io"
SENTRY_PATH = "/api/4510195390611458/envelope/"
PUBLIC_DSN_KEY = "ae32ed50620d7a7792c1ce5df38b3e3e"
REASON = "Owned synthetic feedback only."
ATTACHMENT = b"Owned synthetic diagnostic only.\n"
FILENAME = "owned-feedback-diagnostic.txt"
MAX_WIRE = 16_384
MAX_HEADERS = 16_384
MAX_BODY = 262_144
MAX_DECODED = 524_288
MAX_UPLOADS = 16
ALLOWED_METHODS = {"initialize", "initialized", "thread/loaded/list", "feedback/upload"}


def atomic_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value, ensure_ascii=False))
    pending.replace(path)


def isolation(parent):
    child = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes += json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
    assert child != parent, "BLOCKED_ENV: private network namespace required"
    assert [row["ifname"] for row in links] == ["lo"]
    for row in routes:
        assert row.get("dev") == "lo" and row.get("dst") != "default"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent": parent, "child": child, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


def certificates(root):
    tls = root / "tls"
    tls.mkdir(mode=0o700)
    (tls / "extensions.cnf").write_text(
        f"subjectAltName=DNS:{SENTRY_HOST}\nbasicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
    commands = [
        ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
         "-subj", "/CN=Owned synthetic feedback CA", "-addext", "basicConstraints=critical,CA:TRUE",
         "-keyout", str(tls / "ca.key"), "-out", str(tls / "ca.pem")],
        ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
         "-subj", f"/CN={SENTRY_HOST}", "-keyout", str(tls / "server.key"),
         "-out", str(tls / "server.csr")],
        ["x509", "-req", "-in", str(tls / "server.csr"), "-CA", str(tls / "ca.pem"),
         "-CAkey", str(tls / "ca.key"), "-CAcreateserial", "-days", "1", "-sha256",
         "-extfile", str(tls / "extensions.cnf"), "-out", str(tls / "server.pem")],
    ]
    for command in commands:
        subprocess.run(["openssl", *command], check=True, timeout=15, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for path in tls.glob("*.key"):
        path.chmod(0o600)


def headers(stream):
    first = stream.readline(2049)
    assert first.endswith(b"\r\n") and len(first) <= 2048, "bounded request line required"
    fields, used = {}, len(first)
    for _ in range(33):
        line = stream.readline(2049)
        used += len(line)
        assert used <= MAX_HEADERS and line.endswith(b"\r\n") and len(line) <= 2048
        if line == b"\r\n":
            return first[:-2].decode("ascii"), fields
        key, value = line[:-2].decode("ascii").split(":", 1)
        key = key.lower()
        assert re.fullmatch(r"[a-z0-9-]+", key) and key not in fields
        fields[key] = value.strip()
    raise AssertionError("too many HTTP headers")


def decode_body(body, encoding):
    if encoding == "gzip":
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        body = decoder.decompress(body, MAX_DECODED + 1)
        assert decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data
    else:
        assert encoding in [None, "identity"]
    assert 0 < len(body) <= MAX_DECODED
    return body


def envelope(body):
    header, body = body.split(b"\n", 1)
    metadata = json.loads(header)
    item_line, body = body.split(b"\n", 1)
    item = json.loads(item_line)
    size = item["length"]
    assert type(size) is int and 0 <= size <= MAX_DECODED
    payload, trailing = body[:size], body[size:]
    assert len(payload) == size and trailing in [b"", b"\n"], "one item per envelope required"
    kind = item["type"]
    event_id = metadata.get("event_id")
    assert isinstance(event_id, str) and re.fullmatch(r"[a-f0-9-]{32,36}", event_id)
    details = {"kind": kind, "event_id": event_id, "decoded_size": size,
               "payload_sha256": hashlib.sha256(payload).hexdigest()}
    if kind == "event":
        event = json.loads(payload)
        assert event["tags"]["classification"] == "bug"
        assert event["tags"]["reason"] == REASON
        thread_id = event["tags"]["thread_id"]
        assert isinstance(thread_id, str) and thread_id.startswith("no-active-thread-")
        details["thread_id"] = thread_id
    else:
        assert kind == "attachment" and item["filename"] == FILENAME
        assert payload == ATTACHMENT, "only the owned synthetic file may be uploaded"
        details["filename"] = FILENAME
    return details


class Fixture:
    def __init__(self, root, scenario, proof):
        self.root, self.scenario = root, scenario
        self.lock, self.closing = threading.RLock(), threading.Event()
        self.journal = {"namespace": proof, "events": []}
        self.connections, self.uploads = 0, 0
        self.sockets = set()
        fixture = self
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.set_alpn_protocols(["http/1.1"])
        context.load_cert_chain(root / "tls/server.pem", root / "tls/server.key")

        class Server(socketserver.ThreadingTCPServer):
            daemon_threads = False

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", error_type=sys.exc_info()[0].__name__)

        class Handler(socketserver.BaseRequestHandler):
            def handle(self):
                connection = self.request
                connection.settimeout(5)
                with fixture.lock:
                    fixture.connections += 1
                    assert fixture.connections <= 24, "owned connection bound exceeded"
                    fixture.sockets.add(connection)
                try:
                    with connection.makefile("rb") as stream:
                        first, fields = headers(stream)
                    if first != f"CONNECT {SENTRY_HOST}:443 HTTP/1.1" or "proxy-authorization" in fields:
                        fixture.record("forbidden_proxy")
                        connection.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
                        return
                    connection.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                    secure = context.wrap_socket(connection, server_side=True)
                    with fixture.lock:
                        fixture.sockets.discard(connection)
                        fixture.sockets.add(secure)
                    connection = secure
                    with secure.makefile("rb") as stream:
                        first, fields = headers(stream)
                        assert first == f"POST {SENTRY_PATH} HTTP/1.1", "only fixed envelope POST allowed"
                        assert fields.get("host") in [SENTRY_HOST, SENTRY_HOST + ":443"]
                        assert "authorization" not in fields and "chatgpt-account-id" not in fields
                        assert "transfer-encoding" not in fields
                        assert f"sentry_key={PUBLIC_DSN_KEY}" in fields.get("x-sentry-auth", "")
                        length = int(fields["content-length"])
                        assert 0 < length <= MAX_BODY
                        body = stream.read(length)
                        assert len(body) == length
                    details = envelope(decode_body(body, fields.get("content-encoding")))
                    with fixture.lock:
                        fixture.uploads += 1
                        assert fixture.uploads <= MAX_UPLOADS, "owned upload bound exceeded"
                    if fixture.scenario == "partial":
                        status = 200 if details["kind"] == "event" else 503
                    else:
                        status = {"core429": 429, "core503": 503, "held": 503}.get(fixture.scenario, 200)
                    if details["kind"] == "attachment":
                        assert fixture.scenario in ["extra", "partial"]
                    fixture.record("upload", **details, status=status, path=SENTRY_PATH,
                                   tls_version=secure.version(), host_verified=True,
                                   sentry_auth_verified=True, account_headers_absent=True)
                    if fixture.scenario == "held":
                        deadline = time.monotonic() + 8
                        while not (root / "release-response").exists():
                            if fixture.closing.wait(0.01):
                                return
                            assert time.monotonic() < deadline, "owned response release deadline"
                    reasons = {200: "OK", 429: "Too Many Requests", 503: "Service Unavailable"}
                    response = (f"HTTP/1.1 {status} {reasons[status]}\r\nContent-Length: 2\r\n"
                                "Connection: close\r\n\r\n{}").encode()
                    secure.sendall(response)
                    fixture.record("response_sent", event_id=details["event_id"],
                                   kind=details["kind"], status=status)
                finally:
                    with fixture.lock:
                        fixture.sockets.discard(connection)
                    connection.close()

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.record("isolation_ready", scenario=scenario)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 128, "journal bound exceeded"
            self.journal["events"].append({"event": event, **fields})
            atomic_json(self.root / "journal.json", self.journal)

    def configure(self):
        codex = self.root / "codex"
        assert not any(codex.iterdir()), "fresh owned CODEX_HOME required"
        catalog = codex / "models.json"
        atomic_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "No inference authorized",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turns in this profile."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "http://127.0.0.1:9/backend-api"
openai_base_url = "http://127.0.0.1:9/v1"
[feedback]
enabled = true
[analytics]
enabled = false
[features]
apps = false
plugins = false
codex_hooks = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "No inference owned feedback fixture"
base_url = "http://127.0.0.1:9/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        path = self.root / FILENAME
        with path.open("xb") as attachment:
            attachment.write(ATTACHMENT)
        path.chmod(0o600)
        proxy = f"http://127.0.0.1:{self.server.server_address[1]}"
        return {"HOME": str(self.root / "home"), "CODEX_HOME": str(codex),
                "TMPDIR": str(self.root / "tmp"), "PATH": os.environ["PATH"],
                "HTTPS_PROXY": proxy, "https_proxy": proxy,
                "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost",
                "SSL_CERT_FILE": str(self.root / "tls/ca.pem"),
                "NO_COLOR": "1", "RUST_LOG": "off", "CODEX_DISABLE_REMOTE_CONTROL": "1",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_TERMINAL_PROMPT": "0", "PYTHONDONTWRITEBYTECODE": "1"}

    def close(self):
        self.closing.set()
        self.server.shutdown()
        with self.lock:
            sockets = list(self.sockets)
        for connection in sockets:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.server.server_close()
        self.thread.join(5)
        assert not self.thread.is_alive(), "owned feedback peer did not stop"
        self.record("peer_closed")


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    proof = isolation(args.parent_netns)
    certificates(args.root)
    fixture, native, reader = None, None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args.root, args.scenario, proof)
        environment = fixture.configure()
        with (args.root / "native-stderr.log").open("w") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=BINARY_SHA256,
                       child_ca_only=True, proxy_never_forwards=True)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n"), "bounded native output required"
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        input_count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            input_count += 1
            assert input_count <= 16 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            wire = json.loads(line)
            assert wire.get("method") in ALLOWED_METHODS, "unapproved native method"
            if wire["method"] == "feedback/upload":
                expected = {"classification": "bug", "reason": REASON, "includeLogs": False}
                if args.scenario in ["extra", "partial"]:
                    expected["extraLogFiles"] = [str(args.root / FILENAME)]
                    path = args.root / FILENAME
                    assert not path.is_symlink() and path.read_bytes() == ATTACHMENT
                assert wire.get("params") == expected, "only fixed synthetic feedback allowed"
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
    parser.add_argument("--scenario", required=True,
                        choices=["event", "extra", "core429", "core503", "partial", "held"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == BINARY_SHA256
    assert all((args.root / name).is_dir() and not (args.root / name).is_symlink()
               for name in ["home", "codex", "workspace", "tmp"])
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip", "openssl"]), \
            "BLOCKED_ENV: Linux namespaces, ip and openssl required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
