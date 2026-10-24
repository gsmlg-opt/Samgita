#!/usr/bin/env python3
"""Owned, fixed-message Responses peer for actual pinned review delivery.

The existing BEM fixture owns the private namespace, UDS, restart and shutdown.
Its original provider is closed before native startup. Its unused realtime peer
remains owned and must receive no traffic. No app-server frame is synthesized.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture


INSTRUCTIONS = "Review the owned synthetic change λ🙂"
PARENT_INPUT = "Owned review parent context λ"
PARENT_ANSWER = "Owned parent materialized"
ANSWER = "No findings. Owned review λ🙂"


class ReviewProvider(ModelFixture):
    def __init__(self, root, scenario):
        super().__init__(scenario, root / "workspace", root / "requests.json")
        self.root = root
        self.records, self.errors = [], []
        self.record_lock = threading.Lock()
        self.release = threading.Event()
        self.closing = threading.Event()
        atomic(self.requests_file, [])
        atomic(root / "review-http.json", [])
        atomic(root / "provider-errors.json", [])
        provider = self
        base = self.server.RequestHandlerClass

        class Handler(base):
            def do_GET(self):
                provider.reject(self, "Unapproved GET: " + self.path)

            def do_POST(self):
                try:
                    assert self.path == "/v1/responses", "Unapproved POST path"
                    assert self.headers.get("Authorization") is None, "Unexpected auth"
                    assert self.headers.get("Content-Encoding") in {None, "identity"}
                    assert not self.headers.get("Transfer-Encoding")
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 4194304, "Request size out of bounds"
                    request = json.loads(self.rfile.read(size))
                    with provider.lock:
                        provider.requests.append(request)
                        index = len(provider.requests)
                        atomic(provider.requests_file, provider.requests)
                    provider.record("http_request", path=self.path, index=index, method="POST")
                    provider.write_response(self, index, request)
                except (AssertionError, KeyError, TypeError, ValueError) as error:
                    provider.reject(self, type(error).__name__ + ": " + str(error))
                except (BrokenPipeError, ConnectionResetError):
                    if not provider.closing.is_set():
                        provider.fail("Unexpected provider disconnect")

        self.server.RequestHandlerClass = Handler

    def record(self, event, **values):
        with self.record_lock:
            self.records.append({"event": event, **values})
            atomic(self.root / "review-http.json", self.records)

    def fail(self, message):
        with self.record_lock:
            self.errors.append(message)
            atomic(self.root / "provider-errors.json", self.errors)

    def reject(self, handler, message):
        self.fail(message)
        handler.send_error(500, "Unapproved synthetic review request")

    def write_response(self, handler, index, request):
        budget = {"detached": 2, "inline": 1, "rejected": 0}[self.scenario]
        assert 1 <= index <= budget, "Responses request budget exceeded"
        assert request["model"] == "mock-model"
        assert not any(item.get("type") in {"function_call", "function_call_output"}
                       for item in request["input"]), "Unexpected tool execution"
        texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                 for part in item.get("content", []) if part.get("type") == "input_text"]
        materialize = self.scenario == "detached" and index == 1
        if materialize:
            assert PARENT_INPUT in texts
        else:
            expected = INSTRUCTIONS
            if self.scenario == "detached":
                skill = self.root / "codex" / "skills" / ".system" / "review-agent" / "SKILL.md"
                expected = f"Use [$review-agent]({skill}) for this review.\n\n{INSTRUCTIONS}"
                assert PARENT_INPUT in texts, "Detached fork lost parent context"
            assert expected in texts, "Review prompt differs from independent fixed oracle"
            self.record("review_pending", index=index)
            assert self.release.wait(timeout=10), "Explicit review release deadline"
            if self.closing.is_set():
                return
        self.record("response_released", index=index)
        super().write_response(handler, index, request)

    def response_item(self, index, _request):
        text = PARENT_ANSWER if self.scenario == "detached" and index == 1 else ANSWER
        return {"type": "message", "role": "assistant", "id": f"owned-review-message-{index}",
                "content": [{"type": "output_text", "text": text}]}

    def close(self):
        self.closing.set()
        self.release.set()
        super().close()


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        self.provider.close()
        assert self.provider.requests == [] and self.native is None
        self.provider = ReviewProvider(self.root, args.scenario).start()
        # Replace all BEM account/realtime/provider settings with the existing
        # no-auth synthetic Responses configuration before the first native run.
        configure(self.root, self.provider)
        path = self.root / "codex" / "config.toml"
        config = path.read_text().replace("[features]\n",
            "[features]\nenable_request_compression = false\n")
        path.write_text(config + "\n[analytics]\nenabled = false\n")
        self.record("review_provider_ready", scenario=args.scenario,
                    source_provider_requests=0, api_base=self.provider.url + "/v1",
                    request_auth="none", output="fixed_assistant_messages_only")

    def control(self, message):
        if message.get("op") == "releaseReview":
            assert set(message) == {"id", "op"} and not self.closed
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            assert not self.provider.release.is_set()
            assert sum(row["event"] == "review_pending" for row in self.provider.records) == 1
            self.provider.release.set()
            self.record("control_done", id=message["id"], op=message["op"])
        else:
            super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["detached", "inline", "rejected"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args, isolation(args.parent_netns))
        fixture.start_native()
        for line in sys.stdin:
            assert len(line.encode()) <= 1024
            fixture.control(json.loads(line))
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


if __name__ == "__main__":
    main()
