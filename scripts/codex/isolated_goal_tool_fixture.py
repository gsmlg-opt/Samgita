#!/usr/bin/env python3
"""Seven bounded provider replies exercise real stock native goal tools.

Only Responses SSE is synthetic; no app-server or goal state is fabricated.
"""
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
import time

from isolated_goal_budget_fixture import (
    Fixture as BudgetFixture, GoalBudgetProvider, named_tools, text_parts,
)
from isolated_realtime_bem_fixture import SHA, atomic, isolation


OBJECTIVES = {
    "A": "Owned synthetic goal A: observe rejection without replacement.",
    "B": "Owned synthetic goal B: observe a fresh accounting baseline.",
}
INPUT = ("Explicitly create goal A with token budget 100: " + OBJECTIVES["A"]
         + " Then deliberately attempt the rejected replacement A probe. "
         "Complete A after observing rejection. Explicitly create replacement goal B "
         "with token budget 200: " + OBJECTIVES["B"]
         + " Then deliberately attempt the rejected replacement B probe and complete B "
         "after observing rejection. Report the native structured usage. "
         "This authorizes only these synthetic goal tools, no commands or external work.")
FINAL = ("Synthetic goal A completed using 9 of 100 tokens; "
         "replacement goal B completed using 12 of 200 tokens.")
ERROR = ("cannot create a new goal because this thread has an unfinished goal; "
         "complete the existing goal first")
REPORT = ("Goal achieved. Report final usage from this tool result's structured goal fields. "
          "If `goal.tokenBudget` is present, include token usage from `goal.tokensUsed` "
          "and `goal.tokenBudget`. If `goal.timeUsedSeconds` is greater than 0, summarize "
          "elapsed time in a concise, human-friendly form appropriate to the response language.")
CALLS = [
    ("create_goal", "owned-goal-create-a", {"objective": OBJECTIVES["A"], "token_budget": 100}),
    ("create_goal", "owned-goal-reject-a", {
        "objective": "Rejected replacement A must never become the goal.", "token_budget": 99}),
    ("update_goal", "owned-goal-complete-a", {"status": "complete"}),
    ("create_goal", "owned-goal-create-b", {"objective": OBJECTIVES["B"], "token_budget": 200}),
    ("create_goal", "owned-goal-reject-b", {
        "objective": "Rejected replacement B must never become the goal.", "token_budget": 199}),
    ("update_goal", "owned-goal-complete-b", {"status": "complete"}),
]


def usage(index):
    incoming, cached, outgoing = {2: (7, 3, 5), 5: (11, 2, 3)}.get(index, (0, 0, 0))
    return {"input_tokens": incoming,
            "input_tokens_details": {"cached_tokens": cached, "cache_write_tokens": 0},
            "output_tokens": outgoing, "output_tokens_details": {"reasoning_tokens": 0},
            "total_tokens": incoming + outgoing}


def response_item(index):
    if index == 7:
        return {"type": "message", "role": "assistant", "id": "owned-goal-final-1",
                "content": [{"type": "output_text", "text": FINAL}]}
    name, call_id, arguments = CALLS[index - 1]
    return {"type": "function_call", "name": name, "call_id": call_id,
            "arguments": json.dumps(arguments, separators=(",", ":"))}


