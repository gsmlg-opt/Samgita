#!/usr/bin/env python3
"""Ordinary configuration-update producer/input fixture for stock pinned Codex.

This peer emits assistant messages only. Native Codex creates every configuration
control, raw notification and persisted envelope. The fifth request is a cold
continuation of actual captured raw payloads, never a supplied native sidecar.
"""
from pathlib import Path

import model_fixture as model


MARKERS = [f"Owned configuration turn {index} 163 λ" for index in range(1, 5)]
FOLLOWUP = "Owned raw configuration history continuation 163 λ"
ANSWERS = [f"Owned ordinary configuration answer {index} 163 λ" for index in range(1, 6)]
def control(effort):
    return {"type": "configuration_update", "reasoning": {"effort": effort}}


def timeline(items):
    selected = []
    for item in items:
        if item.get("type") == "configuration_update":
            effort = item["reasoning"]["effort"]
            assert item == control(effort), "Incomplete native control map"
            selected.append(["control", effort])
        elif item.get("role") == "user" and item.get("content") in [
                [{"type": "input_text", "text": marker}] for marker in MARKERS + [FOLLOWUP]]:
            selected.append(["user", item["content"][0]["text"]])
    return selected


class ConfigurationUpdateFixture(model.ModelFixture):
    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        text = path.read_text()
        assert text.count('name = "Local deterministic fixture"') == 1
        text = text.replace('name = "Local deterministic fixture"', 'name = "OpenAI"')
        text = text.replace('approval_policy = "on-request"', 'approval_policy = "never"')
        text = text.replace('sandbox_mode = "read-only"', 'sandbox_mode = "danger-full-access"')
        path.write_text(
            'model_reasoning_effort = "medium"\ncheck_for_update_on_startup = false\n'
            'allow_login_shell = false\n' + text +
            '\n[features]\nreasoning_effort_override = true\napps = false\nplugins = false\n'
            'recommended_plugins = false\nshell_snapshot = false\nbrowser_use = false\n'
            'computer_use = false\n')

    def response_item(self, index, request):
        assert self.scenario == "assistant"
        assert 1 <= index <= 5, "Unexpected extra configuration inference"
        assert request["model"] == "mock-model"
        assert request["reasoning"]["effort"] == "medium"
        items = request["input"]
        assert not any(item.get("type") in {
            "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
            "local_shell_call", "tool_search_call", "tool_search_output", "compaction_trigger",
            "compaction", "reasoning",
        } for item in items), "Unexpected work or synthetic reasoning in ordinary config input"
        source = [
            [["user", MARKERS[0]], ["control", "medium"]],
            [["user", MARKERS[0]], ["control", "medium"],
             ["user", MARKERS[1]], ["control", "high"]],
            [["user", MARKERS[0]], ["control", "medium"],
             ["user", MARKERS[1]], ["control", "high"], ["user", MARKERS[2]]],
            [["user", MARKERS[0]], ["control", "medium"],
             ["user", MARKERS[1]], ["control", "high"], ["user", MARKERS[2]],
             ["user", MARKERS[3]], ["control", "low"]],
        ]
        expected = source[index - 1] if index <= 4 else (
            [["user", marker] for marker in MARKERS + [FOLLOWUP]] + [["control", "medium"]])
        assert timeline(items) == expected, "Native control order or duplication differs"
        for marker in MARKERS + [FOLLOWUP]:
            expected_count = int(marker in (MARKERS[:index] if index <= 4 else MARKERS + [FOLLOWUP]))
            assert sum(item.get("role") == "user" and item.get("content") == [
                {"type": "input_text", "text": marker}
            ] for item in items) == expected_count
        assistants = [item for item in items if item.get("role") == "assistant"]
        assert [item["content"] for item in assistants] == [
            [{"type": "output_text", "text": answer}] for answer in ANSWERS[:index - 1]
        ]
        if index == 5:
            # Imported raw controls remain distinct from the new cold control.
            assert [item for item in items if item.get("type") == "configuration_update"] == [
                control("medium")]
        return {
            "type": "message", "id": f"owned-config-answer-{index}", "role": "assistant",
            "content": [{"type": "output_text", "text": ANSWERS[index - 1]}],
        }


if __name__ == "__main__":
    model.ModelFixture = ConfigurationUpdateFixture
    model.main()
