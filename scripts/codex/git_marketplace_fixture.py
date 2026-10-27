#!/usr/bin/env python3
"""Bounded loopback smart-HTTP fixture using the installed Git HTTP backend.

This serves one owned repository's real refs/objects. It never emulates Codex,
creates checkout files, accepts pushes, or substitutes another Git transport.
The caller owns stdin and the existing stdio process-group guardian.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import select
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit


MAX_REQUESTS = 64
MAX_BYTES = 2_097_152
MAX_HEADERS = 16_384
BACKEND_SECONDS = 3.0


def backend_path(git):
    result = subprocess.run([git, "--exec-path"], check=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2)
    if len(result.stdout) > 4096 or result.stderr:
        raise RuntimeError("invalid Git exec-path result")
    path = Path(os.fsdecode(result.stdout).strip()) / "git-http-backend"
    if not path.is_file():
        raise RuntimeError("BLOCKED_ENV: installed git-http-backend required")
    return path


def run_backend(backend, env, body, stopping):
    # Keep descendants in the fixture's existing owned process group, so its
    # guardian can reap them even if an assertion or the Python controller dies.
    process = subprocess.Popen([str(backend)], env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               bufsize=0)
    selector = selectors.DefaultSelector()
    output = bytearray()
    errors = bytearray()
    remaining = memoryview(body)
    deadline = time.monotonic() + BACKEND_SECONDS
    try:
        for stream in (process.stdin, process.stdout, process.stderr):
            os.set_blocking(stream.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ, output)
        selector.register(process.stderr, selectors.EVENT_READ, errors)
        if remaining:
            selector.register(process.stdin, selectors.EVENT_WRITE)
        else:
            process.stdin.close()
        while selector.get_map():
            if stopping.is_set() or time.monotonic() >= deadline:
                raise RuntimeError("Git HTTP backend interrupted or deadline exceeded")
            for key, _mask in selector.select(timeout=0.05):
                if key.fileobj is process.stdin:
                    try:
                        count = os.write(process.stdin.fileno(), remaining[:65536])
                    except BrokenPipeError:
                        count = len(remaining)
                    remaining = remaining[count:]
                    if not remaining:
                        selector.unregister(process.stdin)
                        process.stdin.close()
                else:
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                    else:
                        key.data.extend(chunk)
                        limit = MAX_BYTES if key.data is output else MAX_HEADERS
                        if len(key.data) > limit:
                            raise RuntimeError("Git HTTP backend output overflow")
        code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
        if code != 0:
            raise RuntimeError("Git HTTP backend failed")
        return bytes(output), process.pid, code
    finally:
        selector.close()
        if process.poll() is None:
            process.kill()
        process.wait(timeout=0.5)
        for stream in (process.stdin, process.stdout, process.stderr):
            if not stream.closed:
                stream.close()


def cgi_response(encoded):
    header, separator, body = encoded.partition(b"\r\n\r\n")
    if not separator:
        header, separator, body = encoded.partition(b"\n\n")
    if not separator or len(header) > MAX_HEADERS:
        raise RuntimeError("invalid Git HTTP backend headers")
    status = 200
    headers = []
    for line in header.splitlines():
        name, colon, value = line.partition(b":")
        if not colon:
            raise RuntimeError("invalid Git HTTP backend header")
        name = name.decode("ascii")
        value = value.strip().decode("ascii")
        if name.lower() == "status":
            status = int(value.split(" ", 1)[0])
        elif name.lower() in {"content-type", "cache-control", "expires", "pragma"}:
            headers.append((name, value))
    if status != 200 or not any(name.lower() == "content-type" for name, _ in headers):
        raise RuntimeError("unexpected Git HTTP backend response")
    return status, headers, body


class OwnedHTTPServer(HTTPServer):
    def __init__(self, address, handler, fixture):
        self.fixture = fixture
        self.current = None
        self.current_lock = threading.Lock()
        super().__init__(address, handler)
        self.timeout = 0.05

    def get_request(self):
        connection, address = super().get_request()
        # Bound reads before BaseHTTPRequestHandler parses the request line or
        # headers, including a connection interrupted before dispatch begins.
        connection.settimeout(2)
        if not self.fixture.reserve_attempt():
            connection.close()
            raise OSError("Git fixture request-count overflow")
        with self.current_lock:
            self.current = connection
        if self.fixture.stopping.is_set():
            self.interrupt()
        return connection, address

    def shutdown_request(self, request):
        try:
            super().shutdown_request(request)
        finally:
            with self.current_lock:
                if self.current is request:
                    self.current = None

    def interrupt(self):
        with self.current_lock:
            connection = self.current
        if connection is not None:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class GitFixture:
    def __init__(self, repository, git, journal):
        self.repository = repository.resolve(strict=True)
        if self.repository.name != "fixture.git" or not (self.repository / ".git").is_dir():
            raise RuntimeError("one owned fixture.git working repository required")
        self.backend = backend_path(git)
        self.journal = journal
        self.entries = []
        self.attempts = 0
        self.failure = None
        self.stopping = threading.Event()
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                self.dispatch()

            def do_POST(self):
                self.dispatch()

            def dispatch(self):
                try:
                    fixture.respond(self)
                except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
                    fixture.failure = "Git fixture request failed or exceeded a bound"
                    fixture.save()
                    self.send_error(500, "Owned Git fixture failure")

        self.server = OwnedHTTPServer(("127.0.0.1", 0), Handler, self)
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.save()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}/fixture.git"

    def save(self):
        encoded = json.dumps({"failure": self.failure, "attempts": self.attempts,
                              "entries": self.entries})
        if len(encoded.encode()) > 65_536:
            raise RuntimeError("Git fixture journal overflow")
        temporary = self.journal.with_suffix(".partial")
        temporary.write_text(encoded)
        temporary.replace(self.journal)

    def reserve_attempt(self):
        # Every accepted attempt consumes the budget, even if header/body
        # parsing or the backend subsequently fails and no success is recorded.
        if self.attempts >= MAX_REQUESTS:
            self.failure = "Git fixture request-count overflow"
            self.stopping.set()
            self.save()
            return False
        self.attempts += 1
        self.save()
        return True

    def serve(self):
        while not self.stopping.is_set():
            self.server.handle_request()

    def respond(self, handler):
        target = urlsplit(handler.path)
        if len(handler.path) > 256 or sum(len(k) + len(v) for k, v in handler.headers.items()) > MAX_HEADERS:
            raise RuntimeError("Git fixture request-header overflow")
        expected = (
            handler.command == "GET" and target.path == "/fixture.git/info/refs"
            and target.query == "service=git-upload-pack"
        ) or (
            handler.command == "POST" and target.path == "/fixture.git/git-upload-pack"
            and not target.query
        )
        if not expected or handler.headers.get("Transfer-Encoding"):
            raise RuntimeError("unexpected Git read request")
        size = int(handler.headers.get("Content-Length", "0"))
        if not 0 <= size <= MAX_BYTES:
            raise RuntimeError("Git fixture request-body overflow")
        body = handler.rfile.read(size)
        if len(body) != size:
            raise RuntimeError("incomplete Git request body")
        env = dict(os.environ)
        env.update({
            "GIT_PROJECT_ROOT": str(self.repository.parent),
            "GIT_HTTP_EXPORT_ALL": "1",
            "GIT_EXEC_PATH": str(self.backend.parent),
            "REQUEST_METHOD": handler.command,
            "PATH_INFO": target.path,
            "QUERY_STRING": target.query,
            "CONTENT_TYPE": handler.headers.get("Content-Type", ""),
            "CONTENT_LENGTH": str(size),
            "HTTP_GIT_PROTOCOL": handler.headers.get("Git-Protocol", ""),
            "HTTP_CONTENT_ENCODING": handler.headers.get("Content-Encoding", ""),
            "REMOTE_ADDR": "127.0.0.1",
            "SERVER_PROTOCOL": handler.request_version,
        })
        output, pid, code = run_backend(self.backend, env, body, self.stopping)
        status, headers, response = cgi_response(output)
        self.entries.append({
            "method": handler.command, "path": handler.path, "status": status,
            "request_bytes": len(body), "response_bytes": len(response),
            "backend_pid": pid, "backend_returncode": code,
        })
        self.save()
        handler.send_response(status)
        for name, value in headers:
            handler.send_header(name, value)
        handler.send_header("Content-Length", str(len(response)))
        handler.end_headers()
        handler.wfile.write(response)

    def close(self):
        self.stopping.set()
        self.server.interrupt()
        self.thread.join(timeout=0.5)
        self.server.server_close()
        if self.thread.is_alive():
            raise RuntimeError("Git fixture thread did not stop")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--git", required=True)
    parser.add_argument("--journal", type=Path, required=True)
    args = parser.parse_args()
    fixture = GitFixture(args.repository, args.git, args.journal)
    for name in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(name, lambda *_args: fixture.stopping.set())
    fixture.thread.start()
    print(json.dumps({"url": fixture.url, "pid": os.getpid(),
                      "backend": str(fixture.backend)}), flush=True)
    try:
        while not fixture.stopping.is_set():
            readable, _, _ = select.select([sys.stdin], [], [], 0.05)
            if readable and not os.read(sys.stdin.fileno(), 1):
                break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
