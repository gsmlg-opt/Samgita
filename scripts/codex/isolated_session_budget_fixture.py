#!/usr/bin/env python3
"""One owned native session-budget failure; only the Responses SSE is synthetic."""
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

from isolated_goal_budget_fixture import GoalBudgetProvider, Fixture as GoalFixture, named_tools
from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure

INPUT = "Owned synthetic session-budget input; no tools or external work."
ANSWER = "Owned synthetic session-budget response."
REMINDER = ("<rollout_budget>\nYou have 30 weighted tokens left in the shared session "
            "token budget.\n</rollout_budget>")
USAGE = {"input_tokens": 7,
         "input_tokens_details": {"cached_tokens": 3, "cache_write_tokens": 0},
         "output_tokens": 26, "output_tokens_details": {"reasoning_tokens": 0},
         "total_tokens": 33}


class SessionBudgetProvider(GoalBudgetProvider):
    # The inherited HTTP handler counts attempts before validation and kills only
    # this owned fixture on a second attempt. It never answers over-budget work.
    request_limit = 1
    output_label = "fixed_session_budget_completion"

    def check_request(self, index, request):
        assert index == 1 and request["model"] == "mock-model"
        assert isinstance(request["input"], list)
        metadata = self.records[index - 1]["metadata"]
        assert metadata["turn_trigger"] == "user"
        user = [part.get("text") for item in request["input"] if item.get("role") == "user"
                for part in item.get("content", []) if isinstance(part, dict)]
        developer = [part.get("text") for item in request["input"]
                     if item.get("role") == "developer"
                     for part in item.get("content", []) if isinstance(part, dict)]
        assert user.count(INPUT) == 1
        assert developer.count(REMINDER) == 1, "Missing native shared-budget reminder"
        assert not any(item.get("type") in {"function_call", "function_call_output",
                                          "custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"])
        for tool in ["get_goal", "create_goal", "update_goal", "spawn_agent", "wait_agent"]:
            assert named_tools(request["tools"], tool) == [], "Unexpected goal/subagent tool"

    def write_response(self, handler, index, request):
        self.check_request(index, request)
        identity = "owned-session-budget-response"
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": {
                "type": "message", "role": "assistant", "id": "owned-session-budget-message",
                "content": [{"type": "output_text", "text": ANSWER}]}},
            {"type": "response.completed", "response": {"id": identity, "usage": USAGE}},
        ]
        raw = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                      for event in events).encode()
        with self.record_lock:
            self.records[index - 1].update({
                "status": 200, "rawResponseBase64": base64.b64encode(raw).decode(),
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


class Fixture(GoalFixture):
    def __init__(self, args, proof):
        # Reuse the proven native/namespace owner; no goal is enabled or created.
        BemFixture.__init__(
            self, argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            (self.root / "bin").mkdir()
            shutil.copyfile("/bin/sh", self.root / "bin/sh")
            (self.root / "bin/sh").chmod(0o700)
            self.provider = SessionBudgetProvider(self.root).start()
            configure(self.root, self.provider)
            path = self.root / "codex/config.toml"
            config = path.read_text().replace("[features]\n", "[features]\n"
                "goals = false\nmulti_agent = false\nmulti_agent_v2 = false\n"
                "enable_request_compression = false\nhooks = false\nremote_models = false\n"
                "shell_tool = false\nunified_exec = false\nbrowser_use = false\ncomputer_use = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                            + config + "\n[features.rollout_budget]\nenabled = true\n"
                            "limit_tokens = 30\nreminder_at_remaining_tokens = [20, 10]\n"
                            "sampling_token_weight = 1.0\nprefill_token_weight = 1.0\n"
                            "\n[analytics]\nenabled = false\n")
            self.config = path.read_bytes()
            self.catalog = (self.root / "codex/models.json").read_bytes()
            self.record("session_budget_provider_ready", source_provider_requests=0,
                        request_auth="none", request_budget=1, output=self.provider.output_label)
        except BaseException:
            self.close()
            raise

    def start_native(self):
        assert self.native_pids == [], "Only one owned native launch is allowed"
        super().start_native()

    def control(self, message):
        assert message.get("op") in {"barrier", "close"}, "Restart is outside this fixture"
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
        failed = fixture is not None and fixture.provider.fatal.is_set()
        raise SystemExit(1 if failed else 0)

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
