#!/usr/bin/env python3
"""Generic current Responses decode/history fixture for stock pinned Codex.

Only the first Responses stream supplies a context_compaction item with no ID
or passthrough metadata, followed by an ordinary assistant response. Native
Codex creates all raw app-server notifications, identities and durable history.
This is not evidence of a real provider's emission or remote-v2 installation.
"""
import json
from pathlib import Path

import model_fixture as model


MARKER = "Owned generic current context-compaction history 163 λ"
FOLLOWUP = "Owned continuation consumes current context-compaction history 163 λ"
SOURCE_ANSWER = "Owned source context-compaction evidence completed λ"
ANSWER = "Owned imported context-compaction evidence consumed λ"
_assistant_events = model.response_events


def response_events(index, completed_item):
    assistant = _assistant_events(index, completed_item)
    assert 1 <= index <= 2, "Unexpected extra context-compaction inference"
    if index == 1:
        # No app-server frames, native identities, turn metadata or history rows.
        return assistant[:1] + [{
            "type": "response.output_item.done",
            "item": {"type": "context_compaction"},
        }] + assistant[1:]
    return assistant


class SuppliedContextCompactionHistoryFixture(model.ModelFixture):
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
        assert 1 <= index <= 2, "Unexpected extra context-compaction inference"
        items = request["input"]
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": MARKER}
        ] for item in items) == 1
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
            "tool_search_call", "tool_search_output", "local_shell_call",
            "compaction_trigger", "compaction",
        } for item in items), "Unexpected work in current context-history-only profile"
        contexts = [item for item in items if item.get("type") == "context_compaction"]
        followups = sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUP}
        ] for item in items)
        if index == 1:
            assert contexts == []
            assert followups == 0
            identity, answer = "owned-context-history-source-answer", SOURCE_ANSWER
        else:
            assert len(contexts) == 1
            context = contexts[0]
            identity = context.get("id")
            assert isinstance(identity, str) and identity.startswith("cmp_") and len(identity) > 4
            assert context == {"type": "context_compaction", "id": identity}
            assert followups == 1
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            identity, answer = "owned-context-history-followup-answer", ANSWER
        return {
            "type": "message", "id": identity, "role": "assistant",
            "content": [{"type": "output_text", "text": answer}],
        }


if __name__ == "__main__":
    model.response_events = response_events
    model.ModelFixture = SuppliedContextCompactionHistoryFixture
    model.main()
