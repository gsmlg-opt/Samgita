#!/usr/bin/env python3
"""Two explicit sent-unconfirmed approval outcomes before owned SIGKILL.

Every native frame comes from stock Codex. No existing unanswered-crash control
is changed. This separate fixture inherits the same private namespace, UDS,
restart/stop ownership and bounded cleanup from the retained BEM controller.
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

INPUT = "Owned sent-unconfirmed cold approval"
COMMAND = "echo 'owned recovered command' >> loss-command.txt; printf samgita_loss_command"
ANSWER = "Owned sent-unconfirmed command finished"
ITEM = "sent-cold-command-1"
REASON = "Owned sent-unconfirmed approval only"


class SentProvider(ReviewProvider):
    def __init__(self, root):
        super().__init__(root, "inline")

    def write_response(self, handler, index, request):
        assert 1 <= index <= 2 and request["model"] == "mock-model", "Unexpected cold inference"
        texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                 for part in item.get("content", []) if part.get("type") == "input_text"]
        assert INPUT in texts, "Inference lacks the single explicit owned input"
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        marker = self.root / "workspace" / "loss-command.txt"
        if index == 1:
            assert outputs == [] and not marker.exists()
        else:
            assert len(outputs) == 1 and outputs[0]["call_id"] == ITEM
            assert marker.is_file() and not marker.is_symlink()
            assert marker.read_bytes() == b"owned recovered command\n"
        self.record("sent_model_request", index=index)
        ModelFixture.write_response(self, handler, index, request)

    def response_item(self, index, _request):
        if index == 1:
            return {"type": "function_call", "name": "exec_command", "call_id": ITEM,
                    "arguments": json.dumps({
                        "cmd": COMMAND, "workdir": str(self.root / "workspace"),
                        "shell": str(self.root / "bin" / "sh"), "login": False, "tty": False,
                        "sandbox_permissions": "require_escalated", "justification": REASON})}
        assert index == 2
        return {"type": "message", "role": "assistant", "id": "owned-sent-cold-answer",
                "content": [{"type": "output_text", "text": ANSWER}]}


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        self.branch = args.branch
        self.crashed = False
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            (self.root / "bin").mkdir()
            shutil.copyfile("/bin/sh", self.root / "bin" / "sh")
            (self.root / "bin" / "sh").chmod(0o700)
            self.provider = SentProvider(self.root).start()
            configure(self.root, self.provider)
            path = self.root / "codex" / "config.toml"
            config = path.read_text().replace("[features]\n",
                "[features]\nenable_request_compression = false\n")
            path.write_text(config + "\n[analytics]\nenabled = false\n")
            atomic(self.root / "sent-crashes.json", [])
            self.record("sent_provider_ready", branch=self.branch,
                        source_provider_requests=0, request_auth="none")
        except BaseException:
            self.close()
            raise

    def control(self, message):
        if message.get("op") == "crashSentUnconfirmed":
            assert set(message) == {"id", "op"} and not self.closed and not self.crashed
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            assert self.native is not None and self.native.poll() is None
            assert os.readlink(f"/proc/{self.native.pid}/ns/net") == self.proof["namespace"]
            marker = self.root / "workspace" / "loss-command.txt"
            expected = 1 if self.branch == "dropped" else 2
            assert len(self.provider.requests) == expected
            assert self.provider.errors == []
            if self.branch == "dropped":
                assert list((self.root / "workspace").iterdir()) == [] and not marker.exists()
            else:
                assert sorted(p.name for p in (self.root / "workspace").iterdir()) == ["loss-command.txt"]
                assert marker.is_file() and not marker.is_symlink()
                assert marker.read_bytes() == b"owned recovered command\n"
            native = self.native
            # Only this held live Popen, never a discovered PID or arbitrary process group.
            native.kill()
            code = native.wait(timeout=5)
            assert code == -signal.SIGKILL and native.poll() == code
            self.native = None
            self.crashed = True
            atomic(self.root / "sent-crashes.json", [{
                "native_pid": native.pid, "returncode": code, "reaped": True,
                "branch": self.branch, "provider_requests": expected}])
            self.record("native_crashed", pid=native.pid, returncode=code, branch=self.branch)
            self.record("control_done", id=message["id"], op=message["op"])
        else:
            # Keep the original BEM control allowlist and shutdown budgets.
            if message.get("op") == "restart":
                assert self.crashed and self.native is None
            super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--branch", choices=["dropped", "forwarded"], required=True)
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
        while True:
            line = sys.stdin.readline(1025)
            if not line:
                break
            assert len(line.encode()) <= 1024
            fixture.control(json.loads(line))
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


if __name__ == "__main__":
    main()
