#!/usr/bin/env python3
"""Fixed model responses; stock Codex alone owns child lifecycles and IDs."""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture


ROOT_MARKERS = [f"OWNED_COLLAB_ROOT_{phase}" for phase in (1, 2, 3)]
FIRST = "OWNED_COLLAB_CHILD_FIRST"
FOLLOWUP = "OWNED_COLLAB_CHILD_FOLLOWUP"
FIRST_DONE = "Owned collaboration child first done"
FOLLOWUP_DONE = "Owned collaboration child followup done"


def user_texts(request):
    return [part.get("text") for item in request.get("input", [])
            if item.get("role") == "user"
            for part in item.get("content", []) if isinstance(part, dict)]


def tool_outputs(request):
    return {item["call_id"]: json.loads(item["output"])
            for item in request.get("input", [])
            if item.get("type") == "function_call_output"}


def child_id(values):
    value = values["owned-collab-spawn"]
    assert isinstance(value.get("agent_id"), str) and value["agent_id"], value
    return value["agent_id"]


def completed(message):
    return {"completed": message}


def validate(values, call, action, phase):
    result = values[call]
    if action == "spawn_agent":
        child_id(values)
    elif action == "wait_agent":
        status = ("not_found" if call == "owned-collab-wait-closed" else
                  completed(FIRST_DONE if phase == 1 else FOLLOWUP_DONE))
        assert result == {"status": {child_id(values): status}, "timed_out": False}, result
    elif action == "close_agent":
        message = FIRST_DONE if phase == 1 else FOLLOWUP_DONE
        assert result == {"previous_status": completed(message)}, result
    elif action == "resume_agent":
        # The public loaded-state query, between turns, is the resume oracle.
        # Do not pick PendingInit/Running by racing the native snapshot.
        assert set(result) == {"status"}, result
    elif action == "send_input":
        assert set(result) == {"submission_id"}, result
        assert isinstance(result["submission_id"], str) and result["submission_id"], result


class CollaborationLifecycleFixture(ModelFixture):
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

    def response_item(self, index, request):
        texts = user_texts(request)
        latest = next((text for text in reversed(texts)
                       if text in [*ROOT_MARKERS, FIRST, FOLLOWUP]), None)
        assert latest is not None, "Missing prescribed collaboration input"
        if latest in (FIRST, FOLLOWUP):
            text = FIRST_DONE if latest == FIRST else FOLLOWUP_DONE
            return self.message(index, text)

        phase = ROOT_MARKERS.index(latest) + 1
        values = tool_outputs(request)
        steps = {
            1: [("owned-collab-spawn", "spawn_agent"),
                ("owned-collab-wait-first", "wait_agent"),
                ("owned-collab-close-first", "close_agent"),
                ("owned-collab-wait-closed", "wait_agent")],
            2: [("owned-collab-resume", "resume_agent")],
            3: [("owned-collab-send", "send_input"),
                ("owned-collab-wait-followup", "wait_agent"),
                ("owned-collab-close-followup", "close_agent")],
        }[phase]

        for call, action in steps:
            if call in values:
                validate(values, call, action, phase)
                continue
            if action == "spawn_agent":
                arguments = {"message": FIRST, "fork_context": False,
                             "model": "mock-model", "reasoning_effort": "low"}
            elif action == "wait_agent":
                arguments = {"targets": [child_id(values)]}
            elif action == "resume_agent":
                arguments = {"id": child_id(values)}
            else:
                arguments = {"target": child_id(values)}
                if action == "send_input":
                    arguments.update(message=FOLLOWUP, interrupt=False)
            return {"type": "function_call", "namespace": "multi_agent_v1",
                    "name": action, "call_id": call, "arguments": json.dumps(arguments)}
        return self.message(index, f"Owned collaboration root {phase} done")

    @staticmethod
    def message(index, text):
        return {"type": "message", "role": "assistant", "id": f"owned-collab-{index}",
                "content": [{"type": "output_text", "text": text}]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = CollaborationLifecycleFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
