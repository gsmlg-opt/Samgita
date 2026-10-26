#!/usr/bin/env python3
"""Responses SSE only; native Codex owns all child IDs, status and history."""
import argparse
import json
from pathlib import Path
import sys
import threading

from model_fixture import ModelFixture, response_events


ROOT = "OWNED_V359_ROOT"
CHILD_A = "OWNED_V359_CHILD_FAILURE"
CHILD_B = "OWNED_V359_CHILD_HELD"
FAILURE = "Owned V359 child failure."
ANSWER = "Owned V359 root continued after failure and shutdown."
CALLS = ["owned-v359-spawn-a", "owned-v359-wait-a", "owned-v359-close-a",
         "owned-v359-spawn-b", "owned-v359-close-b"]


def user_texts(request):
    return [part.get("text") for item in request.get("input", [])
            if item.get("role") == "user"
            for part in item.get("content", []) if isinstance(part, dict)]


def outputs(request):
    return {item["call_id"]: json.loads(item["output"])
            for item in request.get("input", [])
            if item.get("type") == "function_call_output"}


def child(values, call):
    identity = values[call].get("agent_id")
    assert isinstance(identity, str) and identity, "Missing native child ID"
    return identity


class CollaborationFailureRunningFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.state_lock = threading.Lock()
        self.b_requested = threading.Event()
        self.closing = threading.Event()
        self.observed = Path(requests_file).with_name("failure-running-observed.json")
        self.state = {"root_requests": 0, "child_a_requests": 0,
                      "child_b_requests": 0, "root_responses": [],
                      "failure_sent": False, "b_held": False,
                      "close_b_after_request": False, "errors": []}
        self.save_state()

    def save_state(self):
        temporary = self.observed.with_suffix(".partial")
        temporary.write_text(json.dumps(self.state))
        temporary.replace(self.observed)

    def record_root_response(self, name):
        with self.state_lock:
            self.state["root_responses"].append(name)
            self.save_state()

    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(config.read_text() + """
[agents]
enabled = true
max_depth = 2
max_concurrent_threads_per_session = 2
[features]
multi_agent = true
multi_agent_v2 = false
apps = false
shell_snapshot = false
""")

    def write_response(self, handler, index, request):
        try:
            latest = next((text for text in reversed(user_texts(request))
                           if text in (ROOT, CHILD_A, CHILD_B)), None)
            assert latest is not None, "Missing prescribed v1 input"
            assert request["model"] == "mock-model", "Unexpected model"
            assert request["reasoning"]["effort"] == "low", "Unexpected effort"
            if latest == CHILD_B:
                assert outputs(request) == {}, "Held child cannot execute tools"
                with self.state_lock:
                    self.state["child_b_requests"] += 1
                    assert self.state["child_b_requests"] == 1, "Repeated held child request"
                    self.state["b_held"] = True
                    self.save_state()
                self.b_requested.set()
                # No headers, successful answer or terminal SSE enters the
                # native close race. Only owned fixture teardown releases this.
                assert self.closing.wait(30), "Held child teardown deadline"
                return
            if latest == CHILD_A:
                assert outputs(request) == {}, "Failed child cannot execute tools"
                with self.state_lock:
                    self.state["child_a_requests"] += 1
                    assert self.state["child_a_requests"] == 1, "Repeated failed child request"
                    self.state["failure_sent"] = True
                    self.save_state()
                identity = "owned-v359-failed-response"
                events = [
                    {"type": "response.created", "response": {"id": identity}},
                    {"type": "response.failed", "response": {
                        "id": identity,
                        "error": {"code": "invalid_prompt", "message": FAILURE},
                    }},
                ]
            else:
                events = response_events(index, self.root_item(index, request))
            body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                           for event in events).encode()
            handler.send_response(200)
            handler.send_header("Content-Type", "text/event-stream")
            handler.send_header("Content-Length", str(len(body)))
            handler.end_headers()
            handler.wfile.write(body)
        except Exception as error:
            with self.state_lock:
                self.state["errors"].append({"type": type(error).__name__, "message": str(error)})
                self.save_state()
            handler.send_response(500)
            handler.end_headers()

    def root_item(self, index, request):
        with self.state_lock:
            self.state["root_requests"] += 1
            step = self.state["root_requests"]
            self.save_state()
        assert 1 <= step <= 6, "Unexpected extra root inference"
        values = outputs(request)
        assert list(values) == CALLS[:step - 1], "Unexpected native tool result order"
        if CALLS[0] in values:
            child(values, CALLS[0])
        if CALLS[1] in values:
            a = child(values, CALLS[0])
            assert values[CALLS[1]] == {
                "status": {a: {"errored": FAILURE}}, "timed_out": False,
            }, "Native wait did not preserve child failure"
        if CALLS[2] in values:
            assert values[CALLS[2]] == {"previous_status": {"errored": FAILURE}}
        if CALLS[3] in values:
            assert child(values, CALLS[3]) != child(values, CALLS[0]), "Child identity reused"
        if CALLS[4] in values:
            assert values[CALLS[4]] == {"previous_status": "running"}
        if step == 6:
            self.record_root_response("root_final")
            return {"type": "message", "role": "assistant", "id": f"owned-v359-root-{index}",
                    "content": [{"type": "output_text", "text": ANSWER}]}
        call = CALLS[step - 1]
        if step in (1, 4):
            name = "spawn_agent"
            arguments = {"message": CHILD_A if step == 1 else CHILD_B,
                         "fork_context": False, "model": "mock-model", "reasoning_effort": "low"}
        elif step == 2:
            name, arguments = "wait_agent", {"targets": [child(values, CALLS[0])]}
        else:
            if step == 5:
                assert self.b_requested.wait(10), "Native held-child request barrier deadline"
                assert not self.closing.is_set(), "Fixture closed before running snapshot"
                with self.state_lock:
                    self.state["close_b_after_request"] = True
                    self.save_state()
            name = "close_agent"
            arguments = {"target": child(values, CALLS[0 if step == 3 else 3])}
        self.record_root_response(call)
        return {"type": "function_call", "namespace": "multi_agent_v1",
                "name": name, "call_id": call, "arguments": json.dumps(arguments)}

    def close(self):
        # ThreadingHTTPServer waits for its handlers; signal before server_close.
        self.closing.set()
        super().close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = CollaborationFailureRunningFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
