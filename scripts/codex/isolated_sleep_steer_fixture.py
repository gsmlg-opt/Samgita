#!/usr/bin/env python3
"""Owned native clock.sleep input wake with raw model request/response evidence.

The BEM controller owns private namespace, exact native restart and cleanup.
This peer emits only one fixed namespaced model tool call and one fixed answer;
every app-server item, input acceptance and durable record comes from Codex.
"""
import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture, response_events


INITIAL = "Owned native sleep initial input"
STEER = "Owned new input wakes this native sleep"
ANSWER = "Owned native sleep continued after accepted input"
CALL = "owned-sleep-steer-1"
ARGUMENTS = '{"duration_ms":60000}'
OUTPUT = re.compile(r"Wall time: ([0-9]+\.[0-9]{4}) seconds\nSleep interrupted by new input\.")


def sleep_tool(request):
    clocks = [tool for tool in request["tools"]
              if tool.get("type") == "namespace" and tool.get("name") == "clock"]
    assert len(clocks) == 1, "Stock clock namespace missing or duplicated"
    tools = [tool for tool in clocks[0]["tools"] if tool.get("name") == "sleep"]
    assert len(tools) == 1, "Stock clock.sleep missing or duplicated"
    tool = tools[0]
    assert tool["type"] == "function" and tool["strict"] is False
    assert isinstance(tool["description"], str) and tool["description"]
    parameters = tool["parameters"]
    assert parameters["type"] == "object"
    assert set(parameters["properties"]) == {"duration_ms"}
    assert parameters["properties"]["duration_ms"]["type"] == "number"
    assert parameters["required"] == ["duration_ms"]
    assert parameters["additionalProperties"] is False
    return tool


class SleepProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("assistant", root / "workspace", root / "requests.json")
        self.root, self.records, self.errors = root, [], []
        self.record_lock = threading.Lock()
        self.closing = threading.Event()
        self.server.daemon_threads = True
        for path in [self.requests_file, root / "sleep-http.json", root / "provider-errors.json"]:
            atomic(path, [])
        provider, base = self, self.server.RequestHandlerClass

        class Handler(base):
            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def do_GET(self):
                provider.reject(self, "Unapproved HTTP method: " + self.command)

            do_PUT = do_DELETE = do_PATCH = do_HEAD = do_GET

            def do_POST(self):
                try:
                    assert self.path == "/v1/responses", "Unapproved POST path"
                    assert self.headers.get("Authorization") is None, "Unexpected auth"
                    assert self.headers.get("Content-Encoding") in {None, "identity"}
                    assert not self.headers.get("Transfer-Encoding")
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 4_194_304, "Request size out of bounds"
                    raw = self.rfile.read(size)
                    assert len(raw) == size, "Truncated owned model request"
                    request = json.loads(raw)
                    metadata = json.loads(self.headers.get("x-codex-turn-metadata", "null"))
                    assert isinstance(metadata, dict), "Missing native turn metadata"
                    assert all(isinstance(metadata.get(key), str) and metadata[key]
                               for key in ["thread_id", "turn_id"])
                    with provider.lock:
                        assert len(provider.requests) < 2, "Responses request budget exceeded"
                        provider.requests.append(request)
                        index = len(provider.requests)
                        atomic(provider.requests_file, provider.requests)
                    provider.record(index=index, metadata=metadata, path=self.path,
                                    rawBodyBase64=base64.b64encode(raw).decode(),
                                    rawBodySHA256=hashlib.sha256(raw).hexdigest(),
                                    requestAuth="none", responded=False)
                    provider.write_response(self, index, request)
                except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
                    if not provider.closing.is_set():
                        provider.reject(self, type(error).__name__ + ": " + str(error))

        self.server.RequestHandlerClass = Handler

    def record(self, **values):
        with self.record_lock:
            assert len(self.records) < 2, "Owned sleep HTTP journal bound"
            self.records.append(values)
            atomic(self.root / "sleep-http.json", self.records)

    def update(self, index, **values):
        with self.record_lock:
            self.records[index - 1].update(values)
            atomic(self.root / "sleep-http.json", self.records)

    def reject(self, handler, message):
        with self.record_lock:
            assert len(self.errors) < 8, "Owned sleep error journal bound"
            self.errors.append(message)
            atomic(self.root / "provider-errors.json", self.errors)
        handler.send_error(500, "Unapproved synthetic sleep request")

    def write_response(self, handler, index, request):
        assert request["model"] == "mock-model"
        sleep_tool(request)
        texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                 for part in item.get("content", []) if part.get("type") == "input_text"]
        assert texts.count(INITIAL) == 1
        calls = [item for item in request["input"] if item.get("type") == "function_call"]
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        assert not any(item.get("type") in {"custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"])
        if index == 1:
            assert calls == outputs == [] and STEER not in texts
            item = {"type": "function_call", "namespace": "clock", "name": "sleep",
                    "call_id": CALL, "arguments": ARGUMENTS}
        else:
            assert texts.count(STEER) == 1
            assert len(calls) == len(outputs) == 1
            call, output = calls[0], outputs[0]
            assert all(call.get(key) == value for key, value in {
                "namespace": "clock", "name": "sleep", "call_id": CALL,
                "arguments": ARGUMENTS}.items()), "Wrong actual native tool call"
            assert output["call_id"] == CALL and isinstance(output["output"], str)
            match = OUTPUT.fullmatch(output["output"])
            assert match, "Native sleep output is not the exact input-wake result"
            elapsed = float(match.group(1))
            assert math.isfinite(elapsed) and 0 <= elapsed < 10, "Native sleep wake exceeded ten seconds"
            assert self.records[0]["metadata"]["thread_id"] == self.records[1]["metadata"]["thread_id"]
            assert self.records[0]["metadata"]["turn_id"] == self.records[1]["metadata"]["turn_id"]
            self.update(index, elapsedSeconds=elapsed, nativeToolOutput=output["output"])
            item = {"type": "message", "role": "assistant", "id": "owned-sleep-answer",
                    "content": [{"type": "output_text", "text": ANSWER}]}
        events = response_events(index, item)
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        self.update(index, rawResponseBase64=base64.b64encode(body).decode(),
                    rawResponseSHA256=hashlib.sha256(body).hexdigest())
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        self.update(index, responded=True)

    def close(self):
        self.closing.set()
        super().close()


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            (self.root / "bin").mkdir()
            shutil.copyfile("/bin/sh", self.root / "bin/sh")
            (self.root / "bin/sh").chmod(0o700)
            self.provider = SleepProvider(self.root).start()
            configure(self.root, self.provider)
            path = self.root / "codex/config.toml"
            config = path.read_text().replace("[features]\n", "[features]\n"
                "enable_request_compression = false\nhooks = false\nremote_models = false\n"
                "shell_tool = false\nunified_exec = false\nbrowser_use = false\ncomputer_use = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                + config + "\n[features.sleep_tool]\nenabled = true\nmode = \"always_on\"\n"
                "\n[features.current_time_reminder]\nenabled = false\nclock_source = \"system\"\n"
                "\n[analytics]\nenabled = false\n")
            self.config = path.read_bytes()
            self.catalog = (self.root / "codex/models.json").read_bytes()
            self.record("sleep_provider_ready", source_provider_requests=0, request_auth="none",
                        output="fixed_stock_sleep_call_then_fixed_assistant", duration_ms=60000,
                        clock_source="system", sleep_tool_mode="always_on")
        except BaseException:
            self.close()
            raise

    def start_native(self):
        assert (self.root / "codex/config.toml").read_bytes() == self.config
        assert (self.root / "codex/models.json").read_bytes() == self.catalog
        assert not (self.root / "codex/auth.json").exists()
        assert list((self.root / "workspace").iterdir()) == []
        super().start_native()
        assert os.readlink(f"/proc/{self.native.pid}/ns/net") == self.proof["namespace"]

    def control(self, message):
        assert len(self.journal) < 32, "Owned sleep controller journal bound"
        super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
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
