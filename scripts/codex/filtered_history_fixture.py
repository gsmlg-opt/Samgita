#!/usr/bin/env python3
"""Ordinary Responses data for current filtered raw-history input journeys.

Stock Codex creates the manual backend compaction_trigger. For the Other profile
this peer supplies only the declared current Other literal to the generic native
Responses decoder. It never emits app-server notifications or writes rollouts,
history envelopes, legacy records or sidecars. Neither case claims legacy output.
"""
import json
from pathlib import Path

import model_fixture as model


MARKERS = {
    "compaction": "Owned current filtered trigger source 163 λ",
    "assistant": "Owned current filtered Other source 163 λ",
}
FOLLOWUPS = {
    "compaction": "Owned current filtered trigger continuation 163 λ",
    "assistant": "Owned current filtered Other continuation 163 λ",
}
SOURCE_ANSWERS = {
    "compaction": "Owned trigger source ordinary answer 163 λ",
    "assistant": "Owned Other source ordinary answer 163 λ",
}
FOLLOWUP_ANSWERS = {
    "compaction": "Owned trigger filtered continuation answer 163 λ",
    "assistant": "Owned Other filtered continuation answer 163 λ",
}
TOOL_TYPES = {
    "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
    "tool_search_call", "tool_search_output", "local_shell_call",
}
BASE_RESPONSE_EVENTS = model.response_events


def filtered_response_events(index, item):
    events = BASE_RESPONSE_EVENTS(index, item)
    if item.get("id") == "owned-filtered-assistant-source":
        # Ordinary declared provider data. Only stock native can generate the
        # subsequently observed rawResponseItem/completed notification.
        events.insert(1, {"type": "response.output_item.done", "item": {"type": "other"}})
    return events


class FilteredHistoryFixture(model.ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        text = path.read_text().replace('approval_policy = "on-request"',
                                        'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"',
                            'sandbox_mode = "danger-full-access"')
        capabilities = ('\n[model_providers.fixture.capabilities]\nremote_compaction = "v2"\n'
                        if self.scenario == "compaction" else "")
        path.write_text('check_for_update_on_startup = false\nallow_login_shell = false\n' +
                        text + capabilities +
                        '\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n' +
                        'shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n')

    def response_item(self, index, request):
        assert self.scenario in MARKERS
        assert request["model"] == "mock-model"
        budget = 3 if self.scenario == "compaction" else 2
        assert 1 <= index <= budget, "Unexpected extra filtered-history inference"
        items = request["input"]
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": MARKERS[self.scenario]}
        ] for item in items) == 1
        assert not any(item.get("type") in TOOL_TYPES for item in items)
        assert not any(item.get("type") in {"other", "compaction"} for item in items)
        triggers = [item for item in items if item.get("type") == "compaction_trigger"]
        is_compact = self.scenario == "compaction" and index == 2
        assert triggers == ([{"type": "compaction_trigger"}] if is_compact else [])
        if is_compact:
            # Reuse the ordinary backend response to a genuinely native trigger.
            return super().response_item(index, request)
        is_followup = index == budget
        expected_followups = 1 if is_followup else 0
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUPS[self.scenario]}
        ] for item in items) == expected_followups
        if is_followup:
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
        return {
            "type": "message", "id": f"owned-filtered-{self.scenario}-" +
            ("followup" if is_followup else "source"), "role": "assistant",
            "content": [{"type": "output_text", "text":
                         (FOLLOWUP_ANSWERS if is_followup else SOURCE_ANSWERS)[self.scenario]}],
        }


if __name__ == "__main__":
    model.response_events = filtered_response_events
    model.ModelFixture = FilteredHistoryFixture
    model.main()
