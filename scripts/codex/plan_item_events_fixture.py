#!/usr/bin/env python3
"""Responses text only; stock Codex owns Plan items and native persistence.

No app-server frames, native history writes, tools or external services.
"""
import model_fixture

_assistant_events = model_fixture.response_events


def response_events(index, completed_item):
    if index != 1:
        raise AssertionError("Unexpected additional plan-item inference")
    text = "<proposed_plan>\n# Owned next plan λ🙂\n- first\n- second\n</proposed_plan>"
    item = {
        "type": "message", "id": "owned-proposed-plan-message", "role": "assistant",
        "status": "completed", "phase": "final_answer",
        "content": [{"type": "output_text", "text": text}],
    }
    assistant_events = _assistant_events(index, completed_item)
    return [assistant_events[0], {"type": "response.output_item.done", "item": item},
            assistant_events[-1]]


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
