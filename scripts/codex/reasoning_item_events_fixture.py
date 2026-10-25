#!/usr/bin/env python3
"""Responses reasoning data only; stock Codex owns native lifecycle and history.

These literal arrays are provider inputs. No app-server frames are emitted and
no native history is written by this fixture.
"""
import model_fixture

_assistant_events = model_fixture.response_events


def response_events(index, completed_item):
    if index != 1:
        raise AssertionError("Unexpected additional reasoning-item inference")
    items = [
        {"type": "reasoning", "id": "owned-reasoning-populated",
         "summary": [{"type": "summary_text", "text": "Owned summary λ🙂"},
                     {"type": "summary_text", "text": "Owned second summary"}],
         "content": [{"type": "reasoning_text", "text": "Owned raw α🙂"},
                     {"type": "text", "text": ""},
                     {"type": "text", "text": "Owned text alternative"}]},
        {"type": "reasoning", "id": "owned-reasoning-empty", "summary": [], "content": []},
        {"type": "reasoning", "id": "owned-reasoning-omitted",
         "summary": [{"type": "summary_text", "text": "Owned summary with omitted content"}]},
        {"type": "reasoning", "id": "owned-reasoning-null", "summary": [], "content": None},
    ]
    assistant_events = _assistant_events(index, completed_item)
    events = assistant_events[:1]
    events.extend({"type": "response.output_item.done", "item": item} for item in items)
    return events + assistant_events[1:]


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
