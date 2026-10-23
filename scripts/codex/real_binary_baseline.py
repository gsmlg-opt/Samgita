#!/usr/bin/env python3
"""Raw native reference journey against the exact official binary and local model.

The output is a safe evidence summary, not a blanket compatibility certificate.
No scripted app-server, inherited account or paid provider is used.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time

from fetch_pin import BINARY_SHA256, CACHE, COMMIT, digest
from model_fixture import ModelFixture


class NativeProcess:
    def __init__(self, binary, root):
        self.home, self.codex_home = root / "home", root / "codex"
        self.workspace = root / "workspace"
        for path in (self.home, self.codex_home, self.workspace):
            path.mkdir(exist_ok=True)
        env = {"PATH": os.environ["PATH"], "HOME": str(self.home),
               "CODEX_HOME": str(self.codex_home), "LANG": "C.UTF-8",
               "NO_COLOR": "1", "RUST_LOG": "off"}
        self.process = subprocess.Popen([str(binary), "app-server", "--listen", "stdio://"],
                                        cwd=self.workspace, env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        start_new_session=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.notifications, self.server_requests = [], []

    def send(self, message):
        self.process.stdin.write(json.dumps(message).encode() + b"\n")
        self.process.stdin.flush()

    def receive(self, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                return json.loads(line)
            if self.selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(self.process.stdout.fileno(), 65_536)
                if not chunk:
                    raise RuntimeError("Pinned app-server exited unexpectedly")
                self.buffer += chunk
                if len(self.buffer) > 8_388_608:
                    raise RuntimeError("Reference harness message bound exceeded")
        raise TimeoutError("Pinned app-server did not produce the expected message")

    def track(self, wire):
        if "method" in wire:
            target = self.server_requests if "id" in wire else self.notifications
            target.append(wire)

    def call(self, identity, method, params):
        self.send({"id": identity, "method": method, "params": params})
        while True:
            wire = self.receive()
            self.track(wire)
            if "method" not in wire and wire.get("id") == identity:
                return wire

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=3)
        self.selector.close()


def run(binary, experimental):
    with tempfile.TemporaryDirectory(prefix="samgita-codex-reference-") as scratch:
        root = Path(scratch)
        # Create configuration before launching; the process owns no ambient home.
        fixture = ModelFixture().start()
        (root / "codex").mkdir()
        fixture.config(root / "codex")
        process = None
        try:
            process = NativeProcess(binary, root)
            before = process.call("before", "thread/list", {"limit": 2})
            assert "error" in before, "pre-initialization request was accepted"
            initialized = process.call("initialize", "initialize", {
                "clientInfo": {"name": "samgita_reference", "version": "0.1.0"},
                "capabilities": {"experimentalApi": experimental},
            })
            assert "result" in initialized, "initialization failed"
            process.send({"method": "initialized"})
            duplicate = process.call("duplicate", "initialize", {
                "clientInfo": {"name": "samgita_reference", "version": "0.1.0"},
            })
            assert "error" in duplicate, "duplicate initialization was accepted"
            listing = process.call("list", "thread/list", {"limit": 2})
            assert listing.get("result", {}).get("data") == []
            configuration = process.call("config", "config/read", {"includeLayers": False})
            assert "result" in configuration
            start = process.call("thread", "thread/start", {
                "model": "mock-model", "modelProvider": "fixture",
                "cwd": str(process.workspace), "sandbox": "read-only",
                "approvalPolicy": "on-request", "ephemeral": True,
                "config": {"web_search": "disabled"},
            })
            assert "result" in start, "thread start failed"
            thread_id = start["result"]["thread"]["id"]
            turn = process.call("turn", "turn/start", {
                "threadId": thread_id,
                "input": [{"type": "text", "text": "Fixture input", "text_elements": []}],
            })
            assert "result" in turn, "turn start failed"
            turn_id = turn["result"]["turn"]["id"]
            while True:
                wire = process.receive()
                process.track(wire)
                if wire.get("method") == "turn/completed":
                    assert wire["params"]["turn"]["id"] == turn_id
                    assert wire["params"]["turn"]["status"] == "completed", "turn did not complete"
                    break
            assert fixture.requests, "real app-server did not reach the local model fixture"
            assert not process.server_requests, "unexpected interaction in text fixture"
            counts = Counter(item["method"] for item in process.notifications)
            assert counts["item/started"] and counts["item/completed"] and counts["turn/completed"]
            return {"profile": "experimental" if experimental else "stable", "transport": "stdio",
                    "handshake": "passed", "pre_init_rejection": before["error"]["code"],
                    "duplicate_init_rejection": duplicate["error"]["code"],
                    "thread_configuration": "explicit local provider, read-only, ephemeral",
                    "turn_status": "completed", "local_model_requests": len(fixture.requests),
                    "notification_counts": dict(sorted(counts.items())),
                    "binary_sha256": digest(binary), "source_commit": COMMIT,
                    "fixture_sha256": hashlib.sha256(Path(__file__).with_name("model_fixture.py").read_bytes()).hexdigest()}
        finally:
            if process:
                process.close()
            fixture.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=CACHE / "codex-x86_64-unknown-linux-musl")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    if digest(binary) != BINARY_SHA256:
        raise SystemExit("Executable does not match the immutable qualified pin")
    evidence = {"scope": "raw native baseline, not complete driver qualification",
                "profiles": [run(binary, False), run(binary, True)]}
    body = json.dumps(evidence, indent=2) + "\n"
    if args.output:
        args.output.write_text(body)
    print(body, end="")


if __name__ == "__main__":
    main()
