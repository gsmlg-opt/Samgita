#!/usr/bin/env python3
"""Owned loopback Responses SSE for native thread-event qualification.

Imports the existing model fixture unchanged. This emits provider SSE only;
the pinned Codex app-server must produce every asserted protocol notification.
"""
from copy import deepcopy
import model_fixture

_base_item = model_fixture.ModelFixture.item


def stream_parts(index):
    return ["Owned stream ", str(index), " é", "🙂", "\nDone."]


def item(self, index):
    result = _base_item(self, index)
    if result["type"] == "message":
        result = deepcopy(result)
        result["content"][0]["text"] = "".join(stream_parts(index))
    return result


def response_events(index, completed_item):
    identity = f"fixture-response-{index}"
    if completed_item["type"] != "message":
        raise ValueError("Thread-event fixture only supports assistant messages")
    # Pinned core/tests/common/responses.rs: ev_message_item_added and
    # ev_output_text_delta; content is completed only in output_item.done.
    started_item = deepcopy(completed_item)
    started_item["content"][0]["text"] = ""
    return [
        {"type": "response.created", "response": {"id": identity}},
        {"type": "response.output_item.added", "item": started_item},
        *({"type": "response.output_text.delta", "delta": part}
          for part in stream_parts(index)),
        {"type": "response.output_item.done", "item": completed_item},
        {"type": "response.completed", "response": {"id": identity, "usage": {
            "input_tokens": 7, "input_tokens_details": {"cached_tokens": 3},
            "output_tokens": 11, "output_tokens_details": {"reasoning_tokens": 2},
            "total_tokens": 18,
        }}},
    ]


model_fixture.ModelFixture.item = item
model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
