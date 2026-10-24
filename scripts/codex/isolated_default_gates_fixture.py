#!/usr/bin/env python3
"""Draft no-tools native defaults/gates peer inside private user/net namespaces.

The retained controller owns native UDS startup/cleanup. Only the immutable
native child emits app-server frames. The Responses peer always emits one
fixed assistant message; it cannot request tools, sign in or call a paid API.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


PARENT_USERNS = None
ORIGINAL_CONFIGURE = shared.configure
ORIGINAL_ISOLATION = shared.isolation


class DefaultProvider(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        assert scenario == "assistant"
        super().__init__("assistant", workspace, requests_file)
        self.markers = set()

    def response_item(self, index, request):
        markers = [part["text"] for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and re.fullmatch(r"synthetic:defaults:[0-9]+", part.get("text", ""))]
        assert markers and index <= 32, "unapproved synthetic inference"
        marker = markers[-1]
        assert marker not in self.markers, "unexpected repeated model request"
        self.markers.add(marker)
        return {"type": "message", "role": "assistant", "id": f"owned-default-answer-{index}",
                "content": [{"type": "output_text", "text": "Owned default response"}]}


def configure(root, provider):
    ORIGINAL_CONFIGURE(root, provider)
    catalog = root / "codex/models.json"
    model = json.loads(catalog.read_text())["models"][0]
    model.update({"default_reasoning_level": "low", "supported_reasoning_levels": [
        {"effort": "low", "description": "Owned low"},
        {"effort": "high", "description": "Owned high"}],
        "supports_reasoning_summary_parameter": True,
        "service_tiers": [{"id": "priority", "name": "Owned priority",
                           "description": "Synthetic fixture tier"}]})
    shared.write_json(catalog, {"models": [model]})
    path = root / "codex/config.toml"
    body = path.read_text()
    prefix = 'service_tier = "flex"\nmodel_reasoning_effort = "low"\nmodel_reasoning_summary = "concise"\n'
    features = '''hooks = false
remote_models = false
shell_tool = false
unified_exec = false
enable_request_compression = false
'''
    assert body.count("[shell_environment_policy]") == 1
    path.write_text(prefix + body.replace("[shell_environment_policy]",
                                         features + "[shell_environment_policy]"))


def isolation(parent):
    proof = ORIGINAL_ISOLATION(parent)
    userns = os.readlink("/proc/self/ns/user")
    assert userns != PARENT_USERNS, "BLOCKED_ENV: unchanged user namespace"
    routes = json.loads(subprocess.check_output(
        ["ip", "-6", "-j", "route", "show", "table", "all"], timeout=5))
    assert all(row.get("dev") == "lo" and row.get("dst") not in ["default", "::/0"]
               for row in routes), "BLOCKED_ENV: nonlocal IPv6 route"
    return {**proof, "user_namespace": userns, "parent_user_namespace": PARENT_USERNS,
            "ipv6_default_route": False}


def main():
    global PARENT_USERNS
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
    for name in ["config.toml", "managed_config.toml", "requirements.toml"]:
        assert not (Path("/etc/codex") / name).exists(), "BLOCKED_ENV: host managed config present"
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, str(Path(__file__).resolve()), *sys.argv[1:],
            "--inside", "--parent-netns", os.readlink("/proc/self/ns/net"),
            "--parent-userns", os.readlink("/proc/self/ns/user")])
    PARENT_USERNS = args.parent_userns
    args.scenario = "assistant"
    shared.UserShellProvider = DefaultProvider
    shared.configure = configure
    shared.isolation = isolation
    return shared.run(args)


if __name__ == "__main__":
    main()
