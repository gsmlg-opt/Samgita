#!/usr/bin/env python3
"""Provider-only continuation of genuine native client tool-search history.

The reviewed namespace_deferred producer owns replies 1-3 unchanged. Reply 4
consumes only completed imported evidence; it never asks to call a restored tool.
This fixture emits Responses items, never app-server or native rollout records.
"""
import json

import dynamic_tool_exposure_fixture as exposure


FOLLOWUP = "Owned continuation consumes completed tool-search evidence 163"
ANSWER = "Owned imported tool-search evidence consumed λ"
ARGUMENTS = '{"key": "owned exposure λ", "count": 7, "nested": {"enabled": true, "labels": ["α", "β"]}}'
SCHEMA = {
    "type": "object",
    "properties": {
        "key": {"type": "string"},
        "count": {"type": "integer"},
        "nested": {
            "type": "object",
            "properties": {
                "enabled": {"type": "boolean"},
                "labels": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["enabled", "labels"],
            "additionalProperties": False,
        },
    },
    "required": ["key", "count", "nested"],
    "additionalProperties": False,
}
NAMESPACE = {
    "type": "namespace",
    "name": "owned_catalog",
    "description": "Owned canonical catalog description β",
    "tools": [{
        "type": "function",
        "name": "quasar_lookup_824",
        "description": "quasar_lookup_824 retrieves the owned synthetic record λ",
        "strict": False,
        "parameters": SCHEMA,
        "defer_loading": True,
    }],
}


class SuppliedToolSearchHistoryFixture(exposure.DynamicToolExposureFixture):
    def response_item(self, index, request):
        assert self.scenario == "namespace_deferred", "Only the reviewed search producer is allowed"
        if 1 <= index <= 3:
            return super().response_item(index, request)
        assert index == 4, "Unexpected extra supplied-search model request"
        assert request["model"] == "mock-model"
        items = request["input"]
        expected = {
            "tool_search_call": {
                "type": "tool_search_call", "call_id": "owned-exposure-search",
                "execution": "client", "arguments": {"query": "quasar_lookup_824", "limit": 1},
            },
            "tool_search_output": {
                "type": "tool_search_output", "call_id": "owned-exposure-search",
                "status": "completed", "execution": "client", "tools": [NAMESPACE],
            },
            "function_call": {
                "type": "function_call", "call_id": "owned-exposure-call",
                "namespace": "owned_catalog", "name": "quasar_lookup_824", "arguments": ARGUMENTS,
            },
            "function_call_output": {
                "type": "function_call_output", "call_id": "owned-exposure-call",
                "output": "Owned synthetic record result λ",
            },
        }
        for kind, value in expected.items():
            matching = [item for item in items if item.get("type") == kind]
            assert len(matching) == 1, f"Expected exactly one {kind} evidence item"
            assert isinstance(matching[0].get("id"), str) and matching[0]["id"]
            assert {key: item for key, item in matching[0].items() if key != "id"} == value
        assert sum(item.get("role") == "assistant" and item.get("content") == [
            {"type": "output_text", "text": "Owned exposure completed λ"}
        ] for item in items) == 1
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": FOLLOWUP}
        ] for item in items) == 1
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert metadata["history_initialization"] == "supplied_history"
        # ResponseItem history has no SessionMeta dynamic declarations. This
        # continuation intentionally consumes completed evidence, not execution.
        for tool in request["tools"]:
            assert tool.get("name") not in {"owned_catalog", "quasar_lookup_824"}
            assert all(child.get("name") != "quasar_lookup_824" for child in tool.get("tools", []))
        return {
            "type": "message", "id": "owned-supplied-search-followup-answer", "role": "assistant",
            "content": [{"type": "output_text", "text": ANSWER}],
        }


if __name__ == "__main__":
    exposure.DynamicToolExposureFixture = SuppliedToolSearchHistoryFixture
    exposure.main()
