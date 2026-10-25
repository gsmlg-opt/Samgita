#!/usr/bin/env python3
"""Provider Responses SSE only; stock Codex owns streamed items and history.

The URLs are inert result data. This fixture performs no search or browsing,
and never emits app-server frames or writes native history.
"""
import model_fixture

_assistant_events = model_fixture.response_events
PAGE = "https://streamed-web.synthetic.invalid/owned-page"


def response_events(index, completed_item):
    if index != 1:
        raise AssertionError("Unexpected additional streamed-web inference")
    actions = [
        ("primary", {"type": "search", "query": "Owned primary λ",
                     "queries": ["Owned different first", "Owned different second"]}),
        ("fallback", {"type": "search",
                      "queries": ["Owned fallback first", "Owned fallback second"]}),
        ("open", {"type": "open_page", "url": PAGE}),
        ("find", {"type": "find_in_page", "url": PAGE, "pattern": "Owned needle 🙂"}),
    ]
    assistant_events = _assistant_events(index, completed_item)
    events = assistant_events[:1]
    for name, action in actions:
        item = {"type": "web_search_call", "id": "owned-streamed-web-" + name,
                "status": "in_progress"}
        events.append({"type": "response.output_item.added", "item": item})
        events.append({"type": "response.output_item.done",
                       "item": {**item, "status": "completed", "action": action}})
    return events + assistant_events[1:]


model_fixture.response_events = response_events

if __name__ == "__main__":
    model_fixture.main()
