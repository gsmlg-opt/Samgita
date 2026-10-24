#!/usr/bin/env python3
"""Synthetic Responses failures only; pinned native Codex owns all client errors."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


SCENARIOS = ("rate-recovered", "rate-exhausted", "overload-terminal")
RATE_MESSAGE = "Owned provider rate limit."


class ProviderErrors(ModelFixture):
    def write_response(self, handler, index, request):
        root = Path(self.workspace).parent
        initial = "synthetic:provider-error:" + self.scenario
        followup = initial + ":explicit-next-turn"
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if isinstance(part, dict)
                   and part.get("text", "").startswith("synthetic:provider-error:")]
        initial_count = 1 if self.scenario == "overload-terminal" else 2
        is_initial = index <= initial_count and markers == [initial]
        is_followup = index == initial_count + 1 and markers == [initial, followup]
        if not (is_initial or is_followup) or handler.headers.get("Authorization") is not None:
            shared.write_json(root / "unexpected-inference.json", {
                "index": index, "markers": markers,
                "error": "unexpected provider error request or authentication",
            })
            raise AssertionError("unexpected provider error request")

        identity = f"owned-provider-error-{self.scenario}-{index}"
        events = [{"type": "response.created", "response": {"id": identity}}]
        succeeds = is_followup or (self.scenario == "rate-recovered" and index == 2)
        if succeeds:
            events += [{"type": "response.output_item.done", "item": {
                "type": "message", "role": "assistant", "id": f"owned-error-answer-{index}",
                "content": [{"type": "output_text", "text": "Owned provider error recovery."}],
            }}, {"type": "response.completed", "response": {"id": identity, "usage": {
                "input_tokens": 1, "input_tokens_details": None,
                "output_tokens": 1, "output_tokens_details": None, "total_tokens": 2,
            }}}]
        else:
            error = ({"code": "server_is_overloaded", "message": "Provider overload text is not the native display."}
                     if self.scenario == "overload-terminal" else
                     {"code": "rate_limit_exceeded", "message": RATE_MESSAGE})
            # No retry advice is supplied. The native rate-limit and overload
            # policies intentionally differ even with stream_max_retries = 1.
            events.append({"type": "response.failed", "response": {
                "id": identity, "error": error,
            }})

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
    assert body.count("stream_max_retries = 0") == 1
    body = body.replace("stream_max_retries = 0", "stream_max_retries = 1")
    extra = """hooks = false
remote_models = false
shell_tool = false
unified_exec = false
enable_request_compression = false
"""
    assert body.count("[shell_environment_policy]") == 1
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
    parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.UserShellProvider, shared.configure, shared.isolation = ProviderErrors, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
