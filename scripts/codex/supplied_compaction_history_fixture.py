#!/usr/bin/env python3
"""Responses-only producer/consumer of genuine native compaction history.

Replies 1-2 use the existing compaction producer unchanged. Codex installs and
persists the actual checkpoint; this peer never creates app-server/history rows.
The opaque marker is functional data, not a cryptography or provider-quality test.
"""
import json
from pathlib import Path

import model_fixture as model


MARKER = "Owned genuine supplied-history compaction 163 λ"
FOLLOWUP = "Owned continuation consumes installed compaction history 163 λ"
CHECKPOINT = "SYNTHETIC_COMPACTION_CHECKPOINT"
ANSWER = "Owned imported compaction evidence consumed λ"


class SuppliedCompactionHistoryFixture(model.ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        text = path.read_text().replace('approval_policy = "on-request"',
                                        'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"',
                            'sandbox_mode = "danger-full-access"')
        path.write_text('check_for_update_on_startup = false\nallow_login_shell = false\n' + text +
                        '\n[model_providers.fixture.capabilities]\nremote_compaction = "v2"\n' +
                        '\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n' +
                        'shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n')

    def response_item(self, index, request):
        assert self.scenario == "compaction"
        assert request["model"] == "mock-model"
        assert 1 <= index <= 3, "Unexpected extra supplied-compaction inference"
        items = request["input"]
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": MARKER}
        ] for item in items) == 1
        triggers = [item for item in items if item.get("type") == "compaction_trigger"]
        checkpoints = [item for item in items if item.get("type") == "compaction"]
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
            "tool_search_call", "tool_search_output", "local_shell_call",
        } for item in items), "Unexpected work in compaction-only profile"
        if index <= 2:
            assert checkpoints == []
            assert len(triggers) == (1 if index == 2 else 0)
            return super().response_item(index, request)
        assert triggers == [], "Imported history triggered another compaction"
        assert len(checkpoints) == 1
        checkpoint = checkpoints[0]
        assert {key: value for key, value in checkpoint.items() if key != "id"} == {
            "type": "compaction", "encrypted_content": CHECKPOINT,
        }
        assert isinstance(checkpoint["id"], str) and checkpoint["id"].startswith("cmp_")
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUP}
        ] for item in items) == 1
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert metadata["history_initialization"] == "supplied_history"
        return {
            "type": "message", "id": "owned-supplied-compaction-answer", "role": "assistant",
            "content": [{"type": "output_text", "text": ANSWER}],
        }


if __name__ == "__main__":
    model.ModelFixture = SuppliedCompactionHistoryFixture
    model.main()
