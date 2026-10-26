#!/usr/bin/env python3
"""Responses-only producer/consumer of genuine native custom-tool history.

Codex applies the patch and owns all app-server frames and rollout records. The
fixture reads the owned file only; imports and followup never request more work.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from model_fixture import ModelFixture


MARKER = "Owned genuine supplied-history custom patch 163"
FOLLOWUP = "Owned continuation consumes completed custom patch evidence 163"
ANSWER = "Owned custom patch completed λ🙂"
FOLLOWUP_ANSWER = "Owned imported custom patch evidence consumed λ🙂"
BEFORE = "owned before\n"
AFTER = "owned after λ🙂\n"
PATCH = "*** Begin Patch\n*** Update File: owned-notice.txt\n@@\n-owned before\n+owned after λ🙂\n*** End Patch\n"
CALL = {
    "type": "custom_tool_call", "id": "owned-patch-item",
    "call_id": "owned-patch-call", "name": "apply_patch", "input": PATCH,
}
OUTPUT_PATTERN = re.compile(
    r"Exit code: 0\nWall time: ([0-9]+(?:\.[0-9]+)?) seconds\nOutput:\n"
    r"Success\. Updated the following files:\nM owned-notice\.txt\n"
)


def message(identity, text):
    return {"type": "message", "id": identity, "role": "assistant",
            "content": [{"type": "output_text", "text": text}]}


class SuppliedCustomHistoryFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.effect = None

    def snapshot(self):
        target = Path(self.workspace) / "owned-notice.txt"
        assert target.is_file() and not target.is_symlink()
        raw = target.read_bytes()
        assert raw == AFTER.encode(), "Native patch effect differs from literal bytes"
        info = target.stat()
        return {"inode": info.st_ino, "mtime_ns": info.st_mtime_ns,
                "ctime_ns": info.st_ctime_ns, "size": info.st_size,
                "sha256": hashlib.sha256(raw).hexdigest()}

    def response_item(self, index, request):
        assert self.scenario == "custom_history"
        assert request["model"] == "mock-model"
        assert 1 <= index <= 3, "Unexpected extra custom-history inference"
        items = request["input"]
        self.assert_user(items, MARKER)
        if index == 1:
            target = Path(self.workspace) / "owned-notice.txt"
            assert target.is_file() and not target.is_symlink()
            assert target.read_bytes() == BEFORE.encode()
            assert not any(item.get("type") in {"custom_tool_call", "custom_tool_call_output"}
                           for item in items)
            assert sum(tool.get("type") == "custom" and tool.get("name") == "apply_patch"
                       for tool in request["tools"]) == 1
            return dict(CALL)
        self.assert_completed_evidence(items)
        snapshot = self.snapshot()
        if index == 2:
            self.effect = snapshot
            snapshots = [snapshot]
        else:
            assert self.effect is not None and snapshot == self.effect, "Patch effect repeated"
            self.assert_user(items, FOLLOWUP)
            # core/src/client.rs clears non-prefixed provider IDs in request
            # copies; native durable history retains the original full maps.
            expected_answer = {"type": "message", "role": "assistant",
                               "content": [{"type": "output_text", "text": ANSWER}]}
            assert sum(item == expected_answer
                       for item in items) == 1
            metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
            assert metadata["history_initialization"] == "supplied_history"
            snapshots = [self.effect, snapshot]
        destination = self.requests_file.with_name("custom-effect-snapshots.json")
        temporary = destination.with_suffix(".partial")
        temporary.write_text(json.dumps(snapshots))
        temporary.replace(destination)
        if index == 2:
            return message("owned-custom-source-answer", ANSWER)
        return message("owned-custom-followup-answer", FOLLOWUP_ANSWER)

    @staticmethod
    def assert_user(items, text):
        assert sum(item.get("role") == "user" and item.get("content") == [
            {"type": "input_text", "text": text}
        ] for item in items) == 1

    @staticmethod
    def assert_completed_evidence(items):
        calls = [item for item in items if item.get("type") == "custom_tool_call"]
        outputs = [item for item in items if item.get("type") == "custom_tool_call_output"]
        assert calls == [{key: value for key, value in CALL.items() if key != "id"}]
        assert len(outputs) == 1
        output = outputs[0]
        assert isinstance(output.get("id"), str) and output["id"].startswith("ctco_")
        assert set(output) == {"type", "id", "call_id", "output"}
        assert output["call_id"] == "owned-patch-call"
        assert isinstance(output["output"], str) and OUTPUT_PATTERN.fullmatch(output["output"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, choices=["custom_history"])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", required=True, type=Path)
    args = parser.parse_args()
    fixture = SuppliedCustomHistoryFixture(args.scenario, args.workspace, args.requests_file).start()
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
