#!/usr/bin/env python3
"""Owned response-header peer; pinned native Codex emits all app-server frames."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


CANARY = "OWNED_RATE_LIMITS_PRIVATE_CANARY"
SCENARIOS = ("windows", "alternate", "credits-only", "sparse", "malformed", "empty")
HEADERS = {
    "windows": {
        "x-codex-primary-used-percent": "12.5",
        "x-codex-primary-window-minutes": "60",
        "x-codex-primary-reset-at": "1704069000",
        "x-codex-secondary-used-percent": "99.49",
        "x-codex-secondary-window-minutes": "10080",
        "x-codex-secondary-reset-at": "1704673800",
        "x-codex-limit-name": "  Owned Codex quota  ",
        "x-codex-credits-has-credits": "TrUe",
        "x-codex-credits-unlimited": "0",
        "x-codex-credits-balance": "  123.4500  ",
    },
    "alternate": {
        "x-codex-primary-used-percent": "95",
        "x-codex-primary-window-minutes": "60",
        "x-codex-primary-reset-at": "1704069000",
        "x-codex-limit-name": "Default superseded before token fanout",
        "x-codex-other-primary-used-percent": "0",
        "x-codex-other-primary-reset-at": "0",
        "x-codex-other-secondary-used-percent": "42.5",
        "x-codex-other-secondary-window-minutes": "1440",
        "x-codex-other-secondary-reset-at": "-1",
        "x-codex-other-limit-name": "  Owned alternate quota  ",
        "x-unused-primary-used-percent": "NaN",
    },
    "credits-only": {
        "x-codex-credits-has-credits": "FALSE",
        "x-codex-credits-unlimited": "1",
        "x-codex-credits-balance": "   ",
    },
    "sparse": {
        "x-codex-primary-used-percent": "2.49",
        "x-codex-primary-window-minutes": "not-an-integer",
        "x-codex-primary-reset-at": "not-an-integer",
        "x-codex-secondary-used-percent": "0",
        "x-codex-secondary-window-minutes": "0",
        "x-codex-limit-name": "   ",
        "x-codex-credits-has-credits": "yes",
        "x-codex-credits-unlimited": "true",
    },
    "malformed": {
        "x-codex-primary-used-percent": "NaN",
        "x-codex-primary-window-minutes": "60",
        "x-codex-primary-reset-at": "1704069000",
        "x-codex-secondary-used-percent": "inf",
        "x-codex-secondary-window-minutes": "10080",
        "x-codex-secondary-reset-at": "9223372036854775808",
        "x-codex-credits-has-credits": "true",
        "x-codex-credits-unlimited": "invalid",
        "x-invalid-primary-used-percent": "invalid",
        "x-codex-plan-type": "pro",
        "x-codex-normal-model-slug": "must-not-be-invented",
        "x-codex-spend-control-reached": "true",
        "x-codex-rate-limit-reached-type": "rate_limit_reached",
    },
    "empty": {},
}


class RateLimitsProvider(ModelFixture):
    def write_response(self, handler, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text", "").startswith("synthetic:")]
        if (index != 1 or markers != ["synthetic:rate-limits:" + self.scenario]
                or handler.headers.get("Authorization") is not None):
            shared.write_json(Path(self.workspace).parent / "unexpected-inference.json",
                              {"error": "unexpected rate-limit inference or authorization"})
            raise AssertionError("unexpected rate-limit inference or authorization")
        identity = "owned-rate-limits-" + self.scenario
        events = [
            {"type": "response.created", "response": {"id": identity}},
            {"type": "response.output_item.done", "item": {
                "type": "message", "role": "assistant", "id": "owned-rate-limits-item",
                "content": [{"type": "output_text", "text": "Owned rate-limit response."}],
            }},
            {"type": "response.completed", "response": {"id": identity, "usage": {
                "input_tokens": 1, "input_tokens_details": None,
                "output_tokens": 1, "output_tokens_details": None, "total_tokens": 2,
            }}},
        ]
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        for name, value in HEADERS[self.scenario].items():
            handler.send_header(name, value)
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
    shared.UserShellProvider, shared.configure, shared.isolation = RateLimitsProvider, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
