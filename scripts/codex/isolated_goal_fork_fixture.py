#!/usr/bin/env python3
"""Owned native fork goal deferral; only three Responses answers are synthetic."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

from isolated_goal_budget_fixture import GoalBudgetProvider, text_parts
from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure


OBJECTIVE = "Owned synthetic fork continuation; retain the objective until its token budget stops work."
SOURCE = "synthetic:goal-fork:source"
EXPLICIT = "synthetic:goal-fork:explicit"
ANSWERS = ["Owned source fork baseline", "Owned explicit fork progress", "Owned fork budget stop"]


def usage(index):
    incoming, cached, outgoing = [(0, 0, 0), (7, 3, 5), (11, 2, 3)][index - 1]
    return {"input_tokens": incoming,
            "input_tokens_details": {"cached_tokens": cached, "cache_write_tokens": 0},
            "output_tokens": outgoing, "output_tokens_details": {"reasoning_tokens": 0},
            "total_tokens": incoming + outgoing}


def response_item(index):
    return {"type": "message", "role": "assistant", "id": f"owned-goal-fork-answer-{index}",
            "content": [{"type": "output_text", "text": ANSWERS[index - 1]}]}


class ForkProvider(GoalBudgetProvider):
    """Retain the bounded HTTP/auth/error handler; specialize only the journey."""

    def __init__(self, root):
        super().__init__(root)
        self.release_auto = threading.Event()
        self.source_thread, self.source_turn = None, None
        self.target_thread, self.explicit_turn = None, None

    def check_request(self, index, request):
        assert request["model"] == "mock-model" and isinstance(request["input"], list)
        assert not any(item.get("type") in {"function_call", "function_call_output",
                                            "custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"]), "No tool work is authorized"
        metadata = self.records[index - 1]["metadata"]
        texts = text_parts(request)
        if index == 1:
            self.source_thread, self.source_turn = metadata["thread_id"], metadata["turn_id"]
            assert metadata["turn_trigger"] == "owned_fork_source"
            assert texts.count(SOURCE) == 1 and EXPLICIT not in texts
            assert OBJECTIVE not in "\n".join(texts)
        else:
            if index == 2:
                self.target_thread, self.explicit_turn = metadata["thread_id"], metadata["turn_id"]
                assert self.target_thread != self.source_thread
                assert self.explicit_turn != self.source_turn
            assert metadata["thread_id"] == self.target_thread
            assert texts.count(SOURCE) == 1 and texts.count(EXPLICIT) == 1
            assert OBJECTIVE in "\n".join(texts)
            assert texts.count(ANSWERS[0]) == 1
            assert texts.index(SOURCE) < texts.index(ANSWERS[0]) < texts.index(EXPLICIT)
            if index == 2:
                assert metadata["turn_trigger"] == "owned_fork_explicit"
                assert ANSWERS[1] not in texts
                assert "Continue working toward the active thread goal." not in "\n".join(texts)
            else:
                assert metadata["turn_id"] != self.explicit_turn
                assert metadata["turn_trigger"] == "goal"
                assert texts.count(ANSWERS[1]) == 1
                assert texts.index(EXPLICIT) < texts.index(ANSWERS[1])
                continuation = [part for part in texts
                                if "Continue working toward the active thread goal." in part]
                assert len(continuation) == 1
                assert OBJECTIVE in continuation[0]
                assert "- Tokens used: 9\n- Token budget: 20\n- Tokens remaining: 11" in continuation[0]
                assert texts.index(ANSWERS[1]) < texts.index(continuation[0])

    def write_response(self, handler, index, request):
        self.check_request(index, request)
        if index == 3:
            with self.record_lock:
                self.records[index - 1]["waitingForRelease"] = True
                atomic(self.root / "goal-http.json", self.records)
            assert self.release_auto.wait(10), "Owned automatic-response barrier deadline"
            assert not self.closing.is_set(), "Owned provider closed before release"
        identity = f"owned-goal-fork-response-{index}"
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": response_item(index)},
            {"type": "response.completed", "response": {"id": identity, "usage": usage(index)}},
        ]
        raw = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                      for event in events).encode()
        with self.record_lock:
            self.records[index - 1].update({
                "rawResponseBase64": base64.b64encode(raw).decode(),
                "rawResponseSHA256": hashlib.sha256(raw).hexdigest()})
            atomic(self.root / "goal-http.json", self.records)
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(raw)))
        handler.end_headers()
        handler.wfile.write(raw)
        handler.wfile.flush()
        with self.record_lock:
            self.records[index - 1]["responded"] = True
            atomic(self.root / "goal-http.json", self.records)

    def close(self):
        self.closing.set()
        self.release_auto.set()
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
            self.provider = ForkProvider(self.root).start()
            configure(self.root, self.provider)
            path = self.root / "codex/config.toml"
            config = path.read_text().replace("[features]\n", "[features]\n"
                "goals = true\nenable_request_compression = false\nhooks = false\n"
                "remote_models = false\nshell_tool = false\nunified_exec = false\n"
                "browser_use = false\ncomputer_use = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                            + config + "\n[goals]\nmax_goal_token_budget = 20\n"
                            "\n[analytics]\nenabled = false\n")
            self.config = path.read_bytes()
            self.catalog = (self.root / "codex/models.json").read_bytes()
            self.record("goal_fork_provider_ready", source_provider_requests=0,
                        request_auth="none", request_budget=3)
        except BaseException:
            self.close()
            raise

    def start_native(self):
        assert not self.provider.fatal.is_set(), "Failed fixture cannot restart"
        assert (self.root / "codex/config.toml").read_bytes() == self.config
        assert (self.root / "codex/models.json").read_bytes() == self.catalog
        assert not (self.root / "codex/auth.json").exists()
        super().start_native()
        assert os.readlink(f"/proc/{self.native.pid}/ns/net") == self.proof["namespace"]

    def control(self, message):
        assert len(self.journal) < 48, "Owned controller journal bound"
        assert not self.provider.fatal.is_set(), "Failed fixture control"
        if message.get("op") == "release_auto":
            assert set(message) == {"id", "op"} and isinstance(message["id"], str)
            assert 0 < len(message["id"]) <= 80 and not self.provider.release_auto.is_set()
            with self.provider.record_lock:
                assert self.provider.attempts == 3 and len(self.provider.records) == 3
                last = self.provider.records[-1]
                assert last["waitingForRelease"] and not last["responded"]
                assert last["metadata"]["turn_trigger"] == "goal"
            self.provider.release_auto.set()
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
    for name in ["config.toml", "managed_config.toml", "requirements.toml"]:
        assert not (Path("/etc/codex") / name).exists(), "BLOCKED_ENV: host managed config present"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = None

    def terminate(_signum, _frame):
        failed = fixture is not None and fixture.provider.fatal.is_set()
        raise SystemExit(1 if failed else 0)

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
