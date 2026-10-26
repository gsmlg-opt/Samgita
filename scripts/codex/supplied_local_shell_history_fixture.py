#!/usr/bin/env python3
"""Generic current Responses decode/history fixture for stock pinned Codex.

The first stream supplies incomplete local_shell_call data with no item ID,
call ID or passthrough metadata, followed by an ordinary assistant response.
The command is inert history data, never executed by this Responses peer.
Native Codex creates all raw notifications, identities and durable history.
This is not legacy emission, shell execution or call/output pairing evidence.
"""
import json
from pathlib import Path

import model_fixture as model


MARKER = "Owned generic current local-shell history 163 λ"
FOLLOWUP = "Owned continuation consumes current local-shell history 163 λ"
COMMAND = ["owned-inert-current-history-data-163"]
SOURCE_ANSWER = "Owned source local-shell evidence completed λ"
ANSWER = "Owned imported local-shell evidence consumed λ"
_assistant_events = model.response_events


def local_shell_item():
    return {"type": "local_shell_call", "status": "incomplete",
            "action": {"type": "exec", "command": COMMAND}}


def response_events(index, completed_item):
    assistant = _assistant_events(index, completed_item)
    assert 1 <= index <= 2, "Unexpected extra local-shell-history inference"
    if index == 1:
        # No app-server frames, native identities, turn metadata or history rows.
        return assistant[:1] + [{
            "type": "response.output_item.done", "item": local_shell_item(),
        }] + assistant[1:]
    return assistant


class SuppliedLocalShellHistoryFixture(model.ModelFixture):
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
        assert 1 <= index <= 2, "Unexpected extra local-shell-history inference"
        items = request["input"]
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": MARKER}
        ] for item in items) == 1
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
            "tool_search_call", "tool_search_output", "compaction_trigger", "compaction",
        } for item in items), "Unexpected work or synthesized output in current local history"
        shells = [item for item in items if item.get("type") == "local_shell_call"]
        followups = sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUP}
        ] for item in items)
        if index == 1:
            assert shells == []
            assert followups == 0
            identity, answer = "owned-local-history-source-answer", SOURCE_ANSWER
        else:
            assert len(shells) == 1
            shell = shells[0]
            identity = shell.get("id")
            assert isinstance(identity, str) and identity.startswith("lsh_") and len(identity) > 4
            assert shell == {
                "type": "local_shell_call", "id": identity, "call_id": None,
                "status": "incomplete", "action": {
                    "type": "exec", "command": COMMAND, "timeout_ms": None,
                    "working_directory": None, "env": None, "user": None,
                },
            }
            assert followups == 1
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            identity, answer = "owned-local-history-followup-answer", ANSWER
        return {
            "type": "message", "id": identity, "role": "assistant",
            "content": [{"type": "output_text", "text": answer}],
        }


if __name__ == "__main__":
    model.response_events = response_events
    model.ModelFixture = SuppliedLocalShellHistoryFixture
    model.main()
