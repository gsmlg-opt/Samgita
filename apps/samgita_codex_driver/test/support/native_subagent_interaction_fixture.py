#!/usr/bin/env python3
"""Local Responses-only MAv2 followup and live interrupt candidate (UNRUN).

Explicit encrypted_function_args=[] is the pinned router's plaintext message
contract. No encryption, app-server frames, shell calls or external service.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
from model_fixture import ModelFixture, response_events


ROOT = "OWNED_ACTIVITY_ROOT_V41"
CHILD = "OWNED_ACTIVITY_CHILD_V41"
CHILD_PATH = "/root/activity_child"
SPAWN = "owned-v41-spawn-activity"
WAIT = "owned-v41-wait-activity"
FOLLOWUP = "owned-v41-followup-activity"
INTERRUPT = "owned-v41-interrupt-activity"
FOLLOWUP_MESSAGE = "OWNED_ACTIVITY_FOLLOWUP_V41"
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
        item["call_id"]: (json.loads(item["output"]) if item["output"] else "")
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


class SubagentInteractionFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.state_lock = threading.Lock()
        self.release_child = threading.Event()
        self.closing = threading.Event()
        self.followup_started = threading.Event()
        self.observed = Path(requests_file).with_name("interaction-observed.json")
        self.state = {"root_requests": 0, "child_requests": 0,
                      "responses": [], "followup_held": False, "errors": []}
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
            item = self.response_item(index, request)
            if item is None:
                # Only owned shutdown releases the cancelled followup request.
                # No response headers, model answer, or app-server frame is emitted.
                return
            body = "".join(
                f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                for event in response_events(index, item)
            ).encode()
            handler.send_response(200)
            handler.send_header("Content-Type", "text/event-stream")
            handler.send_header("Content-Length", str(len(body)))
            handler.end_headers()
            handler.wfile.write(body)
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
            assert outputs(request) == {}, "Child must never run a tool"
            with self.state_lock:
                self.state["child_requests"] += 1
                step = self.state["child_requests"]
                assert step in (1, 2), "Unexpected extra child request"
                self.save_state()
            expected = [{"type": "input_text", "text": NEW_TASK}]
            if step == 1:
                assert len(messages) == 1, "Expected original native task envelope"
                assert messages[0]["content"] == expected
                assert self.release_child.wait(10), "Owned child-release barrier deadline"
                assert not self.closing.is_set(), "Closed before original child completion"
                self.record_response("child_final")
                return final_message("owned-v41-child-final", CHILD_ANSWER)
            assert len(messages) == 2, "Expected original and followup native task envelopes"
            assert messages[0]["content"] == expected
            assert messages[1]["content"] == [{
                "type": "input_text",
                "text": NEW_TASK.removesuffix(CHILD) + FOLLOWUP_MESSAGE,
            }], "Followup must reach the model through native delivery"
            with self.state_lock:
                self.state["followup_held"] = True
                self.save_state()
            self.followup_started.set()
            # Never send a successful answer into the interruption race.
            # The test reads native interrupted history before owned shutdown.
            assert self.closing.wait(30), "Owned followup shutdown deadline"
            return None

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
            assert {"spawn_agent", "wait_agent", "followup_task", "interrupt_agent"} <= names, "Missing native v2 tools"
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
        completed_values = {
            SPAWN: {"task_name": CHILD_PATH},
            WAIT: {"message": "Wait completed.", "timed_out": False},
        }
        if step == 3:
            assert values == completed_values, "Native wait must observe child completion"
            messages = agent_messages(request, CHILD_PATH, "/root")
            assert len(messages) == 1
            assert messages[0]["content"] == [
                {"type": "input_text", "text": FINAL_ANSWER}
            ], "Unexpected native completion envelope"
            self.record_response("followup")
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "followup_task", "call_id": FOLLOWUP,
                "encrypted_function_args": [],
                "arguments": json.dumps({
                    "target": CHILD_PATH, "message": FOLLOWUP_MESSAGE,
                }),
            }
        completed_values[FOLLOWUP] = ""
        if step == 4:
            assert values == completed_values, "Native followup submission failed"
            assert self.followup_started.wait(10), "Native followup model request deadline"
            self.record_response("interrupt")
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "interrupt_agent", "call_id": INTERRUPT,
                "arguments": json.dumps({"target": CHILD_PATH}),
            }
        assert step == 5, "Unexpected extra root request"
        completed_values[INTERRUPT] = {"previous_status": "running"}
        assert values == completed_values, "Native interrupt must inspect a running child"
        self.record_response("root_final")
        return final_message("owned-v41-root-final", ROOT_ANSWER)

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
    fixture = SubagentInteractionFixture(
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
