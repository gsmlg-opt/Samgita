#!/usr/bin/env python3
"""Owned Responses metadata peer; native Codex produces all app-server frames."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


PHASE_SCENARIOS = {"phase-commentary": "commentary", "phase-partial-answer": "partial_answer"}
SCENARIOS = ("rich", "null", "nullable-metadata", "stable") + tuple(PHASE_SCENARIOS)
CANARY = "OWNED_RESPONSE_METADATA_PRIVATE_CANARY"
USAGE = {"input_tokens": 12, "input_tokens_details": {"cached_tokens": 3, "cache_write_tokens": 2},
         "output_tokens": 7, "output_tokens_details": {"reasoning_tokens": 4}, "total_tokens": 19}


def metadata(value, **extra):
    return {"type": "response.metadata", "metadata": value, **extra}


class MetadataProvider(ModelFixture):
    def write_response(self, handler, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text", "").startswith("synthetic:")]
        if index != 1 or markers != ["synthetic:response-metadata:" + self.scenario]:
            shared.write_json(Path(self.workspace).parent / "unexpected-inference.json",
                              {"error": "unexpected response metadata inference"})
            raise AssertionError("unexpected response metadata inference")
        identity = "owned-response-" + self.scenario
        rich = self.scenario in {"rich", "stable"}
        item = {"type": "message", "role": "assistant", "id": "owned-metadata-item",
                "content": [{"type": "output_text", "text": "Owned metadata response."}]}
        if rich:
            item.update(status="completed", phase="final_answer")
        elif self.scenario in PHASE_SCENARIOS:
            item.update(status="completed", phase=PHASE_SCENARIOS[self.scenario])
        events = [{"type": "response.created", "response": {"id": identity}}]
        if rich:
            events += [metadata({
                "openai_verification_recommendation": ["unknown", "trusted_access_for_cyber",
                                                       "trusted_access_for_cyber", 42],
                "openai_chatgpt_moderation_metadata": {"presentation": "inline", "owned": [1, None]},
            }, safety_buffering={"use_cases": ["owned-case"], "reasons": ["explicit"],
                                 "retry_model": "owned-wire-fast"}),
                metadata({"openai_verification_recommendation": ["trusted_access_for_cyber"]},
                         safety_buffering={"use_cases": ["owned-case"], "reasons": ["fallback"]}),
                metadata({}, safety_buffering={"use_cases": [], "reasons": ["explicit-null"],
                                               "retry_model": None})]
        elif self.scenario == "nullable-metadata":
            events += [metadata({"openai_chatgpt_moderation_metadata": None})]
        elif self.scenario not in PHASE_SCENARIOS:
            events += [metadata({"openai_verification_recommendation": ["unknown", 42]},
                                safety_buffering=False),
                       {"type": "response.created", "response": {"id": identity},
                        "metadata": {"openai_verification_recommendation": ["trusted_access_for_cyber"],
                                     "openai_chatgpt_moderation_metadata": {"ignored": True}}},
                       metadata({}, safety_buffering={"use_cases": "invalid", "reasons": []})]
        completion = {"id": identity, "usage": USAGE if rich else None}
        if rich:
            completion["usage_metadata"] = {"amount": "0.125", "metadata": {"must_be_replaced": True}}
        elif self.scenario == "nullable-metadata":
            completion["usage_metadata"] = {"amount": None, "metadata": None}
        if self.scenario in PHASE_SCENARIOS:
            # Message phase classifies this item; end_turn independently closes
            # this one sampling response without authorizing a continuation.
            completion["end_turn"] = True
        events += [{"type": "response.output_item.done", "item": item},
                   {"type": "response.completed", "response": completion}]
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.send_header("openai-model", "owned-rerouted-model" if rich else "MOCK-MODEL")
        if rich:
            handler.send_header("x-codex-safety-buffering-faster-model", "owned-header-fast")
        handler.end_headers()
        handler.wfile.write(body)


original_configure, original_isolation = shared.configure, shared.isolation


def configure(root, provider):
    original_configure(root, provider)
    path = root / "codex" / "config.toml"
    body = path.read_text()
    extra = """hooks = false
remote_models = false
shell_tool = false
unified_exec = false
enable_request_compression = false
"""
    assert body.count("[shell_environment_policy]") == 1
    path.write_text("# " + CANARY + "\n" + body.replace("[shell_environment_policy]", extra + "[shell_environment_policy]"))


def isolation(parent):
    proof = original_isolation(parent)
    routes = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"]))
    assert all(row.get("dst") != "default" for row in routes), "unexpected IPv6 default route"
    return {**proof, "ipv6_default_route": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.UserShellProvider, shared.configure, shared.isolation = MetadataProvider, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
