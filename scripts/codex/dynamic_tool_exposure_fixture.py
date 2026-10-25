#!/usr/bin/env python3
"""Responses-only peer for real Codex canonical dynamic-tool exposure.

No app-server frames are generated here. Codex owns declaration conversion,
local BM25 discovery, client dispatch, response association, and persistence.
The top-level deferred declaration is rejected before any provider request.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class DynamicToolExposureFixture(ModelFixture):
    def response_item(self, index, request):
        if self.scenario == "top_deferred":
            raise AssertionError("Rejected top-level deferred declaration reached provider")
        deferred = self.scenario.endswith("deferred")
        if deferred and index == 1:
            return {
                "type": "tool_search_call", "call_id": "owned-exposure-search",
                "execution": "client",
                "arguments": {"query": "quasar_lookup_824", "limit": 1},
            }
        if index == (2 if deferred else 1):
            item = {
                "type": "function_call", "call_id": "owned-exposure-call",
                "name": "quasar_lookup_824",
                "arguments": json.dumps({
                    "key": "owned exposure λ", "count": 7,
                    "nested": {"enabled": True, "labels": ["α", "β"]},
                }, ensure_ascii=False),
            }
            if self.scenario.startswith("namespace"):
                item["namespace"] = "owned_catalog"
            return item
        if index == (3 if deferred else 2):
            return {
                "type": "message", "id": "owned-exposure-answer", "role": "assistant",
                "content": [{"type": "output_text", "text": "Owned exposure completed λ"}],
            }
        raise AssertionError("Unexpected extra model request")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, choices=[
        "top_direct", "top_deferred", "namespace_direct", "namespace_deferred",
    ])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = DynamicToolExposureFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
