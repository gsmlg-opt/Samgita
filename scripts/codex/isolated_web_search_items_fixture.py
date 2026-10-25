#!/usr/bin/env python3
"""Owned Responses web-search output mapping; stock Codex emits app-server frames.

No browsing is requested.
The HTTPS URLs below are inert data; web_search and execution remain disabled.
Unknown/missing Responses actions become app-server Other; results stay null.
This does not qualify hosted search, structured results or action:null.

Pinned rust-v0.163.0 / 83086188ae0614bd882818ff1aa23f3194962012.
Source archive SHA256:
e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567
The following extracted files were byte-verified against that archive:
protocol/src/models.rs:1227-1239,2067-2097
  df9a3da250376d86203a8a1219b2e4b5353a62274d094bb36998560433bd58eb
core/src/event_mapping.rs:228-242
  39d31853d2ac22df6b96ac22bc5637b5e50e2503e6dab0c3228a5af0759ea1f0
core/src/stream_events_utils.rs:315-400,443-456 (non-dispatched output lifecycle)
  3316d151e21ddacb0f4fb976045b67245296b4e798b168c532dfb69a588eb139
core/src/web_search.rs:1-32 (display query is not arbitrary provider output)
  7029c8ad137965387cba1b499d653913110d6b10e209689bea0c78a891854d37
ext/items/src/web_search.rs:1-44 (camelCase action, explicit null results)
  f4b11081a91a0c305fc79aaaba113a14ab314cf694a7a4e0b257fafe9a43a1c3
app-server-protocol/src/protocol/v2/item.rs:856-871,992-998
  e3ca6b9b880d815a16ff956b701beb9690abc222fb70a5b7e697e1c0ff91e099
app-server-protocol/src/protocol/thread_history.rs:619-688
  73334586efa8b67c1f2037de2c78b49e72a7ec3f3339cf305bfafd54d4bdf2ac

Immutable anchors use https://github.com/openai/codex/blob/
83086188ae0614bd882818ff1aa23f3194962012/codex-rs/<path>#L<line>.
The unchanged shared namespace/native/cleanup harness has SHA256:
4d8a7b0186ab4a508f8743a64cb2cc453546522a3adb850c192b1f886c49fad7
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


SCENARIO = "fixed-web-search-items"
MARKER = "synthetic:web-search-items:" + SCENARIO
PAGE = "https://web-search.synthetic.invalid/owned-page"


def response_items():
    # Responses action discriminants are snake_case; native app-server output
    # uses camelCase. These are provider inputs, never app-server expected frames.
    actions = [
        ("search", {"type": "search", "query": "owned primary λ",
                    "queries": ["owned first", "owned second"]}),
        ("open", {"type": "open_page", "url": PAGE}),
        ("find", {"type": "find_in_page", "url": PAGE, "pattern": "owned needle"}),
        ("unknown", {"type": "owned_future_action", "ignored": "owned inert data"}),
        ("missing", None),
    ]
    items = []
    for name, action in actions:
        item = {"type": "web_search_call", "id": "owned-web-" + name,
                "status": "completed"}
        if action is not None:
            item["action"] = action
        items.append(item)
    return items


class WebSearchItemsProvider(ModelFixture):
    def write_response(self, handler, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text", "").startswith("synthetic:")]
        if self.scenario != SCENARIO or index != 1 or markers != [MARKER]:
            shared.write_json(Path(self.workspace).parent / "unexpected-inference.json",
                              {"error": "unexpected web-search output inference"})
            raise AssertionError("unexpected web-search output inference")
        assert all(tool.get("type") not in {"web_search", "web_search_preview"}
                   for tool in request.get("tools", []))
        identity = "owned-web-search-response"
        items = response_items() + [{"type": "message", "id": "owned-web-answer",
            "role": "assistant", "status": "completed", "phase": "final_answer",
            "content": [{"type": "output_text", "text": "Owned inert web-search output."}]}]
        events = [{"type": "response.created", "response": {"id": identity}}]
        events.extend({"type": "response.output_item.done", "item": item} for item in items)
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
    assert body.count("[shell_environment_policy]") == 1
    extra = """hooks = false
remote_models = false
shell_tool = false
unified_exec = false
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
    shared.UserShellProvider, shared.configure, shared.isolation = WebSearchItemsProvider, configure, isolation
    # All native restart/startup/teardown behavior and deadlines remain shared.
    shared.run(args)


if __name__ == "__main__":
    main()
