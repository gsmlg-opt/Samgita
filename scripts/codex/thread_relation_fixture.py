#!/usr/bin/env python3
"""Synthetic Responses only; real pinned Codex owns all spawn state and IDs."""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture


MARKERS = {
    "root": "OWNED_RELATION_ROOT",
    "a": "OWNED_RELATION_CHILD_A",
    "b": "OWNED_RELATION_CHILD_B",
    "g": "OWNED_RELATION_GRANDCHILD",
    "other": "OWNED_RELATION_UNRELATED",
}


def route(request):
    texts = [part.get("text") for item in request.get("input", [])
             if item.get("role") == "user"
             for part in item.get("content", []) if isinstance(part, dict)]
    matches = [key for key, marker in MARKERS.items() if marker in texts]
    assert len(matches) == 1, f"Unexpected synthetic user route: {matches}"
    return matches[0]


def outputs(request):
    return {item["call_id"]: json.loads(item["output"])
            for item in request.get("input", [])
            if item.get("type") == "function_call_output"}


def agent_id(values, call):
    value = values[call]
    assert isinstance(value.get("agent_id"), str), f"Native spawn failed: {value}"
    return value["agent_id"]


def assert_wait(values, call, target):
    value = values[call]
    assert value["timed_out"] is False, f"Native wait timed out: {value}"
    assert set(value["status"]) == {target}, value
    assert set(value["status"][target]) == {"completed"}, value


class ThreadRelationFixture(ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(config.read_text() + """
[agents]
enabled = true
max_depth = 3
max_concurrent_threads_per_session = 4
[features]
multi_agent = true
multi_agent_v2 = false
""")

    def response_item(self, index, request):
        owner = route(request)
        values = outputs(request)
        steps = {
            "root": [("relation-spawn-a", "spawn", "a"),
                     ("relation-wait-a", "wait", "relation-spawn-a"),
                     ("relation-spawn-b", "spawn", "b"),
                     ("relation-wait-b", "wait", "relation-spawn-b")],
            "a": [("relation-spawn-g", "spawn", "g"),
                  ("relation-wait-g", "wait", "relation-spawn-g")],
            "b": [], "g": [], "other": [],
        }[owner]
        for call, action, target in steps:
            if call in values:
                if action == "spawn":
                    agent_id(values, call)
                else:
                    assert_wait(values, call, agent_id(values, target))
                continue
            arguments = ({"message": MARKERS[target], "fork_context": False}
                         if action == "spawn" else
                         {"targets": [agent_id(values, target)]})
            return {"type": "function_call", "namespace": "multi_agent_v1",
                    "name": "spawn_agent" if action == "spawn" else "wait_agent",
                    "call_id": call, "arguments": json.dumps(arguments)}
        return {"type": "message", "role": "assistant", "id": f"relation-{index}",
                "content": [{"type": "output_text", "text": f"Owned relation {owner} done"}]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = ThreadRelationFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
