#!/usr/bin/env python3
"""Provider Responses SSE only; stock Codex owns streamed items and history.

The URLs are inert result data. This fixture performs no search or browsing,
and never emits app-server frames or writes native history.
"""
import argparse
import json
from pathlib import Path
import sys

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
        ("primary-queries-omitted", {"type": "search", "query": "Owned nullable primary λ"}),
        ("primary-queries-null", {"type": "search", "query": "Owned nullable primary λ",
                                  "queries": None}),
        ("search-fields-omitted", {"type": "search"}),
        ("search-fields-null", {"type": "search", "query": None, "queries": None}),
        ("open-url-omitted", {"type": "open_page"}),
        ("open-url-null", {"type": "open_page", "url": None}),
        ("find-url-omitted", {"type": "find_in_page", "pattern": "Owned lone pattern 🙂"}),
        ("find-url-null", {"type": "find_in_page", "url": None,
                           "pattern": "Owned lone pattern 🙂"}),
        ("find-pattern-omitted", {"type": "find_in_page", "url": PAGE}),
        ("find-pattern-null", {"type": "find_in_page", "url": PAGE, "pattern": None}),
        ("find-fields-omitted", {"type": "find_in_page"}),
        ("find-fields-null", {"type": "find_in_page", "url": None, "pattern": None}),
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

# This explicit extra scenario consumes genuine native supplied history. The
# existing sixteen-item streamed-web scenario above remains unchanged.
HISTORY_MARKER = "Owned genuine supplied-history web search 163"
HISTORY_FOLLOWUP = "Owned continuation consumes supplied web evidence 163"
HISTORY_ANSWER = "Owned source web evidence completed λ🙂"
HISTORY_FOLLOWUP_ANSWER = "Owned imported web evidence consumed λ🙂"


def supplied_history_events(index, completed_item):
    assistant = _assistant_events(index, completed_item)
    if index == 1:
        # Existing provider literals only; the native creates all history and
        # app-server items. Select just the actual primary added/done pair.
        primary = [event for event in response_events(index, completed_item)
                   if event.get("item", {}).get("id") == "owned-streamed-web-primary"]
        assert [event["type"] for event in primary] == [
            "response.output_item.added", "response.output_item.done"]
        return assistant[:1] + primary + assistant[1:]
    assert index == 2, "Unexpected additional supplied-web inference"
    return assistant


class SuppliedWebHistoryFixture(model_fixture.ModelFixture):
    def response_item(self, index, request):
        assert self.scenario == "web_search_history"
        assert request["model"] == "mock-model"
        assert 1 <= index <= 2, "Unexpected additional supplied-web inference"
        items = request["input"]
        self.assert_message(items, "user", HISTORY_MARKER)
        searches = [item for item in items if item.get("type") == "web_search_call"]
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call",
            "custom_tool_call_output", "tool_search_call", "tool_search_output",
        } for item in items)
        if index == 1:
            assert searches == []
            identity, text = "owned-web-history-source-answer", HISTORY_ANSWER
        else:
            # Provider copies lose metadata and the unprefixed provider ID;
            # complete independent literals assert actual evidence consumption.
            assert searches == [{
                "type": "web_search_call",
                "status": "completed",
                "action": {
                    "type": "search",
                    "query": "Owned primary λ",
                    "queries": ["Owned different first", "Owned different second"],
                },
            }]
            self.assert_message(items, "assistant", HISTORY_ANSWER)
            self.assert_message(items, "user", HISTORY_FOLLOWUP)
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            identity, text = "owned-web-history-followup-answer", HISTORY_FOLLOWUP_ANSWER
        return {"type": "message", "id": identity, "role": "assistant",
                "content": [{"type": "output_text", "text": text}]}

    @staticmethod
    def assert_message(items, role, text):
        content_type = "input_text" if role == "user" else "output_text"
        content = [{"type": content_type, "text": text}]
        selected = [item for item in items
                    if item.get("role") == role and item.get("content") == content]
        assert len(selected) == 1
        expected = {"type": "message", "role": role, "content": content}
        if role == "user":
            identity = selected[0].get("id")
            assert isinstance(identity, str) and identity.startswith("msg_")
            expected["id"] = identity
        assert selected[0] == expected


def supplied_history_main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, choices=["web_search_history"])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True, type=Path)
    args = parser.parse_args()
    model_fixture.response_events = supplied_history_events
    fixture = SuppliedWebHistoryFixture(
        args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    if ("--scenario" in sys.argv
            and sys.argv[sys.argv.index("--scenario") + 1] == "web_search_history"):
        supplied_history_main()
    else:
        model_fixture.main()
