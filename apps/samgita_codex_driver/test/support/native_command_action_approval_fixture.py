#!/usr/bin/env python3
"""Fixed scratch-only native Read/ListFiles/Search approval qualification.

Only the pinned native binary emits app-server frames, on its own Unix socket.
This controller owns the Responses peer, fixed command launchers and namespace.
Launchers journal once, invoke captured stock tools, and preserve their output.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
NATIVE_SHA = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
MAX_BODY = 1_048_576
INPUTS = {
    "owned.txt": b"owned read contents v119\n",
    "owned-dir/alpha.txt": b"owned alpha contents v119\n",
    "owned-dir/needle.txt": b"haystack\nOWNED_NEEDLE v119\n",
}
SPECS = {
    "read": ("cat", ["owned.txt"]),
    "list": ("ls", ["-1", "owned-dir"]),
    "search": ("rg", ["-n", "OWNED_NEEDLE", "owned-dir/needle.txt"]),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    body = json.dumps(value)
    assert len(body.encode()) <= MAX_BODY, "Owned journal byte bound"
    pending = path.with_suffix(".pending")
    pending.write_text(body)
    pending.replace(path)


def immutable_inputs(root):
    workspace = root / "workspace"
    assert workspace.is_dir() and not workspace.is_symlink()
    assert (workspace / "owned-dir").is_dir() and not (workspace / "owned-dir").is_symlink()
    assert sorted(p.relative_to(workspace).as_posix() for p in workspace.rglob("*")
                  if p.is_file()) == sorted(INPUTS)
    assert sorted(p.relative_to(workspace).as_posix() for p in workspace.rglob("*")
                  if p.is_dir()) == ["owned-dir"]
    result = {}
    for name, expected in INPUTS.items():
        path = workspace / name
        assert not path.is_symlink() and path.resolve(strict=True).is_relative_to(workspace)
        assert path.read_bytes() == expected
        stat = path.stat()
        result[name] = {"sha256": sha(expected), "size": stat.st_size,
                        "mode": stat.st_mode, "mtime_ns": stat.st_mtime_ns}
    return result


def command_probe(args):
    root = args.root.resolve(strict=True)
    state = json.loads((root / "state.json").read_text())
    assert args.scenario == state["scenario"]
    name, expected_args = SPECS[args.scenario]
    assert args.command_args == expected_args, "Noncanonical owned command arguments"
    assert Path.cwd() == root / "workspace", "Unexpected owned command cwd"
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace == state["namespace"]["child"]
    assert namespace != state["namespace"]["parent"]
    assert shutil.which(name) == str(root / "bin" / name), "Native PATH bypassed owned launcher"
    before = immutable_inputs(root)
    assert before == state["inputs"]
    captured = state["stock"][name]
    executable = Path(captured["path"])
    assert executable.is_absolute() and executable.is_file()
    assert not executable.is_relative_to(root)
    assert sha(executable.read_bytes()) == captured["sha256"]
    marker = root / "commands" / (args.scenario + ".json")
    journal = {"status": "started", "scenario": args.scenario,
               "pid": os.getpid(), "parent_pid": os.getppid(), "namespace": namespace,
               "cwd": str(Path.cwd()), "args": [name, *expected_args],
               "executable": str(executable), "executable_sha256": captured["sha256"]}
    # Exclusive creation precedes the stock launch. A duplicate cannot run again.
    with marker.open("x") as target:
        target.write(json.dumps(journal))
    environment = {
        "HOME": str(root / "home"), "TMPDIR": str(root / "tmp"),
        "PATH": str(root / "bin"), "LC_ALL": "C", "LANG": "C", "NO_COLOR": "1",
    }
    child = subprocess.Popen([str(executable), *expected_args], cwd=root / "workspace",
                             env=environment, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    journal["stock_pid"] = child.pid
    write_json(marker, journal)
    try:
        stdout, stderr = child.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=5)
        raise
    assert len(stdout) <= 65_536 and len(stderr) <= 65_536, "Owned stock output bound"
    assert immutable_inputs(root) == before
    journal.update(status="finished", exit_code=child.returncode,
                   stdout=stdout.decode(), stderr=stderr.decode(), inputs_unchanged=True)
    write_json(marker, journal)
    sys.stdout.buffer.write(stdout)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(stderr)
    sys.stderr.buffer.flush()
    return child.returncode


def namespace_proof(parent):
    child = os.readlink("/proc/self/ns/net")
    assert child != parent, "BLOCKED_ENV: namespace unchanged"
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes.extend(json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5)))
    assert [link["ifname"] for link in links] == ["lo"]
    assert all(row.get("dev") == "lo" and row.get("dst") != "default" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    return {"parent": parent, "child": child, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


def inside(args):
    # Import the unchanged supported model fixture only in controller mode.
    sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "scripts" / "codex"))
    from model_fixture import ModelFixture

    root = args.root.resolve(strict=True)
    proof = namespace_proof(args.parent_netns)
    for directory in ["home", "codex", "workspace", "workspace/owned-dir", "tmp", "bin", "commands"]:
        (root / directory).mkdir(exist_ok=True)
    for name, body in INPUTS.items():
        path = root / "workspace" / name
        with path.open("xb") as target:
            target.write(body)
        path.chmod(0o400)
    stock = {}
    for name in ["cat", "ls", "rg"]:
        resolved = shutil.which(name)
        assert resolved, "BLOCKED_ENV: stock " + name + " required"
        # Preserve the invocation basename: stock multicall tools may dispatch
        # cat/ls from argv[0], even when their symlink targets share one binary.
        path = Path(resolved).absolute()
        assert path.is_file() and not path.resolve(strict=True).is_relative_to(root)
        stock[name] = {"path": str(path), "sha256": sha(path.read_bytes())}
    shutil.copyfile("/bin/sh", root / "bin/sh")
    (root / "bin/sh").chmod(0o700)
    for scenario, (name, _argv) in SPECS.items():
        launcher = root / "bin" / name
        launcher.write_text(
            "#!" + sys.executable + "\nimport runpy,sys\n"
            + "sys.argv = [" + repr(str(Path(__file__).resolve()))
            + ", '--command-mode', '--root', " + repr(str(root))
            + ", '--scenario', " + repr(scenario) + ", '--', *sys.argv[1:]]\n"
            + "runpy.run_path(sys.argv[0], run_name='__main__')\n"
        )
        launcher.chmod(0o700)
    account_shell = pwd.getpwuid(os.getuid()).pw_shell
    expected_shell = (account_shell if Path(account_shell).stem == "sh" and Path(account_shell).is_file()
                      else str(root / "bin/sh"))
    state = {"namespace": proof, "scenario": args.scenario, "stock": stock,
             "inputs": immutable_inputs(root), "expected_shell": expected_shell,
             "controller_pid": os.getpid(), "namespace_owner_pid": os.getppid(),
             "native_pids": [], "generation": 0, "ready": False, "events": []}
    write_json(root / "state.json", state)

    class Provider(ModelFixture):
        def __init__(self):
            super().__init__(args.scenario, root / "workspace", root / "requests.json")
            write_json(self.requests_file, [])
            self.audit_lock = threading.Lock()
            self.audit = {"unexpected_http": [], "errors": []}
            write_json(root / "provider-audit.json", self.audit)
            fixture = self
            base_handler = self.server.RequestHandlerClass

            class Handler(base_handler):
                def do_GET(self):
                    fixture.unexpected("GET", self.path)
                    super().do_GET()

                def do_POST(self):
                    size = int(self.headers.get("Content-Length", "0"))
                    if self.path != "/v1/responses" or not 0 < size <= 4_194_304:
                        fixture.unexpected("POST", self.path)
                    super().do_POST()

                def do_DELETE(self):
                    fixture.unexpected("DELETE", self.path)
                    self.send_response(405)
                    self.end_headers()

            self.server.RequestHandlerClass = Handler

        def unexpected(self, method, path):
            with self.audit_lock:
                assert len(self.audit["unexpected_http"]) < 16
                self.audit["unexpected_http"].append({"method": method, "path": path})
                write_json(root / "provider-audit.json", self.audit)

        def write_response(self, handler, index, request):
            try:
                super().write_response(handler, index, request)
            except Exception as error:
                with self.audit_lock:
                    self.audit["errors"].append({"type": type(error).__name__, "message": str(error)})
                    write_json(root / "provider-audit.json", self.audit)
                handler.send_response(500)
                handler.end_headers()

        def response_item(self, index, request):
            assert request["model"] == "mock-model"
            assert index in (1, 2), "Unexpected extra provider request"
            assert any(part.get("text") == "OWNED_COMMAND_ACTION_" + args.scenario.upper() + "_V119"
                       for item in request["input"] if item.get("role") == "user"
                       for part in item.get("content", []))
            outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
            if index == 1:
                assert outputs == []
                name, argv = SPECS[args.scenario]
                return {"type": "function_call", "name": "exec_command",
                        "call_id": "owned-command-action-" + args.scenario + "-v119",
                        "arguments": json.dumps({
                            "cmd": " ".join([name, *argv]), "workdir": self.workspace,
                            "shell": str(root / "bin/sh"), "login": False, "tty": False,
                            "sandbox_permissions": "require_escalated",
                            "justification": "Owned command action " + args.scenario + " only",
                        })}
            assert len(outputs) == 1
            assert outputs[0]["call_id"] == "owned-command-action-" + args.scenario + "-v119"
            assert "Process exited with code 0" in outputs[0]["output"]
            return {"type": "message", "role": "assistant", "id": "owned-command-action-final-v119",
                    "content": [{"type": "output_text", "text": "Owned command action complete"}]}

    provider = Provider().start()
    provider.config(root / "codex")
    catalog = root / "codex/models.json"
    write_json(catalog, {"models": [{
        "slug": "mock-model", "display_name": "Owned command action fixture",
        "supported_reasoning_levels": [], "shell_type": "unified_exec",
        "visibility": "list", "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Owned local command action qualification only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
        "experimental_supported_tools": [],
    }]})
    config = root / "codex/config.toml"
    config.write_text(
        "model_catalog_json = " + json.dumps(str(catalog)) + "\n"
        + 'cli_auth_credentials_store = "ephemeral"\ncheck_for_update_on_startup = false\n'
        + 'allow_login_shell = false\nanalytics.enabled = false\n' + config.read_text()
        + '\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n'
        + 'remote_plugin = false\nshell_snapshot = false\n'
        + '[shell_environment_policy]\ninherit = "all"\n'
    )
    native = None

    def persist(event):
        state["events"].append(event)
        assert len(state["events"]) <= 32
        write_json(root / "state.json", state)

    def stop_native():
        nonlocal native
        state["ready"] = False
        if native is not None:
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
            persist("native_stopped")
            native = None

    def start_native():
        nonlocal native
        socket = root / "native.sock"
        socket.unlink(missing_ok=True)
        environment = {
            "HOME": str(root / "home"), "CODEX_HOME": str(root / "codex"),
            "TMPDIR": str(root / "tmp"), "SHELL": str(root / "bin/sh"),
            "PATH": str(root / "bin") + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
            "LC_ALL": "C", "LANG": "C", "NO_COLOR": "1", "RUST_LOG": "off",
            "PYTHONDONTWRITEBYTECODE": "1", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
            "NO_PROXY": "*", "no_proxy": "*",
        }
        with (root / "native-stderr.log").open("a") as stderr:
            native = subprocess.Popen(
                [str(args.codex), "-c", "features.plugins=false", "-c",
                 "features.recommended_plugins=false", "app-server", "--listen", "unix://" + str(socket)],
                cwd=root / "workspace", env=environment, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=stderr)
        state["native_pids"].append(native.pid)
        state["generation"] += 1
        deadline = time.monotonic() + 5
        while not socket.exists():
            assert native.poll() is None, "Owned native startup exited"
            assert time.monotonic() < deadline, "Owned native startup deadline"
            time.sleep(0.01)
        state["ready"] = True
        persist("native_started")

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    close_id = None
    try:
        start_native()
        while True:
            line = sys.stdin.buffer.readline(16_385)
            if not line:
                break
            assert len(line) <= 16_384 and line.endswith(b"\n")
            message = json.loads(line)
            assert set(message) == {"id", "op"}
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            if message["op"] == "restart":
                stop_native()
                start_native()
            elif message["op"] == "barrier":
                pass
            elif message["op"] == "close":
                close_id = message["id"]
                break
            else:
                raise AssertionError("Forbidden owned controller operation")
            state["last_control_id"] = message["id"]
            persist("control_done")
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        stop_native()
        provider.close()
        assert not provider.thread.is_alive(), "Owned provider did not stop"
        persist("fixture_closed")
        if close_id is not None:
            state["last_control_id"] = close_id
            persist("control_done")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=sorted(SPECS))
    parser.add_argument("--codex", type=Path)
    parser.add_argument("--command-mode", action="store_true")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("command_args", nargs="*")
    args = parser.parse_args()
    if args.command_mode:
        assert args.codex is None and not args.inside
        return command_probe(args)
    assert args.codex is not None and not args.command_args
    args.codex = args.codex.resolve(strict=True)
    assert sha(args.codex.read_bytes()) == NATIVE_SHA
    if not args.inside:
        assert sys.platform == "linux" and shutil.which("unshare") and shutil.which("ip")
        os.execvp("unshare", [
            "unshare", "--user", "--map-root-user", "--net", "--fork", "--kill-child=TERM",
            sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net"),
        ])
    inside(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
