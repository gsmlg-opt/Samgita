#!/usr/bin/env python3
"""Responses draft text and distinct final text; stock Codex emits Plan events.

No app-server frames, native history writes, tools or external services.
"""
import model_fixture

_assistant_events = model_fixture.response_events


def response_events(index, completed_item):
    if index != 1:
        raise AssertionError("Unexpected additional streamed-plan inference")
    identity = "owned-stream-plan-message"
    added = {
        "type": "message", "id": identity, "role": "assistant",
        "status": "in_progress", "phase": "final_answer",
        "content": [{"type": "output_text", "text": ""}],
    }
    final = {
        "type": "message", "id": identity, "role": "assistant",
        "status": "completed", "phase": "final_answer",
        "content": [{"type": "output_text", "text":
                     "<proposed_plan>\n# Owned final λ🙂\n- accepted source\n</proposed_plan>"}],
    }
    parts = ["<proposed_", "plan>\n# Draft λ🙂\n",
             "- streamed\n</proposed_", "plan>"]
    assistant_events = _assistant_events(index, completed_item)
    return [assistant_events[0], {"type": "response.output_item.added", "item": added},
            *({"type": "response.output_text.delta", "delta": part} for part in parts),
            {"type": "response.output_item.done", "item": final}, assistant_events[-1]]


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
