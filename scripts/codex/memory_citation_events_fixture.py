#!/usr/bin/env python3
"""Responses text only; stock Codex parses citations and emits native items.

Paths and non-UUID IDs are inert strings, never host-memory retrieval inputs.
The fixture emits no app-server frames and never edits native history.
"""
import model_fixture

_assistant_events = model_fixture.response_events


def response_events(index, completed_item):
    if index != 1:
        raise AssertionError("Unexpected additional citation-event inference")
    modern = (
        "Owned modern visible λ."
        "<oai-mem-citation>\n<citation_entries>\n"
        " synthetic/owned-memory.md:7-11|note=[ owned summary λ ]\n"
        "synthetic/owned-detail.md:20-23|note=[owned detail]\n"
        "</citation_entries>\n<rollout_ids>\n"
        "owned-rollout-alpha\nowned-rollout-beta\nowned-rollout-alpha\n"
        "</rollout_ids>\n<thread_ids>\nowned-ignored-legacy\n</thread_ids>\n"
        "</oai-mem-citation> Tail."
    )
    legacy = (
        "Owned legacy visible."
        "<oai-mem-citation>\n<citation_entries>\n"
        "synthetic/owned-legacy.md:2-4|note=[owned legacy note]\n"
        "</citation_entries>\n<thread_ids>\n"
        "owned-thread-first\nowned-thread-second\nowned-thread-first\n"
        "</thread_ids>\n</oai-mem-citation> Done."
    )
    items = [
        {"type": "message", "id": "owned-memory-modern", "role": "assistant",
         "status": "completed", "phase": "commentary",
         "content": [{"type": "output_text", "text": modern}]},
        {"type": "message", "id": "owned-memory-legacy", "role": "assistant",
         "status": "completed", "phase": "final_answer",
         "content": [{"type": "output_text", "text": legacy}]},
    ]
    assistant_events = _assistant_events(index, completed_item)
    events = assistant_events[:1]
    events.extend({"type": "response.output_item.done", "item": item} for item in items)
    return events + assistant_events[-1:]


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
