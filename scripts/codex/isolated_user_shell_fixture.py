#!/usr/bin/env python3
"""Real pinned user-shell lifecycle inside a private network namespace.

The only provider is an owned synthetic Responses peer. Native Codex produces
every app-server message. Commands can touch only this fixture's disposable
workspace/markers; their namespace is verified independently before any effect.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

from model_fixture import ModelFixture


BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def isolation(parent):
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace != parent, "BLOCKED_ENV: unchanged network namespace"
    interfaces = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert [row["ifname"] for row in interfaces] == ["lo"], "BLOCKED_ENV: nonloopback link"
    assert all(row.get("dev") == "lo" and row.get("dst") != "default" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    return {"namespace": namespace, "parent_namespace": parent,
            "interfaces": ["lo"], "default_route": False}


def owned_command(args):
    root = args.root.resolve(strict=True)
    state = json.loads((root / "state.json").read_text())
    proof = isolation(state["parent_namespace"])
    assert proof["namespace"] == state["namespace"]
    assert re.fullmatch(r"[a-z][a-z0-9-]*", args.name)
    marker = root / "commands" / (args.name + ".json")
    assert not marker.exists(), "synthetic command executed twice"
    write_json(marker, {**proof, "pid": os.getpid(), "parent_pid": os.getppid(),
                        "cwd": os.getcwd(), "mode": args.mode})
    if args.mode == "held":
        print("owned-ready:" + args.name, flush=True)
        deadline = time.monotonic() + 12
        while not (root / "releases" / args.name).exists():
            assert time.monotonic() < deadline, "owned shell release deadline"
            time.sleep(0.01)
        print("owned-done:" + args.name, flush=True)
    elif args.mode == "quick":
        print("owned-output:" + args.name, flush=True)
    elif args.mode == "fail":
        print("owned-stdout", flush=True)
        print("owned-stderr", file=sys.stderr, flush=True)
        return 7
    elif args.mode == "stdin":
        print(json.dumps({"stdin": sys.stdin.read(), "cwd": os.getcwd()}), flush=True)
    else:
        raise AssertionError("noncanonical owned command mode")
    return 0


class UserShellProvider(ModelFixture):
    def response_item(self, index, request):
        assert self.scenario == "active", "standalone user-shell requested model inference"
        assert index in (1, 2), "unexpected extra native provider request"
        if index == 1:
            return {"type": "function_call", "name": "exec_command",
                    "call_id": "owned-held-agent-command", "arguments": json.dumps({
                        "cmd": "printf never-authorized-user-shell-peer",
                        "workdir": self.workspace, "login": False,
                        "sandbox_permissions": "require_escalated",
                        "justification": "Owned synthetic approval barrier; always decline",
                    })}
        return {"type": "message", "role": "assistant", "id": "owned-active-answer",
                "content": [{"type": "output_text", "text": "Owned active turn finished"}]}


def configure(root, provider):
    catalog = root / "codex" / "models.json"
    write_json(catalog, {"models": [{
        "slug": "mock-model", "display_name": "Owned synthetic user-shell",
        "supported_reasoning_levels": [], "shell_type": "unified_exec",
        "visibility": "list", "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Synthetic user-shell qualification only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
        "experimental_supported_tools": [],
    }]})
    (root / "codex" / "config.toml").write_text(f'''
model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
chatgpt_base_url = "{provider.url}"
openai_base_url = "{provider.url}/v1"
[features]
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
[shell_environment_policy]
inherit = "all"
[model_providers.fixture]
name = "Owned synthetic user-shell provider"
base_url = "{provider.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')


def run(args):
    root = args.root.resolve(strict=True)
    codex = Path(args.codex).resolve(strict=True)
    assert hashlib.sha256(codex.read_bytes()).hexdigest() == BINARY_SHA256, "unpinned native binary"
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])

    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    proof = isolation(args.parent_netns)
    provider = UserShellProvider(args.scenario, root / "workspace", root / "requests.json")
    provider.server.daemon_threads = True
    provider.start()
    configure(root, provider)
    native = None
    socket_path = root / "native.sock"
    state = {**proof, "controller_pid": os.getpid(), "namespace_owner_pid": os.getppid(),
             "native_pids": [], "generation": 0, "ready": False}

    def persist():
        write_json(root / "state.json", state)

    def stop():
        nonlocal native
        state["ready"] = False
        persist()
        if native is not None:
            native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
            native = None

    def start():
        nonlocal native
        if socket_path.exists():
            assert stat.S_ISSOCK(socket_path.lstat().st_mode), "unexpected owned socket replacement"
            socket_path.unlink()
        environment = {key: value for key, value in os.environ.items()
                       if key in {"HOME", "CODEX_HOME", "PATH", "TMPDIR", "NO_COLOR",
                                  "RUST_LOG", "CODEX_DISABLE_REMOTE_CONTROL", "SHELL",
                                  "PYTHONDONTWRITEBYTECODE"}}
        native = subprocess.Popen([str(codex), "app-server", "--listen", "unix://" + str(socket_path)],
                                  cwd=root / "workspace", env=environment,
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        state["native_pids"].append(native.pid)
        state["generation"] += 1
        deadline = time.monotonic() + 5
        while not socket_path.exists():
            assert native.poll() is None, "native startup exited"
            assert time.monotonic() < deadline, "native owned UDS startup deadline"
            time.sleep(0.01)
        state["ready"] = True
        persist()

    def terminate(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    try:
        start()
        for line in sys.stdin:
            assert json.loads(line) == {"restart": True}, "unexpected fixture control operation"
            stop()
            start()
    finally:
        stop()
        provider.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--scenario", choices=["standalone", "active"], default="standalone")
    parser.add_argument("--command", action="store_true")
    parser.add_argument("--name")
    parser.add_argument("--mode", choices=["held", "quick", "fail", "stdin"])
    args = parser.parse_args()
    if args.command:
        return owned_command(args)
    run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
