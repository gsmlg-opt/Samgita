#!/usr/bin/env python3
"""Responses-only child lifecycle; native Codex owns provenance and history."""
import argparse
import json
from pathlib import Path
import sys
import threading

from model_fixture import ModelFixture


ROOT = "Owned source provenance root λ"
CHILD = "Owned source provenance child 🙂"
CHILD_PATH = "/root/search_child"
CHILD_ANSWER = CHILD + " done"
ROOT_ANSWER = "Owned source provenance root done"
SPAWN = "owned-provenance-spawn"
WAIT = "owned-provenance-wait"
NEW_TASK = (
    "Message Type: NEW_TASK\nTask name: /root/search_child\n"
    "Sender: /root\nPayload:\n" + CHILD
)
FINAL_ANSWER = (
    "Message Type: FINAL_ANSWER\nTask name: /root\n"
    "Sender: /root/search_child\nPayload:\n" + CHILD_ANSWER
)


def outputs(request):
    return {item["call_id"]: json.loads(item["output"])
            for item in request.get("input", [])
            if item.get("type") == "function_call_output"}


def messages(request, author, recipient):
    return [item for item in request.get("input", [])
            if item.get("type") == "agent_message"
            and item.get("author") == author
            and item.get("recipient") == recipient]


def answer(identity, text):
    return {"type": "message", "role": "assistant", "id": identity,
            "content": [{"type": "output_text", "text": text}]}


class ProvenanceFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.state_lock = threading.Lock()
        self.release_child = threading.Event()
        self.closing = threading.Event()
        self.observed = Path(requests_file).with_name("provenance-observed.json")
        self.state = {"root_requests": 0, "child_requests": 0, "errors": []}
        self.save_state()

    def save_state(self):
        temporary = self.observed.with_suffix(".partial")
        temporary.write_text(json.dumps(self.state))
        temporary.replace(self.observed)

    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(
            'cli_auth_credentials_store = "ephemeral"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + config.read_text()
            + "\n[agents]\nenabled = true\nmax_depth = 1\n"
            "max_concurrent_threads_per_session = 2\n"
            '[agents.source_fixture]\n'
            'description = "Owned child provenance fixture"\n'
            'nickname_candidates = ["OwnedSearchChild"]\n'
            "[features]\nmulti_agent = true\nmulti_agent_v2 = true\n"
            "apps = false\nplugins = false\nrecommended_plugins = false\n"
            "shell_snapshot = false\n"
        )

    def write_response(self, handler, index, request):
        try:
            super().write_response(handler, index, request)
        except Exception as error:
            with self.state_lock:
                self.state["errors"].append(type(error).__name__)
                self.save_state()
            handler.send_response(500)
            handler.end_headers()

    def response_item(self, _index, request):
        assert request["model"] == "mock-model", "Unexpected owned model"
        assert request["reasoning"]["effort"] == "medium", "Unexpected owned effort"
        root = any(part.get("text") == ROOT
                   for item in request.get("input", []) if item.get("role") == "user"
                   for part in item.get("content", []) if isinstance(part, dict))
        if not root:
            incoming = messages(request, "/root", CHILD_PATH)
            assert len(incoming) == 1, "Missing native child message"
            assert incoming[0]["content"] == [{"type": "input_text", "text": NEW_TASK}]
            assert outputs(request) == {}, "Child must not call a tool"
            with self.state_lock:
                self.state["child_requests"] += 1
                assert self.state["child_requests"] == 1, "Unexpected child continuation"
                self.save_state()
            assert self.release_child.wait(10), "Owned child-release deadline"
            assert not self.closing.is_set(), "Provider closed before child completion"
            return answer("owned-provenance-child-answer", CHILD_ANSWER)

        with self.state_lock:
            self.state["root_requests"] += 1
            step = self.state["root_requests"]
            self.save_state()
        values = outputs(request)
        if step == 1:
            assert values == {}, "Unexpected initial tool effects"
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "spawn_agent", "call_id": SPAWN,
                "encrypted_function_args": [],
                "arguments": json.dumps({
                    "task_name": "search_child", "message": CHILD,
                    "fork_turns": "none", "agent_type": "source_fixture",
                    "model": "mock-model", "reasoning_effort": "medium",
                }),
            }
        if step == 2:
            assert values == {SPAWN: {"task_name": CHILD_PATH}}, "Native spawn failed"
            self.release_child.set()
            return {
                "type": "function_call", "namespace": "collaboration",
                "name": "wait_agent", "call_id": WAIT,
                "arguments": json.dumps({"timeout_ms": 10000}),
            }
        assert step == 3, "Unexpected root continuation"
        assert values == {
            SPAWN: {"task_name": CHILD_PATH},
            WAIT: {"message": "Wait completed.", "timed_out": False},
        }, "Native wait did not observe child completion"
        incoming = messages(request, CHILD_PATH, "/root")
        assert len(incoming) == 1, "Missing native child result"
        assert incoming[0]["content"] == [{"type": "input_text", "text": FINAL_ANSWER}]
        return answer("owned-provenance-root-answer", ROOT_ANSWER)

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
    fixture = ProvenanceFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
