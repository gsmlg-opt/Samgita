#!/usr/bin/env python3
"""Source-review draft: provider SSE for seven active native output notices.

Reuses unchanged isolated controller and model-provider primitives. No function
constructs app-server JSON-RPC, authorizes an approval, or invokes a shell tool.
"""
import argparse
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_tool_interactions_fixture as shared
from model_fixture import ModelFixture


BEFORE = "owned before\n"
AFTER = "owned after λ🙂\n"
PATCH_PARTS = [
    "*** Begin Patch\n*** Update File: owned-notice.txt\n@@\n-owned before\n+owned ",
    "after λ🙂\n*** End Patch\n",
]
PLAN_PARTS = ["Preface\n<proposed_", "plan>\n# Owned plan λ🙂\n- first\n", "- second\n</proposed_plan>\nPostscript"]
SUMMARY_PARTS = [(0, "Synthetic summary "), (0, "λ🙂"), (1, "Synthetic second summary")]
RAW_PARTS = [(2, "Synthetic raw "), (2, "α🙂")]
CHECKLIST = {
    "explanation": "Synthetic checklist λ🙂",
    "plan": [
        {"step": "Owned completed step", "status": "completed"},
        {"step": "Owned current step", "status": "in_progress"},
        {"step": "Owned pending step", "status": "pending"},
    ],
}


def message(identity, text):
    return {"type": "message", "role": "assistant", "id": identity,
            "content": [{"type": "output_text", "text": text}]}


def added(item):
    return {"type": "response.output_item.added", "item": item}


def done(item):
    return {"type": "response.output_item.done", "item": item}


def events(index, item):
    body = []
    if item["type"] == "reasoning":
        body.append(added({"type": "reasoning", "id": item["id"], "summary": []}))
        for summary_index in [0, 1]:
            body.append({"type": "response.reasoning_summary_part.added",
                         "summary_index": summary_index})
            body.extend({"type": "response.reasoning_summary_text.delta", "delta": text,
                         "summary_index": part_index}
                        for part_index, text in SUMMARY_PARTS if part_index == summary_index)
        body.extend({"type": "response.reasoning_text.delta", "delta": text,
                     "content_index": content_index} for content_index, text in RAW_PARTS)
        body += [done(item), done(message("owned-reasoning-answer", "Synthetic reasoning finished"))]
    elif item.get("id") == "owned-plan-message":
        empty = deepcopy(item)
        empty["content"][0]["text"] = ""
        body = [added(empty), *({"type": "response.output_text.delta", "delta": part}
                               for part in PLAN_PARTS), done(item)]
    elif item["type"] == "custom_tool_call":
        empty = {**item, "input": "", "status": "in_progress"}
        body = [added(empty), *({"type": "response.custom_tool_call_input.delta",
                                "item_id": item["id"], "call_id": item["call_id"],
                                "delta": part} for part in PATCH_PARTS), done(item)]
    else:
        body = [done(item)]
    identity = f"owned-output-response-{index}"
    return [{"type": "response.created", "response": {"id": identity}}, *body,
            {"type": "response.completed", "response": {"id": identity, "usage": {
                "input_tokens": 0, "input_tokens_details": None,
                "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
            }}}]


class OutputProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("output-notices", root / "workspace", root / "requests.json")
        self.root, self.calls = root, {}

    def response_item(self, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text") in {"synthetic:output-reasoning", "synthetic:output-plan",
                                            "synthetic:output-checklist", "synthetic:output-patch"}]
        assert len(markers) == 1, "unapproved synthetic inference"
        scenario = markers[0].removeprefix("synthetic:output-")
        count = self.calls.get(scenario, 0) + 1
        self.calls[scenario] = count
        assert count <= (2 if scenario in {"checklist", "patch"} else 1), "extra inference"
        if count == 2:
            call_id = "owned-checklist-call" if scenario == "checklist" else "owned-patch-call"
            assert any(item.get("call_id") == call_id and item.get("type") in {
                "function_call_output", "custom_tool_call_output"}
                       for item in request.get("input", [])), "missing actual tool output"
            return message(f"owned-final-{index}", "Synthetic tool finished")
        if scenario == "reasoning":
            return {"type": "reasoning", "id": "owned-reasoning", "summary": [
                {"type": "summary_text", "text": "Synthetic summary λ🙂"},
                {"type": "summary_text", "text": "Synthetic second summary"}],
                    "content": [{"type": "reasoning_text", "text": text}
                                for text in ["", "", "Synthetic raw α🙂"]]}
        if scenario == "plan":
            return message("owned-plan-message", "".join(PLAN_PARTS))
        if scenario == "checklist":
            return {"type": "function_call", "name": "update_plan",
                    "call_id": "owned-checklist-call", "arguments": json.dumps(CHECKLIST)}
        target = Path(self.workspace) / "owned-notice.txt"
        assert target.parent.resolve() == Path(self.workspace)
        assert target.is_file() and not target.is_symlink() and target.read_text() == BEFORE
        return {"type": "custom_tool_call", "id": "owned-patch-item", "name": "apply_patch",
                "call_id": "owned-patch-call", "input": "".join(PATCH_PARTS)}

    def write_response(self, handler, index, request):
        output = events(index, self.response_item(index, request))
        path = self.root / "provider-events.json"
        previous = json.loads(path.read_text()) if path.exists() else []
        shared.write_json(path, previous + [output])
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in output).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)


def configure(root, provider):
    shared_configure(root, provider)
    catalog = root / "codex" / "models.json"
    data = json.loads(catalog.read_text())
    data["models"][0]["apply_patch_tool_type"] = "freeform"
    shared.write_json(catalog, data)
    path = root / "codex" / "config.toml"
    config = "show_raw_agent_reasoning = true\nhide_agent_reasoning = false\n" + path.read_text()
    extra = """hooks = false
remote_models = false
concurrent_reasoning_summaries = false
collaboration_modes = true
apply_patch_streaming_events = true
[tools.update_plan]
enabled = true
"""
    assert config.count("[model_providers.fixture]") == 1
    path.write_text(config.replace("[model_providers.fixture]", extra + "[model_providers.fixture]"))


def isolation(parent):
    proof = shared_isolation(parent)
    routes = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"]))
    assert all(row.get("dst") != "default" for row in routes), "unexpected IPv6 default route"
    return {**proof, "ipv6_default_route": False}


shared_configure, shared_isolation = shared.configure, shared.isolation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.ToolProvider, shared.configure, shared.isolation = OutputProvider, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
