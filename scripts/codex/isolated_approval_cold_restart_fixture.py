#!/usr/bin/env python3
"""Owned hard restart while a native command approval is unanswered.

The controller kills only its live Popen and reaps it before an explicit restart.
The local model never writes the effect or synthesizes app-server traffic.
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

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_review_delivery_fixture import ReviewProvider
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture


FIRST = "Owned unanswered cold approval"
SECOND = "Owned explicit post-crash command"
COMMAND = "echo 'owned cold command' >> cold-command.txt; printf samgita_cold_command"
ANSWER = "Owned explicit cold command finished"


class ColdProvider(ReviewProvider):
    def __init__(self, root):
        super().__init__(root, "inline")

    def write_response(self, handler, index, request):
        assert 1 <= index <= 3 and request["model"] == "mock-model", "Unexpected cold inference"
        texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                 for part in item.get("content", []) if part.get("type") == "input_text"]
        assert (FIRST if index == 1 else SECOND) in texts, "Inference lacks explicit input"
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        if index <= 2:
            if index == 1:
                assert outputs == []
            assert not (self.root / "workspace" / "cold-command.txt").exists()
        else:
            assert len([item for item in outputs if item["call_id"] == "cold-command-2"]) == 1
            assert (self.root / "workspace" / "cold-command.txt").read_bytes() == b"owned cold command\n"
        self.record("cold_model_request", index=index)
        ModelFixture.write_response(self, handler, index, request)

    def response_item(self, index, _request):
        if index <= 2:
            return {"type": "function_call", "name": "exec_command",
                    "call_id": f"cold-command-{index}", "arguments": json.dumps({
                        "cmd": COMMAND, "workdir": str(self.root / "workspace"),
                        "shell": str(self.root / "bin" / "sh"), "login": False, "tty": False,
                        "sandbox_permissions": "require_escalated",
                        "justification": "Owned synthetic cold approval only"})}
        return {"type": "message", "role": "assistant", "id": "owned-cold-answer",
                "content": [{"type": "output_text", "text": ANSWER}]}


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            (self.root / "bin").mkdir()
            shutil.copyfile("/bin/sh", self.root / "bin" / "sh")
            (self.root / "bin" / "sh").chmod(0o700)
            self.provider = ColdProvider(self.root).start()
            configure(self.root, self.provider)
            path = self.root / "codex" / "config.toml"
            config = path.read_text().replace("[features]\n",
                "[features]\nenable_request_compression = false\n")
            path.write_text(config + "\n[analytics]\nenabled = false\n")
            atomic(self.root / "cold-crashes.json", [])
            self.record("cold_provider_ready", source_provider_requests=0, request_auth="none",
                        output="fixed_owned_command_then_assistant_only")
        except BaseException:
            self.close()
            raise

    def control(self, message):
        if message.get("op") == "crashNative":
            assert set(message) == {"id", "op"} and not self.closed
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            assert self.native is not None and self.native.poll() is None
            assert len(self.provider.requests) == 1
            assert not (self.root / "workspace" / "cold-command.txt").exists()
            native = self.native
            # Exact held process identity; never look up or signal another PID/group.
            native.kill()
            code = native.wait(timeout=5)
            assert code == -signal.SIGKILL
            self.native = None
            atomic(self.root / "cold-crashes.json", [{"native_pid": native.pid,
                                                       "returncode": code, "reaped": True}])
            self.record("native_crashed", pid=native.pid, returncode=code)
            self.record("control_done", id=message["id"], op=message["op"])
        else:
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
