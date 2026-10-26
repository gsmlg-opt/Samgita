#!/usr/bin/env python3
"""Genuine native image producers followed by one explicit history continuation.

Source replies use the existing provider unchanged. Native Codex creates every
history record; this provider never supplies app-server responses or rollouts.
"""
import json
from pathlib import Path

import model_fixture as model


MARKERS = {
    "assistant": "Owned source user image detail null 163",
    "dynamic_tool": "Owned source dynamic image detail null 163",
}
FOLLOWUPS = {
    "assistant": "Owned continuation consumes user image null detail 163",
    "dynamic_tool": "Owned continuation consumes dynamic image null detail 163",
}
ANSWER = "Owned imported null image detail consumed 163"
RESULT = "Owned genuine dynamic image output 163"
FILE_ID = "file-owned-null-image-detail-163"


def text_marker_count(items, marker):
    return sum(item.get("role") == "user" and item.get("content") == [
        {"type": "input_text", "text": marker}
    ] for item in items)


class SuppliedNullImageDetailHistoryFixture(model.ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        text = config.read_text().replace('approval_policy = "on-request"',
                                          'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"',
                            'sandbox_mode = "danger-full-access"')
        config.write_text(
            'check_for_update_on_startup = false\nallow_login_shell = false\n' + text +
            '\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n'
            'shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n'
            'unified_image_budget = false\n'
        )

    def response_item(self, index, request):
        assert self.scenario in MARKERS
        source_budget = 1 if self.scenario == "assistant" else 2
        assert 1 <= index <= source_budget + 1, "Unexpected extra null-detail inference"
        assert request["model"] == "mock-model"
        items = request["input"]
        followups = text_marker_count(items, FOLLOWUPS[self.scenario])
        if followups:
            assert index == source_budget + 1 and followups == 1
            self.assert_imported_history(items)
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            return {
                "type": "message", "role": "assistant", "id": "owned-null-image-detail-answer",
                "content": [{"type": "output_text", "text": ANSWER}],
            }
        assert index <= source_budget, "Only explicit continuation may consume final request"
        return super().response_item(index, request)

    def assert_imported_history(self, items):
        if self.scenario == "assistant":
            users = [item for item in items if item.get("role") == "user" and
                     item.get("content", [{}])[0].get("text") == MARKERS[self.scenario]]
            assert len(users) == 1
            assert users[0]["content"] == [
                {"type": "input_text", "text": MARKERS[self.scenario]},
                {"type": "input_image", "file_id": FILE_ID},
            ]
            assert not any(item.get("type") in {"function_call", "function_call_output"}
                           for item in items)
        else:
            assert text_marker_count(items, MARKERS[self.scenario]) == 1
            calls = [item for item in items if item.get("type") == "function_call"]
            outputs = [item for item in items if item.get("type") == "function_call_output"]
            assert len(calls) == len(outputs) == 1
            assert calls[0]["call_id"] == outputs[0]["call_id"] == "fixture-call-1"
            assert calls[0]["name"] == "fixture_lookup"
            assert json.loads(calls[0]["arguments"]) == {"key": "synthetic"}
            assert outputs[0]["output"][0] == {"type": "input_text", "text": RESULT}
            assert len(outputs[0]["output"]) == 2
            image = outputs[0]["output"][1]
            assert set(image) == {"type", "image_url"}
            assert image["type"] == "input_image"
            assert image["image_url"].startswith("data:image/png;base64,")
        assistants = [item for item in items if item.get("role") == "assistant"]
        assert assistants == [{
            "type": "message", "role": "assistant", "content": [
                {"type": "output_text", "text": "Deterministic local fixture answer"}
            ],
        }], "Unprefixed fixture assistant ID must be absent only in provider copy"


if __name__ == "__main__":
    model.ModelFixture = SuppliedNullImageDetailHistoryFixture
    model.main()
