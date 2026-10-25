#!/usr/bin/env python3
"""One local Responses-only MAv2 spawn; native Codex owns all agent events.

Explicit encrypted_function_args=[] is the pinned router's plaintext message
contract. No encryption, app-server frames, shell calls or external service.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
from model_fixture import ModelFixture


ROOT = "OWNED_ACTIVITY_ROOT_V39"
CHILD = "OWNED_ACTIVITY_CHILD_V39"
CHILD_PATH = "/root/activity_child"
SPAWN = "owned-v39-spawn-activity"
WAIT = "owned-v39-wait-activity"
CHILD_ANSWER = "Owned activity child done"
ROOT_ANSWER = "Owned activity root done"
NEW_TASK = (
    "Message Type: NEW_TASK\nTask name: /root/activity_child\n"
    "Sender: /root\nPayload:\n" + CHILD
)
FINAL_ANSWER = (
    "Message Type: FINAL_ANSWER\nTask name: /root\n"
    "Sender: /root/activity_child\nPayload:\n" + CHILD_ANSWER
)


def outputs(request):
    return {
        item["call_id"]: json.loads(item["output"])
        for item in request.get("input", [])
        if item.get("type") == "function_call_output"
    }


def agent_messages(request, author, recipient):
    return [
        item for item in request.get("input", [])
        if item.get("type") == "agent_message"
        and item.get("author") == author
        and item.get("recipient") == recipient
    ]


def final_message(identity, text):
    return {
        "type": "message", "role": "assistant", "id": identity,
        "content": [{"type": "output_text", "text": text}],
    }


class SubagentActivityFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.state_lock = threading.Lock()
        self.release_child = threading.Event()
        self.closing = threading.Event()
        self.observed = Path(requests_file).with_name("activity-observed.json")
        self.state = {"root_requests": 0, "child_requests": 0,
                      "responses": [], "errors": []}
        with self.state_lock:
            self.save_state()

    def save_state(self):
        temporary = self.observed.with_suffix(".partial")
        temporary.write_text(json.dumps(self.state))
        temporary.replace(self.observed)

    def record_response(self, stage):
        with self.state_lock:
            self.state["responses"].append(stage)
            self.save_state()

    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(
            'cli_auth_credentials_store = "ephemeral"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + config.read_text()
            + "\n[agents]\nenabled = true\nmax_depth = 1\n"
            "max_concurrent_threads_per_session = 2\n"
            "[features]\nmulti_agent = true\nmulti_agent_v2 = true\n"
            "apps = false\nplugins = false\nrecommended_plugins = false\n"
            "shell_snapshot = false\n"
        )

    def write_response(self, handler, index, request):
        try:
            super().write_response(handler, index, request)
        except Exception as error:
            with self.state_lock:
                self.state["errors"].append(
                    {"type": type(error).__name__, "message": str(error)}
                )
                self.save_state()
            handler.send_response(500)
            handler.end_headers()

    def response_item(self, _index, request):
        assert request["model"] == "mock-model", "Unexpected owned model"
        assert request["reasoning"]["effort"] == "medium", "Unexpected owned effort"
        root = any(
            part.get("text") == ROOT
            for item in request.get("input", []) if item.get("role") == "user"
            for part in item.get("content", []) if isinstance(part, dict)
        )
        if not root:
            messages = agent_messages(request, "/root", CHILD_PATH)
            assert len(messages) == 1, "Expected exactly one owned native child message"
            assert messages[0]["content"] == [
                {"type": "input_text", "text": NEW_TASK}
            ], "Native child must receive the source-prescribed plaintext envelope"
            assert outputs(request) == {}, "Child must never run a tool"
            with self.state_lock:
                self.state["child_requests"] += 1
                assert self.state["child_requests"] == 1, "Unexpected extra child request"
                self.save_state()
            # Do not hold either state_lock or ModelFixture.lock across this wait.
            assert self.release_child.wait(10), "Owned child-release barrier deadline"
            assert not self.closing.is_set(), "Owned provider closed before child release"
            self.record_response("child_final")
            return final_message("owned-v39-child-final", CHILD_ANSWER)

        with self.state_lock:
            self.state["root_requests"] += 1
            step = self.state["root_requests"]
            self.save_state()
        values = outputs(request)
        if step == 1:
            assert values == {}, "Root first request already has tool effects"
            namespaces = [tool for tool in request["tools"]
                          if tool.get("name") == "collaboration"]
            assert len(namespaces) == 1, "Missing native collaboration namespace"
            names = {tool["name"] for tool in namespaces[0]["tools"]}
            assert {"spawn_agent", "wait_agent"} <= names, "Missing native v2 tools"
            self.record_response("spawn")
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "spawn_agent", "call_id": SPAWN,
                # Some(empty), unlike omission, selects DirectPlaintextMessage.
                "encrypted_function_args": [],
                "arguments": json.dumps({
                    "task_name": "activity_child", "message": CHILD,
                    "fork_turns": "none", "model": "mock-model",
                    "reasoning_effort": "medium",
                }),
            }
        if step == 2:
            assert values == {SPAWN: {"task_name": CHILD_PATH}}, "Native v2 spawn failed"
            # Native emits Started before returning the successful spawn output.
            self.record_response("wait")
            self.release_child.set()
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "wait_agent", "call_id": WAIT,
                "arguments": json.dumps({"timeout_ms": 10000}),
            }
        assert step == 3, "Unexpected extra root request"
        assert values == {
            SPAWN: {"task_name": CHILD_PATH},
            WAIT: {"message": "Wait completed.", "timed_out": False},
        }, "Native wait must observe the child's completion mailbox message"
        messages = agent_messages(request, CHILD_PATH, "/root")
        assert len(messages) == 1, "Expected exactly one native completion message"
        assert messages[0]["content"] == [
            {"type": "input_text", "text": FINAL_ANSWER}
        ], "Unexpected native completion envelope"
        self.record_response("root_final")
        return final_message("owned-v39-root-final", ROOT_ANSWER)

    def close(self):
        self.closing.set()
        self.release_child.set()
        super().close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = SubagentActivityFixture(
        args.scenario, args.workspace, args.requests_file
    ).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
