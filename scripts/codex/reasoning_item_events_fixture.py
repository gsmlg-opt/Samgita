#!/usr/bin/env python3
"""Responses reasoning data only; stock Codex owns native lifecycle and history.

These literal arrays are provider inputs. No app-server frames are emitted and
no native history is written by this fixture.
"""
import argparse
import json
from pathlib import Path
import sys

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

# This extra scenario consumes genuine native supplied history. The default
# reasoning-item event scenario above remains unchanged.
HISTORY_MARKER = "Owned genuine supplied-history reasoning 163"
HISTORY_FOLLOWUP = "Owned continuation consumes supplied reasoning evidence 163"
HISTORY_ANSWER = "Owned source reasoning completed λ🙂"
HISTORY_FOLLOWUP_ANSWER = "Owned imported reasoning evidence consumed λ🙂"


def supplied_history_events(index, completed_item):
    assistant = _assistant_events(index, completed_item)
    if index == 1:
        # Reuse the existing provider input; emit only its populated item.
        populated = [event for event in response_events(index, completed_item)
                     if event.get("type") == "response.output_item.done"
                     and event.get("item", {}).get("id") == "owned-reasoning-populated"]
        assert len(populated) == 1
        return assistant[:1] + populated + assistant[1:]
    assert index == 2, "Unexpected additional supplied-reasoning inference"
    return assistant


class SuppliedReasoningHistoryFixture(model_fixture.ModelFixture):
    def response_item(self, index, request):
        assert self.scenario == "reasoning_history"
        assert request["model"] == "mock-model"
        assert 1 <= index <= 2, "Unexpected additional supplied-reasoning inference"
        items = request["input"]
        self.assert_message(items, "user", HISTORY_MARKER)
        reasonings = [item for item in items if item.get("type") == "reasoning"]
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call",
            "custom_tool_call_output", "tool_search_call", "tool_search_output",
        } for item in items)
        if index == 1:
            assert reasonings == []
            identity, text = "owned-reasoning-source-answer", HISTORY_ANSWER
        else:
            # client.rs removes passthrough metadata and non-prefixed IDs from
            # provider copies. Exact independent literals verify consumption.
            assert reasonings == [{
                "type": "reasoning",
                "summary": [
                    {"type": "summary_text", "text": "Owned summary λ🙂"},
                    {"type": "summary_text", "text": "Owned second summary"},
                ],
                "content": [
                    {"type": "reasoning_text", "text": "Owned raw α🙂"},
                    {"type": "text", "text": ""},
                    {"type": "text", "text": "Owned text alternative"},
                ],
                "encrypted_content": None,
            }]
            self.assert_message(items, "assistant", HISTORY_ANSWER)
            self.assert_message(items, "user", HISTORY_FOLLOWUP)
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            identity, text = "owned-reasoning-followup-answer", HISTORY_FOLLOWUP_ANSWER
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
    parser.add_argument("--scenario", required=True, choices=["reasoning_history"])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True, type=Path)
    args = parser.parse_args()
    model_fixture.response_events = supplied_history_events
    fixture = SuppliedReasoningHistoryFixture(
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
            and sys.argv[sys.argv.index("--scenario") + 1] == "reasoning_history"):
        supplied_history_main()
    else:
        model_fixture.main()
