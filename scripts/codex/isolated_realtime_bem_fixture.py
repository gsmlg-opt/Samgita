#!/usr/bin/env python3
"""Owned synthetic Responses and realtime peers around unmodified pinned Codex.

Only three fixed model scenarios are served in a private loopback namespace.
No app-server frame, shell command, media fetch or external inference is faked.
"""
import argparse
from copy import deepcopy
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from isolated_realtime_fixture import RealtimeFixture
from model_fixture import ModelFixture, response_events


SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
MARKDOWN = "::codex-realtime-inline{}\nOwned markdown λ"
VISUALIZATION = ("```\n::codex-inline-vis{file=hidden}\n```\n"
                 "~~~\nvisualize{file=also-hidden}\n~~~\n"
                 "::codex-inline-vis{file=first}\nvisualize{file=second}")
ANSWER = "Owned synthetic dynamic result acknowledged"
OUTPUT = "Owned fixed tool output λ"


def atomic(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value, ensure_ascii=False))
    temporary.replace(path)


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes += json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent and [row["ifname"] for row in links] == ["lo"]
    for row in routes:
        assert row.get("dst") != "default" and row.get("dev") == "lo"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent_namespace": parent, "namespace": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


class Provider(ModelFixture):
    def __init__(self, root, scenario):
        super().__init__(scenario, root / "workspace", root / "requests.json")
        self.errors = root / "provider-errors.json"
        atomic(self.errors, [])

    def write_response(self, handler, index, request):
        try:
            assert request["model"] == "mock-model"
            assert index <= (2 if self.scenario == "dynamic" else 1), "request budget exceeded"
            outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
            if self.scenario == "dynamic" and index == 2:
                assert len(outputs) == 1 and outputs[0]["call_id"] == "owned-bem-tool-call"
                assert outputs[0]["output"] == OUTPUT
            else:
                assert outputs == []
            item = self.item(index)
            events = response_events(index, item)
            if item["type"] == "message":
                empty = deepcopy(item)
                empty["content"][0]["text"] = ""
                text = item["content"][0]["text"]
                # Actual native streaming and final completion see the same
                # directives, so promotion deduplication is exercised.
                events[1:1] = [{"type": "response.output_item.added", "item": empty},
                               {"type": "response.output_text.delta", "delta": text}]
            body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                           for event in events).encode()
            handler.send_response(200)
            handler.send_header("Content-Type", "text/event-stream")
            handler.send_header("Content-Length", str(len(body)))
            handler.end_headers()
            handler.wfile.write(body)
        except (AssertionError, KeyError, TypeError) as error:
            atomic(self.errors, [type(error).__name__ + ": " + str(error)])
            handler.send_error(500, "Unapproved synthetic BEM model request")

    def item(self, index):
        if self.scenario == "dynamic" and index == 1:
            return {"type": "function_call", "name": "fixture_lookup",
                    "call_id": "owned-bem-tool-call", "arguments": '{"key":"synthetic"}'}
        text = {"dynamic": ANSWER, "markdown": MARKDOWN, "visualization": VISUALIZATION}[self.scenario]
        return {"type": "message", "role": "assistant", "id": "owned-bem-message",
                "content": [{"type": "output_text", "text": text}]}


class Fixture:
    def __init__(self, args, proof):
        self.root, self.binary, self.proof = args.root, args.codex, proof
        self.native, self.native_pids, self.closed = None, [], False
        self.journal = []
        self.provider = Provider(self.root, args.scenario).start()
        self.peer = RealtimeFixture(argparse.Namespace(
            codex_home=str(self.root / "codex"), requests_file=str(self.root / "rejected-realtime-posts.json")))
        self.peer.thread.start()
        catalog = self.root / "codex" / "models.json"
        atomic(catalog, {"models": [{"slug": "mock-model", "display_name": "Owned BEM fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned synthetic BEM qualification only."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        path = self.root / "codex" / "config.toml"
        config = path.read_text()
        old = f'base_url = "http://127.0.0.1:{self.peer.server.server_port}/v1"'
        assert config.count(old) == 2  # openai_base_url and provider base_url
        config = config.replace(old, f'base_url = "{self.provider.url}/v1"')
        config = config.replace('name = "Owned no-inference realtime fixture"',
                                'name = "Owned synthetic BEM fixture"')
        config = config.replace("[features]\n", "[features]\napps = false\n")
        path.write_text(f'model_catalog_json = {json.dumps(str(catalog))}\n' + config)

    def record(self, event, **values):
        self.journal.append({"event": event, **values})
        atomic(self.root / "bem-journal.json", self.journal)

    def start_native(self):
        path = self.root / "native.sock"
        path.unlink(missing_ok=True)
        environment = {key: os.environ[key] for key in
            ["HOME", "CODEX_HOME", "TMPDIR", "PATH", "NO_COLOR", "RUST_LOG", "CODEX_DISABLE_REMOTE_CONTROL"]}
        environment.update({"NO_PROXY": "*", "no_proxy": "*", "GIT_CONFIG_NOSYSTEM": "1",
                            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"})
        with (self.root / "native-stderr.log").open("a") as stderr:
            self.native = subprocess.Popen([str(self.binary), "app-server", "--listen", "unix://" + str(path)],
                cwd=self.root / "workspace", env=environment, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=stderr)
        self.native_pids.append(self.native.pid)
        deadline = time.monotonic() + 5
        while not path.exists():
            assert self.native.poll() is None, "owned native startup exited"
            assert time.monotonic() < deadline, "owned native startup deadline"
            time.sleep(0.01)
        atomic(self.root / "state.json", {**self.proof, "controller_pid": os.getpid(),
            "namespace_owner_pid": os.getppid(), "native_pid": self.native.pid,
            "native_pids": self.native_pids, "ready": True})
        self.record("native_started", pid=self.native.pid)

    def stop_native(self):
        if self.native is not None:
            if self.native.poll() is None:
                self.native.terminate()
            try:
                self.native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.native.kill()
                self.native.wait(timeout=5)
            self.record("native_stopped", pid=self.native.pid)
            self.native = None

    def close(self):
        if not self.closed:
            self.stop_native()
            self.peer.close()
            self.provider.close()
            self.closed = True
            self.record("fixture_closed")

    def control(self, message):
        assert set(message) == {"id", "op"} and message["op"] in {"restart", "barrier", "close"}
        assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
        if message["op"] == "restart":
            assert not self.closed
            self.stop_native()
            self.start_native()
        elif message["op"] == "close":
            self.close()
        self.record("control_done", id=message["id"], op=message["op"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["dynamic", "markdown", "visualization"])
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
