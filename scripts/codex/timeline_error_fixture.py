#!/usr/bin/env python3
"""Provider SSE only: native overload, then one explicit successful next turn.

The stock pinned app-server owns errors, persistence and timeline projections.
This process never emits app-server frames or modifies native history.
"""
import model_fixture

_completed_events = model_fixture.response_events


def response_events(index, completed_item):
    if index == 1:
        identity = "owned-timeline-overload-1"
        return [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.failed", "response": {
                "id": identity,
                "error": {
                    "code": "server_is_overloaded",
                    "message": "Provider text differs from the native overload display.",
                },
            }},
        ]
    if index == 2:
        return _completed_events(index, completed_item)
    raise AssertionError("Unexpected additional timeline inference")


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