class GoalToolProvider(GoalBudgetProvider):
    request_limit = 7
    output_label = "fixed_create_reject_complete_replace_reject_complete_final"

    def __init__(self, root):
        super().__init__(root)
        self.turn_id = None
        self.creations, self.completions = {}, {}

    def check_request(self, index, request):
        assert request["model"] == "mock-model" and isinstance(request["input"], list)
        metadata = self.records[index - 1]["metadata"]
        assert metadata["turn_trigger"] == "user", "Unexpected automatic/secondary turn"
        if index == 1:
            self.thread_id, self.turn_id = metadata["thread_id"], metadata["turn_id"]
        assert (metadata["thread_id"], metadata["turn_id"]) == (self.thread_id, self.turn_id)
        assert INPUT in text_parts(request), "Explicit synthetic authorization absent"
        assert not any(item.get("type") in {"custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"])
        assert not any(item.get("type") == "message" and item.get("role") == "assistant"
                       for item in request["input"]), "Unexpected assistant continuation"
        self.check_specs(request["tools"])
        calls = [item for item in request["input"] if item.get("type") == "function_call"]
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        assert len(calls) == len(outputs) == index - 1, "Unexpected replay count"
        previous_ordinal = -1
        for ordinal, (call, output) in enumerate(zip(calls, outputs), 1):
            expected = response_item(ordinal)
            assert call["name"] == expected["name"] and call.get("namespace") is None
            assert call["call_id"] == expected["call_id"] == output["call_id"]
            assert json.loads(call["arguments"]) == CALLS[ordinal - 1][2]
            call_position = request["input"].index(call)
            output_position = request["input"].index(output)
            assert previous_ordinal < call_position < output_position
            previous_ordinal = output_position
            assert isinstance(output["output"], str)
            self.check_result(ordinal, output["output"])

    @staticmethod
    def check_specs(tools):
        for name in ["get_goal", "create_goal", "update_goal"]:
            found = named_tools(tools, name)
            assert len(found) == 1 and found[0]["strict"] is False
            parameters = found[0]["parameters"]
            assert parameters["type"] == "object" and parameters["additionalProperties"] is False
            properties = parameters["properties"]
            if name == "get_goal":
                assert parameters == {"type": "object", "properties": {},
                                      "required": [], "additionalProperties": False}
            elif name == "create_goal":
                assert parameters["required"] == ["objective"]
                assert set(properties) == {"objective", "token_budget"}
                assert properties["objective"]["type"] == "string"
                assert properties["token_budget"]["type"] == "integer"
            else:
                assert parameters["required"] == ["status"] and set(properties) == {"status"}
                assert properties["status"]["type"] == "string"
                assert properties["status"]["enum"] == ["complete", "blocked", "paused"]

    def check_result(self, ordinal, output):
        if ordinal in {2, 5}:
            assert output == ERROR, "Unfinished goal unexpectedly replaced"
            return
        result = json.loads(output)
        assert set(result) == {"goal", "remainingTokens", "completionBudgetReport"}
        key = "A" if ordinal < 4 else "B"
        complete = ordinal in {3, 6}
        budget, tokens = (100, 9 if complete else 0) if key == "A" else (200, 12 if complete else 0)
        assert type(result["remainingTokens"]) is int
        assert result["remainingTokens"] == budget - tokens
        assert result["completionBudgetReport"] == (REPORT if complete else None)
        goal = result["goal"]
        assert set(goal) == {"threadId", "objective", "status", "tokenBudget", "tokensUsed",
                             "timeUsedSeconds", "createdAt", "updatedAt"}
        assert goal["threadId"] == self.thread_id and goal["objective"] == OBJECTIVES[key]
        assert goal["status"] == ("complete" if complete else "active")
        assert goal["tokenBudget"] == budget and goal["tokensUsed"] == tokens
        assert all(type(goal[field]) is int for field in
                   ["tokenBudget", "tokensUsed", "timeUsedSeconds", "createdAt", "updatedAt"])
        creation_ordinal = 1 if key == "A" else 4
        before = self.records[creation_ordinal - 1]["responseWall"]
        assert int(before) <= goal["createdAt"] <= goal["updatedAt"] <= int(time.time())
        assert 0 <= goal["timeUsedSeconds"] <= int(time.monotonic() - self.created_monotonic) + 1
        if not complete:
            assert goal["timeUsedSeconds"] == 0
            if key in self.creations:
                assert goal == self.creations[key]
            self.creations[key] = goal
            if key == "B":
                assert goal["createdAt"] >= self.creations["A"]["createdAt"]
        else:
            assert goal["createdAt"] == self.creations[key]["createdAt"]
            if key in self.completions:
                assert goal == self.completions[key]
            self.completions[key] = goal
        atomic(self.root / "goal-tool-results.json", {
            "creations": self.creations, "completions": self.completions})

    def write_response(self, handler, index, request):
        self.check_request(index, request)
        identity = f"owned-goal-tool-response-{index}"
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": response_item(index)},
            {"type": "response.completed", "response": {"id": identity, "usage": usage(index)}},
        ]
        raw = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                      for event in events).encode()
        with self.record_lock:
            self.records[index - 1].update({
                "responseWall": time.time(), "responseMonotonic": time.monotonic(),
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


class Fixture(BudgetFixture):
    def __init__(self, args, proof):
        budget_args = argparse.Namespace(root=args.root, codex=args.codex, scenario="budget")
        super().__init__(budget_args, proof)
        try:
            old_url = self.provider.url
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            self.provider = GoalToolProvider(self.root).start()
            config = self.config.decode()
            assert config.count(old_url) == 3
            assert config.count("max_goal_token_budget = 20\n") == 1
            config = config.replace(old_url, self.provider.url).replace(
                "max_goal_token_budget = 20\n", "max_goal_token_budget = 200\n")
            (self.root / "codex/config.toml").write_text(config)
            self.config = config.encode()
            self.record("goal_tool_provider_ready", source_provider_requests=0,
                        request_auth="none", request_budget=self.provider.request_limit,
                        output=self.provider.output_label)
        except BaseException:
            self.close()
            raise


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
