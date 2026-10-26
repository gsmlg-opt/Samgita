#!/usr/bin/env python3
"""Current native MAv2 delivery, then one supplied-history continuation.

Source replies delegate unchanged to the existing functional activity producer.
Native Codex creates the child, delivers its literal result, and persists the
actual AgentMessage. This peer never creates app-server/history records.
"""
import importlib.util
import json
from pathlib import Path

import model_fixture as model


SOURCE = (Path(__file__).resolve().parents[2] / "apps" / "samgita_codex_driver" /
          "test" / "support" / "native_subagent_activity_fixture.py")
SPEC = importlib.util.spec_from_file_location("owned_agent_message_source", SOURCE)
source = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(source)

FOLLOWUP = "Owned continuation consumes supplied AgentMessage history 163 λ"
ANSWER = "Owned imported AgentMessage evidence consumed λ"


def user_marker_count(items, marker):
    return sum(item.get("role") == "user" and item.get("content") == [
        {"type": "input_text", "text": marker}
    ] for item in items)


class SuppliedAgentMessageHistoryFixture(source.SubagentActivityFixture):
    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        text = config.read_text().replace('approval_policy = "on-request"',
                                          'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"',
                            'sandbox_mode = "danger-full-access"')
        config.write_text(text)

    def response_item(self, index, request):
        assert self.scenario == "assistant"
        assert 1 <= index <= 5, "Unexpected extra supplied-AgentMessage inference"
        items = request["input"]
        followups = user_marker_count(items, FOLLOWUP)
        if followups:
            assert index == 5 and followups == 1
            assert request["model"] == "mock-model"
            assert request["reasoning"]["effort"] == "medium"
            assert user_marker_count(items, source.ROOT) == 1
            assert not any(item.get("type") in {
                "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
                "tool_search_call", "tool_search_output", "local_shell_call", "compaction_trigger",
            } for item in items), "Imported history must not execute collaboration or tools"
            messages = [item for item in items if item.get("type") == "agent_message"]
            assert len(messages) == 1
            message = messages[0]
            assert isinstance(message["id"], str) and message["id"].startswith("amsg_")
            assert {key: value for key, value in message.items() if key != "id"} == {
                "type": "agent_message", "author": source.CHILD_PATH, "recipient": "/root",
                "content": [{"type": "input_text", "text": source.FINAL_ANSWER}],
            }
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            self.record_response("import_followup")
            return source.final_message("owned-supplied-agent-message-answer", ANSWER)
        assert index <= 4, "Only an explicit import followup may consume request five"
        return super().response_item(index, request)


if __name__ == "__main__":
    model.ModelFixture = SuppliedAgentMessageHistoryFixture
    model.main()
