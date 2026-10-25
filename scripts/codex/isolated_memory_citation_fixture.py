#!/usr/bin/env python3
"""Owned Responses citation markup; stock Codex emits every app-server frame.

Two actual assistant message producers are prescribed, never injected
MemoryCitation/runtime data:
modern rollout_ids (first-seen dedup, precedence over thread_ids) and legacy
thread_ids fallback. Synthetic paths/IDs are inert output strings, not host files.
No retrieval/account/host memory, paid/provider service or full coverage claim.

Pinned rust-v0.163.0 / 83086188ae0614bd882818ff1aa23f3194962012.
Archive SHA256 e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567.
The following extracted files were byte-verified against that archive:
core/src/stream_events_utils.rs 3316d151e21ddacb0f4fb976045b67245296b4e798b168c532dfb69a588eb139
core/src/stream_events_utils_tests.rs 32414fa3971f54b254bc9ad7b82b227896cbb69dd8ee37e336e620311be56356
protocol/src/memory_citation.rs 37dc99601986fae386a737efb29d3af4636acad16bb7588af6206d8608812fd8
memories/read/src/citations.rs 96549a57473f683a6c9d383a69bc30816ba177307dd2b01f6270eddfafa07156
memories/read/src/citations_tests.rs 99bff775ed93feffb9a4d59e13b4329619bd6fe420ca29b5d72208d0a01f31a2
utils/stream-parser/src/citation.rs 6b07dab550e6ad5d633b0b1af4466d788b500ff9cb0058d7f3945477d147b24d
app-server-protocol/src/protocol/v2/item.rs e3ca6b9b880d815a16ff956b701beb9690abc222fb70a5b7e697e1c0ff91e099
rollout/src/policy.rs 44243ebf3ea74fd96a9f00adf84c36c7b5f36d3d102c32fcc8c540a49203df3f
config/src/types.rs 387881a40e59d4f72a0edab603c3298368466137c09c02d43a3d6704428c14d2
app-server/src/request_processors/thread_processor.rs f98fdad7df37ad720e63b75488ffab99ae88f7de4578b280ab957a09f0a98153

Unchanged local scripts/codex/isolated_user_shell_fixture.py SHA256:
4d8a7b0186ab4a508f8743a64cb2cc453546522a3adb850c192b1f886c49fad7

Immutable anchors: https://github.com/openai/codex/blob/
83086188ae0614bd882818ff1aa23f3194962012/codex-rs/<path>#L<line>
- core/src/stream_events_utils.rs:46-59,315-400,465-488:
  done-only message maps, strips and parses before real started/completed events.
- core/src/stream_events_utils_tests.rs:192-198,272-287:
  ordinary finalization produces citation; no contributor is required.
- memories/read/src/citations.rs:6-43,45-51,54-85:
  parsing is text-only; exact entry fields, first-seen string ID dedup, rollout_ids
  precedence and legacy fallback. UUID filtering is only usage accounting.
- core/src/stream_events_utils.rs:201-218:
  invalid synthetic IDs skip local usage lookup; no citation path file is opened.
- utils/stream-parser/src/citation.rs:11-21,69-76:
  literal hidden markup is stripped, including its contents.
- app-server-protocol/src/protocol/v2/item.rs:152-187,888-904:
  rollout_ids are mapped directly to wire threadIds; entry values preserved.
- rollout/src/policy.rs:132-145,228-281:
  paginated mode retains actual materialized completed items, not legacy surrogates.
- app-server/src/request_processors/thread_processor.rs:3622-3670:
  selective public reads use persisted store, with no resume/turn execution.
- config/src/types.rs:322-334,406-407:
  fixture explicitly disables memory generation and usage.

The shared namespace/startup/restart/reaping implementation is unmodified.
Integration needs existing isolated_user_shell_fixture.py and model_fixture.py
beside this new fixture; the two-file candidate is not a copied repository.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


SCENARIO = "fixed-memory-citation"
MARKER = "synthetic:memory-citation:" + SCENARIO


def response_items():
    modern = (
        "Owned modern visible λ."
        "<oai-mem-citation>\n<citation_entries>\n"
        " synthetic/owned-memory.md:7-11|note=[ owned summary λ ]\n"
        "synthetic/owned-detail.md:20-23|note=[owned detail]\n"
        "</citation_entries>\n<rollout_ids>\n"
        "owned-rollout-alpha\nowned-rollout-beta\nowned-rollout-alpha\n"
        "</rollout_ids>\n<thread_ids>\nowned-ignored-legacy\n</thread_ids>\n"
        "</oai-mem-citation> Tail."
    )
    legacy = (
        "Owned legacy visible."
        "<oai-mem-citation>\n<citation_entries>\n"
        "synthetic/owned-legacy.md:2-4|note=[owned legacy note]\n"
        "</citation_entries>\n<thread_ids>\n"
        "owned-thread-first\nowned-thread-second\nowned-thread-first\n"
        "</thread_ids>\n</oai-mem-citation> Done."
    )
    return [
        {"type": "message", "id": "owned-memory-modern", "role": "assistant",
         "status": "completed", "phase": "commentary",
         "content": [{"type": "output_text", "text": modern}]},
        {"type": "message", "id": "owned-memory-legacy", "role": "assistant",
         "status": "completed", "phase": "final_answer",
         "content": [{"type": "output_text", "text": legacy}]},
    ]


class MemoryCitationProvider(ModelFixture):
    def write_response(self, handler, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text", "").startswith("synthetic:")]
        if self.scenario != SCENARIO or index != 1 or markers != [MARKER]:
            shared.write_json(Path(self.workspace).parent / "unexpected-inference.json",
                              {"error": "unexpected memory-citation inference"})
            raise AssertionError("unexpected memory-citation inference")
        assert all(tool.get("type") not in {"web_search", "web_search_preview"}
                   for tool in request.get("tools", []))
        identity = "owned-memory-citation-response"
        events = [{"type": "response.created", "response": {"id": identity}}]
        events.extend({"type": "response.output_item.done", "item": item}
                      for item in response_items())
        events.append({"type": "response.completed", "response": {
            "id": identity, "end_turn": True, "usage": {
                "input_tokens": 0, "input_tokens_details": None,
                "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0}}})
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)


original_configure, original_isolation = shared.configure, shared.isolation


def configure(root, provider):
    original_configure(root, provider)
    path = root / "codex" / "config.toml"
    body = path.read_text()
    assert 'web_search = "disabled"' in body
    assert body.count("[features]") == 1
    assert body.count("[shell_environment_policy]") == 1
    body = body.replace("[features]", "[memories]\ngenerate_memories = false\n"
                        "use_memories = false\n[features]")
    extra = """hooks = false
remote_models = false
shell_tool = false
unified_exec = false
memories = false
enable_request_compression = false
"""
    path.write_text(body.replace("[shell_environment_policy]", extra + "[shell_environment_policy]"))


def isolation(parent):
    proof = original_isolation(parent)
    routes = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"]))
    assert all(row.get("dst") != "default" for row in routes), "unexpected IPv6 default route"
    return {**proof, "ipv6_default_route": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--scenario", choices=[SCENARIO], required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.UserShellProvider, shared.configure, shared.isolation = MemoryCitationProvider, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
