#!/usr/bin/env python3
"""Owned Responses provider and fixed reader for real core unified-exec.

Draft only. Native Codex creates all app-server messages. No command/exec or
thread/shellCommand endpoint is used, and stdin is never evaluated as code.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import termios

import isolated_user_shell_fixture as shared
from model_fixture import ModelFixture


CONTINUE = "owned-continue λ🙂\n"
FINISH = "owned-finish\n"
NAMES = {"pair-a", "pair-b", "clean-a", "clean-b", "interactive", "denial"}
SCENARIOS = {"pair", "clean", "interactive-start", "interactive-write",
             "denial-start", "denial-write"}
JUSTIFICATION = "Run only the fixed owned background-terminal reader"


def command(root, name):
    assert name in NAMES
    def quote(value):
        return "'" + value.replace("'", "'\\''") + "'"
    return "exec " + " ".join(quote(value) for value in [
        sys.executable, str(Path(__file__).resolve()), "--command", "--root", str(root),
        "--name", name])


def owned_reader(args):
    root = args.root.resolve(strict=True)
    assert args.name in NAMES
    state = json.loads((root / "state.json").read_text())
    proof = isolation(state["parent_namespace"])
    assert proof["namespace"] == state["namespace"]
    assert Path.cwd() == root / "workspace"
    assert sys.stdin.isatty() and sys.stdout.isatty()
    # This process is disposable and must not outlive its native owner.
    parent = os.getppid()
    assert ctypes.CDLL(None).prctl(1, signal.SIGKILL, 0, 0, 0) == 0
    assert os.getppid() == parent
    signal.alarm(40)
    attrs = termios.tcgetattr(sys.stdin.fileno())
    attrs[1] &= ~termios.OPOST
    attrs[3] &= ~termios.ECHO
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, attrs)
    path = root / "commands" / (args.name + ".json")
    assert not path.exists(), "owned reader executed twice"
    shared.write_json(path, {**proof, "pid": os.getpid(), "parent_pid": parent,
                             "cwd": str(Path.cwd()), "stdin_tty": True})
    print("owned-ready:" + args.name, flush=True)
    inputs = []
    while True:
        line = sys.stdin.readline()
        assert line in {CONTINUE, FINISH}, "unapproved terminal input"
        inputs.append(line)
        shared.write_json(root / "inputs" / (args.name + ".json"), inputs)
        if line == FINISH:
            print("owned-finished:" + args.name, flush=True)
            return 0
        assert inputs == [CONTINUE], "unexpected repeated terminal input"
        print("owned-read:" + line.rstrip("\n"), flush=True)


class TerminalProvider(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.root = Path(workspace).parent
        self.counts, self.sessions, self.emitted = {}, {}, []

    def record_sessions(self, request):
        for item in request.get("input", []):
            call = item.get("call_id")
            if item.get("type") != "function_call_output" or call not in {
                    "owned-pair-a", "owned-pair-b", "owned-clean-a", "owned-clean-b",
                    "owned-interactive", "owned-denial"}:
                continue
            output = item.get("output")
            assert isinstance(output, str), "native tool output must be text"
            matches = re.findall(r"^Process running with session ID ([0-9]+)$", output,
                                 flags=re.MULTILINE)
            assert len(matches) == 1, "no unique actual native session ID"
            session = {"process_id": matches[0], "output": output}
            if call in self.sessions:
                assert self.sessions[call] == session, "native session identity changed"
            self.sessions[call] = session
        shared.write_json(self.root / "observed-sessions.json", self.sessions)

    def tool(self, name, call, arguments, request):
        catalog = {tool.get("name") for tool in request.get("tools", [])
                   if tool.get("type") == "function"}
        assert name in catalog, "requested core tool absent from actual native catalog"
        item = {"type": "function_call", "name": name, "call_id": call,
                "arguments": json.dumps(arguments)}
        self.emitted.append(item)
        shared.write_json(self.root / "emitted-calls.json", self.emitted)
        return item

    def launch(self, name, request):
        return self.tool("exec_command", "owned-" + name, {
            "cmd": command(self.root, name), "workdir": self.workspace,
            "shell": str(self.root / "bin" / "sh"), "login": False, "tty": True,
            "yield_time_ms": 1000, "max_output_tokens": 1000,
            "sandbox_permissions": "require_escalated", "justification": JUSTIFICATION,
        }, request)

    def write(self, name, suffix, text, request):
        native = self.sessions["owned-" + name]["process_id"]
        return self.tool("write_stdin", "owned-" + suffix, {
            "session_id": int(native), "chars": text, "yield_time_ms": 500,
            "max_output_tokens": 1000,
        }, request)

    def response_item(self, index, request):
        markers = [part.get("text") for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and part.get("text", "").startswith("synthetic:terminals:")]
        assert markers, "unapproved inference"
        scenario = markers[-1].removeprefix("synthetic:terminals:")
        assert scenario in SCENARIOS
        self.record_sessions(request)
        count = self.counts.get(scenario, 0) + 1
        self.counts[scenario] = count
        limit = 3 if scenario in {"pair", "clean"} else 4 if scenario == "interactive-write" else 2
        assert count <= limit, "unexpected additional inference"
        if scenario in {"pair", "clean"} and count < 3:
            return self.launch(scenario + ("-a" if count == 1 else "-b"), request)
        if scenario in {"interactive-start", "denial-start"} and count == 1:
            return self.launch(scenario.removesuffix("-start"), request)
        if scenario == "interactive-write" and count < 4:
            return self.write("interactive", ["continue", "poll", "finish"][count - 1],
                              [CONTINUE, "", FINISH][count - 1], request)
        if scenario == "denial-write":
            assert count == 1, "cancelled write must not trigger another inference"
            return self.write("denial", "denied-write", CONTINUE, request)
        return {"type": "message", "role": "assistant", "id": f"owned-answer-{index}",
                "content": [{"type": "output_text", "text": "Owned terminal turn finished"}]}


original_configure, original_isolation = shared.configure, shared.isolation


def configure(root, provider):
    shared.write_json(root / "interpreter.json", {"executable": sys.executable})
    original_configure(root, provider)
    path = root / "codex" / "config.toml"
    body = path.read_text()
    extra = """unified_exec = true
unified_exec_tty = true
write_stdin_approval = true
hooks = false
remote_models = false
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
    parser.add_argument("--codex")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--command", action="store_true")
    parser.add_argument("--name", choices=sorted(NAMES))
    args = parser.parse_args()
    if args.command:
        return owned_reader(args)
    assert args.codex and args.name is None
    if not args.inside:
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    # The reused controller owns only native startup/stop and fixed restart
    # control. It never runs another fixture's provider or command scenario.
    args.scenario = "standalone"
    shared.UserShellProvider, shared.configure, shared.isolation = TerminalProvider, configure, isolation
    shared.run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
