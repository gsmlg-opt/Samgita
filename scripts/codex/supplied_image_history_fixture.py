#!/usr/bin/env python3
"""Responses-only producer/consumer for genuine native image-result history.

The first item follows the pinned current ev_image_generation_call helper and
model-switching replay test. Native Codex owns persistence, IDs, turn metadata
and supplied-history import. This peer never manufactures app-server/history
rows. The fixed tiny PNG is data, not actual generation or image-quality proof.
"""
import json
from pathlib import Path

import model_fixture as model


MARKER = "Owned genuine supplied-history image 163 λ"
FOLLOWUP = "Owned continuation consumes supplied image history 163 λ"
IMAGE_ID = "ig_fixture_supplied_history_163"
PROMPT = "A tiny synthetic image fixture λ"
RESULT = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
          "AAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
ANSWER = "Owned imported image evidence consumed λ"


def image_item():
    return {
        "type": "image_generation_call",
        "id": IMAGE_ID,
        "status": "completed",
        "revised_prompt": PROMPT,
        "result": RESULT,
    }


class SuppliedImageHistoryFixture(model.ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        text = path.read_text().replace('approval_policy = "on-request"',
                                        'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"',
                            'sandbox_mode = "danger-full-access"')
        path.write_text('check_for_update_on_startup = false\nallow_login_shell = false\n' + text +
                        '\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n' +
                        'shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n')

    def response_item(self, index, request):
        assert self.scenario == "assistant"
        assert request["model"] == "mock-model"
        assert 1 <= index <= 2, "Unexpected extra supplied-image inference"
        items = request["input"]
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": MARKER}
        ] for item in items) == 1
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
            "tool_search_call", "tool_search_output", "local_shell_call", "compaction_trigger",
        } for item in items), "Unexpected work in image-history-only profile"
        images = [item for item in items if item.get("type") == "image_generation_call"]
        followups = sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUP}
        ] for item in items)
        if index == 1:
            assert images == []
            assert followups == 0
            return image_item()
        assert images == [image_item()]
        assert followups == 1
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert metadata["history_initialization"] == "supplied_history"
        return {
            "type": "message", "id": "owned-supplied-image-answer", "role": "assistant",
            "content": [{"type": "output_text", "text": ANSWER}],
        }


if __name__ == "__main__":
    model.ModelFixture = SuppliedImageHistoryFixture
    model.main()
