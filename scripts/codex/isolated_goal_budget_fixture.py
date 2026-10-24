#!/usr/bin/env python3
"""Stock native goal continuation and cached-token budget stop.

Only provider SSE is synthetic. No app-server frame or external service is faked.
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
import threading
import time

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture


OBJECTIVE = ("Owned synthetic continuation accounting; preserve the objective "
             "until the token budget stops work.")
FIRST = "Owned synthetic first goal turn recorded."
FINAL = "Owned synthetic budget run stopped with the objective retained."
CALL_ID = "owned-active-goal-read-1"


def usage(index):
    incoming, cached, outgoing = {1: (7, 3, 5), 2: (0, 0, 0), 3: (11, 2, 3)}[index]
    return {"input_tokens": incoming,
            "input_tokens_details": {"cached_tokens": cached, "cache_write_tokens": 0},
            "output_tokens": outgoing, "output_tokens_details": {"reasoning_tokens": 0},
            "total_tokens": incoming + outgoing}


def response_item(index):
    if index == 2:
        return {"type": "function_call", "name": "get_goal", "call_id": CALL_ID,
                "arguments": "{}"}
    suffix, text = (1, FIRST) if index == 1 else (2, FINAL)
    return {"type": "message", "role": "assistant",
            "id": f"owned-active-goal-progress-{suffix}",
            "content": [{"type": "output_text", "text": text}]}


def text_parts(request):
    return [part["text"] for item in request["input"]
            for part in item.get("content", [])
            if part.get("type") in {"input_text", "output_text"}]


def named_tools(value, name):
    if isinstance(value, dict):
        found = [value] if value.get("name") == name and value.get("type") == "function" else []
        return found + [item for child in value.values() for item in named_tools(child, name)]
    if isinstance(value, list):
        return [item for child in value for item in named_tools(child, name)]
    return []


class GoalBudgetProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("assistant", root / "workspace", root / "requests.json")
        self.root, self.records, self.errors = root, [], []
        self.record_lock = threading.Lock()
        self.closing, self.fatal = threading.Event(), threading.Event()
        self.attempts, self.created_monotonic = 0, time.monotonic()
        self.thread_id, self.first_turn, self.second_turn = None, None, None
        self.server.daemon_threads = True
        for name, value in [("requests.json", []), ("goal-http.json", []),
                            ("provider-errors.json", []), ("goal-attempts.json", 0)]:
            atomic(root / name, value)
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
                    with provider.lock:
                        assert not provider.fatal.is_set(), "Owned provider already failed"
                        provider.attempts += 1
                        index = provider.attempts
                        atomic(root / "goal-attempts.json", index)
                    assert self.path == "/v1/responses", "Unapproved POST path"
                    assert self.headers.get("Authorization") is None, "Unexpected authentication"
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
                    arrived = time.monotonic()
                    with provider.record_lock:
                        assert len(provider.records) < 4, "Owned HTTP evidence bound"
                        provider.records.append({
                            "index": index, "metadata": metadata, "path": self.path,
                            "requestAuth": "none", "responded": False,
                            "arrivalMonotonic": arrived,
                            "rawBodyBase64": base64.b64encode(raw).decode(),
                            "rawBodySHA256": hashlib.sha256(raw).hexdigest()})
                        atomic(root / "goal-http.json", provider.records)
                    assert index <= 3, "Responses request budget exceeded: fourth request"
                    with provider.lock:
                        provider.requests.append(request)
                        atomic(provider.requests_file, provider.requests)
                    provider.write_response(self, index, request)
                except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
                    if not provider.closing.is_set():
                        provider.reject(self, type(error).__name__ + ": " + str(error))

        self.server.RequestHandlerClass = Handler

    def reject(self, handler, message):
        with self.record_lock:
            if len(self.errors) < 8:
                self.errors.append(message)
                atomic(self.root / "provider-errors.json", self.errors)
            self.fatal.set()
        # The controller's existing finally path reaps only its owned native PID.
        # Never supply a fourth synthetic answer or retryable HTTP error stream.
        handler.close_connection = True
        os.kill(os.getpid(), signal.SIGTERM)

    def check_request(self, index, request):
        assert request["model"] == "mock-model"
        assert isinstance(request["input"], list)
        assert not any(item.get("type") in {"custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"]), "Unexpected custom tool"
        metadata = self.records[index - 1]["metadata"]
        assert metadata["turn_trigger"] == "goal", "Non-goal native inference"
        if index == 1:
            self.thread_id, self.first_turn = metadata["thread_id"], metadata["turn_id"]
        assert metadata["thread_id"] == self.thread_id
        if index == 2:
            self.second_turn = metadata["turn_id"]
            assert self.second_turn != self.first_turn, "No actual second goal turn"
        if index == 3:
            assert metadata["turn_id"] == self.second_turn
        joined = "\n".join(text_parts(request))
        assert OBJECTIVE in joined
        if index <= 2:
            used, remaining = (0, 20) if index == 1 else (9, 11)
            assert "Continue working toward the active thread goal." in joined
            assert (f"- Tokens used: {used}\n- Token budget: 20\n"
                    f"- Tokens remaining: {remaining}") in joined
        for name in ["get_goal", "create_goal", "update_goal"]:
            assert len(named_tools(request["tools"], name)) == 1, "Missing stock goal tool"
        tool = named_tools(request["tools"], "get_goal")[0]
        assert tool["strict"] is False
        assert tool["parameters"] == {"type": "object", "properties": {},
                                      "required": [], "additionalProperties": False}
        calls = [item for item in request["input"] if item.get("type") == "function_call"]
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        if index < 3:
            assert calls == [] and outputs == []
        else:
            self.check_tool_result(calls, outputs)
        assistants = [(ordinal, item) for ordinal, item in enumerate(request["input"])
                      if item.get("type") == "message" and item.get("role") == "assistant"]
        if index == 1:
            assert assistants == []
        else:
            assert len(assistants) == 1, "Unexpected assistant replay count"
            ordinal, message = assistants[0]
            assert message["content"] == [{"type": "output_text", "text": FIRST}]
            # Public/history IDs remain exact. The stock request-copy preparer
            # removes unprefixed provider IDs before subsequent model requests.
            assert "id" not in message, "Unprefixed ID unexpectedly sent to provider"
            if index == 2:
                continuation = [position for position, item in enumerate(request["input"])
                                if any(part.get("type") == "input_text"
                                       and "- Tokens used: 9\n- Token budget: 20\n"
                                           "- Tokens remaining: 11" in part.get("text", "")
                                       for part in item.get("content", []))]
                assert len(continuation) == 1 and ordinal < continuation[0]
            else:
                call_ordinal = request["input"].index(calls[0])
                output_ordinal = request["input"].index(outputs[0])
                assert ordinal < call_ordinal < output_ordinal

    def check_tool_result(self, calls, outputs):
        assert len(calls) == 1 and len(outputs) == 1
        call, output = calls[0], outputs[0]
        assert call["name"] == "get_goal" and call.get("namespace") is None
        assert call["call_id"] == CALL_ID and json.loads(call["arguments"]) == {}
        assert output["call_id"] == CALL_ID and isinstance(output["output"], str)
        result = json.loads(output["output"])
        assert set(result) == {"goal", "remainingTokens", "completionBudgetReport"}
        assert result["remainingTokens"] == 11 and result["completionBudgetReport"] is None
        goal = result["goal"]
        assert set(goal) == {"threadId", "objective", "status", "tokenBudget", "tokensUsed",
                             "timeUsedSeconds", "createdAt", "updatedAt"}
        assert goal["threadId"] == self.thread_id and goal["objective"] == OBJECTIVE
        assert goal["status"] == "active" and goal["tokenBudget"] == 20
        assert goal["tokensUsed"] == 9
        assert all(type(goal[key]) is int for key in
                   ["tokenBudget", "tokensUsed", "timeUsedSeconds", "createdAt", "updatedAt"])
        # Native goal activation precedes the first provider request; arrival is
        # not its clock baseline. Provider creation is an independent earlier
        # bound; the Elixir oracle additionally bounds from the activation RPC.
        assert 1 <= goal["timeUsedSeconds"] <= int(time.monotonic() - self.created_monotonic) + 1
        assert 0 < goal["createdAt"] <= goal["updatedAt"]

    def write_response(self, handler, index, request):
        self.check_request(index, request)
        delay = 0.0
        if index == 1:
            before = time.monotonic()
            assert not self.closing.wait(1.25), "Owned fixture closed during measured delay"
            delay = time.monotonic() - before
            assert 1.25 <= delay < 3, "Owned elapsed-time measurement bound"
        identity = f"owned-active-goal-response-{index}"
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": response_item(index)},
            {"type": "response.completed", "response": {"id": identity, "usage": usage(index)}},
        ]
        raw = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                      for event in events).encode()
        with self.record_lock:
            self.records[index - 1].update({
                "delayElapsedSeconds": delay,
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
            self.provider = GoalBudgetProvider(self.root).start()
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
            self.record("goal_provider_ready", source_provider_requests=0,
                        request_auth="none", request_budget=3,
                        output="fixed_assistant_get_goal_assistant")
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
        super().control(message)

    def close(self):
        if isinstance(self.provider, GoalBudgetProvider):
            self.provider.closing.set()
        super().close()


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
