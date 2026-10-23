#!/usr/bin/env python3
"""Native local notices in an owned namespace; one fixed history turn is optional.

Reuses the unchanged native controller and config primitives. This fixture
never creates app-server messages, hooks or commands. Only the history scenario
may return one fixed text-only model response; every other inference fails.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


class NoticeProvider(ModelFixture):
    def response_item(self, index, request):
        if self.scenario == "history":
            markers = [part.get("text") for item in request.get("input", [])
                       if item.get("role") == "user" for part in item.get("content", [])
                       if part.get("type") == "input_text"
                       and part.get("text", "").startswith("synthetic:")]
            if index == 1 and markers == ["synthetic:configuration-notice-history"]:
                return {"type": "message", "role": "assistant", "id": "owned-notice-history",
                        "content": [{"type": "output_text", "text": "Owned notice history."}]}
        shared.write_json(Path(self.workspace).parent / "unexpected-inference.json", {
            "error": "unapproved configuration notice inference"})
        raise AssertionError("unapproved configuration notice inference")


original_configure, original_isolation = shared.configure, shared.isolation


def configure(root, provider):
    original_configure(root, provider)
    catalog_path = root / "codex" / "models.json"
    catalog = json.loads(catalog_path.read_text())
    catalog["models"][0]["service_tiers"] = []
    catalog["models"][0]["additional_speed_tiers"] = []
    shared.write_json(catalog_path, catalog)
    path = root / "codex" / "config.toml"
    body = path.read_text()
    extra = """hooks = false
remote_models = false
shell_tool = false
unified_exec = false
fast_mode = true
enable_request_compression = false
"""
    assert body.count("[shell_environment_policy]") == 1
    body = body.replace("[shell_environment_policy]", extra + "[shell_environment_policy]")
    if provider.scenario == "ignored":
        body = "network_proxy = { nested = 'owned-private-marker' }\n" + body
    elif provider.scenario == "tier":
        body = "service_tier = 'priority'\n" + body
    else:
        assert provider.scenario in {"clean", "history"}
    path.write_text(body)


def isolation(parent):
    proof = original_isolation(parent)
    routes = json.loads(subprocess.check_output(["ip", "-6", "-j", "route", "show", "table", "all"]))
    assert all(row.get("dst") != "default" for row in routes), "unexpected IPv6 default route"
    return {**proof, "ipv6_default_route": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--scenario", choices=["ignored", "clean", "tier", "history"], default="clean")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    shared.UserShellProvider, shared.configure, shared.isolation = NoticeProvider, configure, isolation
    shared.run(args)


if __name__ == "__main__":
    main()
