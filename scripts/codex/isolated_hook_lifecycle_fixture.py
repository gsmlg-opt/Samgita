#!/usr/bin/env python3
"""Owned fixed hooks and synthetic Responses peer around unmodified native Codex.

The native child alone writes app-server stdout. No external model or project
hook is used. Explicit read-only restart reuses the original CODEX_HOME and
fixture inputs in a fresh private namespace with a rejection-only peer at the
preserved origin. Codex still opens its store normally; this is not filesystem
read-only mode or a claim of whole-store byte immutability.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import threading
import tomllib
from urllib.parse import urlsplit


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SCENARIOS = ("success", "untrusted", "disabled", "blocked", "failed", "stopped", "warning", "context",
             "stop-continuation")
PROMPT = "Owned synthetic hook lifecycle input"
HOOK_PROGRAM = r'''import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve(strict=True)
event, scenario = sys.argv[2:]
assert event in {"SessionStart", "UserPromptSubmit", "Stop"}
assert scenario in {"success", "untrusted", "disabled", "blocked", "failed", "stopped", "warning", "context",
                    "stop-continuation"}
assert Path.cwd() == root / "workspace"
proof = json.loads((root / "state.json").read_text())
assert os.readlink("/proc/self/ns/net") == proof["child"]
assert os.readlink("/proc/self/ns/user") == proof["child_user"]
raw = sys.stdin.buffer.read(65537)
assert len(raw) <= 65536
data = json.loads(raw)
assert data["hook_event_name"] == event
assert data["cwd"] == str(root / "workspace")
assert data["model"] == "mock-model"
assert isinstance(data["session_id"], str) and data["session_id"]
if event == "SessionStart":
    assert data["source"] == "startup" and "turn_id" not in data
elif event == "UserPromptSubmit":
    assert isinstance(data["turn_id"], str) and data["turn_id"]
    assert data["prompt"] == "Owned synthetic hook lifecycle input"
else:
    assert scenario == "stop-continuation"
    assert set(data) == {"session_id", "turn_id", "transcript_path", "cwd", "hook_event_name",
                         "model", "permission_mode", "stop_hook_active", "last_assistant_message"}
    assert isinstance(data["turn_id"], str) and data["turn_id"]
    assert data["permission_mode"] == "default"
    assert data["transcript_path"] is None or isinstance(data["transcript_path"], str)
    assert type(data["stop_hook_active"]) is bool
    expected = "Owned hook final α🙂" if data["stop_hook_active"] else "Owned hook draft λ🙂"
    assert data["last_assistant_message"] == expected
record = {"event": event, "scenario": scenario, "pid": os.getpid(),
          "session_id": data["session_id"], "turn_id": data.get("turn_id"),
          "namespace": os.readlink("/proc/self/ns/net")}
record_name = event
if event == "Stop":
    record_name = "Stop-second" if data["stop_hook_active"] else "Stop-first"
    record.update({key: data[key] for key in (
        "stop_hook_active", "last_assistant_message", "permission_mode", "transcript_path")})
    if data["stop_hook_active"]:
        assert (root / "Stop-first.json").is_file()
    else:
        assert not (root / "Stop-second.json").exists()
# Exclusive slots reject duplicate invocations, including a third Stop run.
with (root / (record_name + ".json")).open("x") as output:
    json.dump(record, output)
if event == "UserPromptSubmit" and scenario == "blocked":
    print("Owned synthetic hook denied input", file=sys.stderr)
    raise SystemExit(2)
if event == "UserPromptSubmit" and scenario == "failed":
    raise SystemExit(7)
if event == "Stop":
    output = {} if data["stop_hook_active"] else {
        "decision": "block", "reason": "Owned synthetic Stop continuation λ🙂"}
    print(json.dumps(output, ensure_ascii=False))
elif event == "UserPromptSubmit" and scenario == "stopped":
    print(json.dumps({"continue": False, "stopReason": "Owned synthetic hook stopped input"}))
elif event == "UserPromptSubmit" and scenario == "warning":
    print(json.dumps({"systemMessage": "Owned synthetic hook warning"}))
elif event == "UserPromptSubmit" and scenario == "context":
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit", "additionalContext": "Owned synthetic hook context"}}))
else:
    print("{}")
'''


def atomic_json(path, value):
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def isolation(args):
    current = os.readlink("/proc/self/ns/net")
    user = os.readlink("/proc/self/ns/user")
    links = json.loads(subprocess.check_output([args.ip, "-j", "link", "show"], timeout=5))
    routes = json.loads(subprocess.check_output([args.ip, "-j", "route", "show", "table", "all"], timeout=5))
    routes6 = json.loads(subprocess.check_output([args.ip, "-6", "-j", "route", "show", "table", "all"], timeout=5))
    assert current != args.parent_netns and user != args.parent_userns
    assert os.getuid() == 0 and [row["ifname"] for row in links] == ["lo"]
    for row in routes + routes6:
        assert row.get("dst") != "default" and row.get("dev") == "lo"
        assert not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
    return {"parent": args.parent_netns, "child": current,
            "parent_user": args.parent_userns, "child_user": user,
            "interfaces": ["lo"], "default_route": False, "ipv6_default_route": False}


class Provider:
    def __init__(self, root, scenario):
        self.root, self.requests, self.errors = root, [], []
        self.lock = threading.Lock()
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True

            def handle_error(self, _request, _address):
                with fixture.lock:
                    fixture.errors.append(sys.exc_info()[0].__name__)
                    atomic_json(root / "provider-errors.json", fixture.errors)

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def do_GET(self):
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                assert self.path == "/v1/responses" and 0 < size <= 4_194_304
                request = json.loads(self.rfile.read(size))
                assert any(part.get("text") == PROMPT
                           for item in request.get("input", []) if item.get("role") == "user"
                           for part in item.get("content", []) if part.get("type") == "input_text")
                with fixture.lock:
                    fixture.requests.append(request)
                    index = len(fixture.requests)
                    atomic_json(root / "requests.json", fixture.requests)
                if scenario == "stop-continuation":
                    assert index in (1, 2), "Unexpected additional synthetic inference"
                    if index == 1:
                        assert not (root / "Stop-first.json").exists()
                    else:
                        assert (root / "Stop-first.json").is_file()
                        assert not (root / "Stop-second.json").exists()
                    identity = f"owned-hook-response-{index}"
                    item_id = f"owned-hook-answer-{index}"
                    text = ("Owned hook draft λ🙂", "Owned hook final α🙂")[index - 1]
                else:
                    assert index == 1, "Unexpected additional synthetic inference"
                    identity, item_id = "owned-hook-response", "owned-hook-answer"
                    text = "Owned hook fixture answer"
                item = {"type": "message", "role": "assistant", "id": item_id,
                        "content": [{"type": "output_text", "text": text}]}
                events = [
                    {"type": "response.created", "response": {"id": identity}},
                    {"type": "response.output_item.done", "item": item},
                    {"type": "response.completed", "response": {"id": identity, "usage": {
                        "input_tokens": 0, "input_tokens_details": None,
                        "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0}}},
                ]
                body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                               for event in events).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.05), daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"


class ReadOnlyPeer:
    """Journal every accepted connection and reject cold HTTP requests safely."""

    def __init__(self, root):
        config = tomllib.loads((root / "codex/config.toml").read_text())
        origins = [urlsplit(config["model_providers"]["fixture"]["base_url"]),
                   urlsplit(config["openai_base_url"]), urlsplit(config["chatgpt_base_url"])]
        for origin in origins:
            assert origin.scheme == "http" and origin.hostname == "127.0.0.1"
            assert origin.port and not origin.username and not origin.password
            assert not origin.query and not origin.fragment
        assert origins[0].path == origins[1].path == "/v1"
        assert origins[2].path in {"", "/"}
        assert len({origin.port for origin in origins}) == 1
        records, lock = [], threading.Lock()
        journal = root / "cold-provider-attempts.json"
        atomic_json(journal, records)

        class Server(ThreadingHTTPServer):
            daemon_threads = True

            def get_request(self):
                connection, address = super().get_request()
                with lock:
                    records.append({"kind": "connection"})
                    atomic_json(journal, records)
                return connection, address

            def handle_error(self, _request, _address):
                with lock:
                    records.append({"kind": "handler_error"})
                    atomic_json(journal, records)

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reject(self):
                with lock:
                    records.append({"kind": "request"})
                    atomic_json(journal, records)
                self.close_connection = True
                self.send_response(503)
                self.send_header("Content-Length", "0")
                self.send_header("Connection", "close")
                self.end_headers()

            do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = reject

        self.server = Server(("127.0.0.1", origins[0].port), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.05), daemon=True)


def configure(args, provider):
    root = args.root
    hook = root / "owned_hook.py"
    with hook.open("x") as output:
        output.write(HOOK_PROGRAM)
    catalog = root / "codex" / "models.json"
    atomic_json(catalog, {"models": [{
        "slug": "mock-model", "display_name": "Owned synthetic hook model",
        "supported_reasoning_levels": [], "shell_type": "unified_exec",
        "visibility": "list", "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Synthetic hook qualification only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
        "input_modalities": ["text"], "experimental_supported_tools": [],
    }]})
    events = ("Stop",) if args.scenario == "stop-continuation" else ("SessionStart", "UserPromptSubmit")
    commands = {event: "exec " + shlex.join([
        sys.executable, str(hook), str(root), event, args.scenario])
        for event in events}
    config = f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
chatgpt_base_url = "{provider.url}"
openai_base_url = "{provider.url}/v1"
[features]
hooks = true
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned synthetic hook provider"
base_url = "{provider.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
    for event, command in commands.items():
        config += f'\n[[hooks.{event}]]\n'
        if event == "SessionStart":
            config += 'matcher = "^startup$"\n'
        # Native TOML uses "timeout"; public hooks/list metadata uses "timeoutSec".
        config += f'''[[hooks.{event}.hooks]]
type = "command"
command = {json.dumps(command)}
timeout = 5
async = false
statusMessage = "Owned synthetic {event}"
'''
    with (root / "codex" / "config.toml").open("x") as output:
        output.write(config)
    return commands


def run(args):
    args.root = args.root.resolve(strict=True)
    codex = Path(args.codex).resolve(strict=True)
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter fixture"
    assert hashlib.sha256(codex.read_bytes()).hexdigest() == SHA256, "Unpinned native binary"
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux required"
        os.execv(args.unshare, [args.unshare, "--user", "--map-root-user", "--net", "--fork",
                              "--kill-child=TERM", sys.executable, str(Path(__file__).resolve()),
                              *sys.argv[1:], "--inside", "--parent-netns",
                              os.readlink("/proc/self/ns/net"), "--parent-userns",
                              os.readlink("/proc/self/ns/user")])
    subprocess.run([args.ip, "link", "set", "lo", "up"], check=True, timeout=5)
    proof = isolation(args)
    provider = None
    retained = {}
    if args.read_only_restart:
        assert args.scenario == "stop-continuation"
        original = json.loads((args.root / "state.json").read_text())
        assert not Path(f"/proc/{original['native_pid']}").exists()
        assert not Path(f"/proc/{original['controller_pid']}").exists()
        assert not Path(f"/proc/{original['namespace_owner_pid']}").exists()
        assert len(json.loads((args.root / "requests.json").read_text())) == 2
        assert json.loads((args.root / "provider-errors.json").read_text()) == []
        for name in ("state.json", "requests.json", "provider-errors.json", "Stop-first.json",
                     "Stop-second.json", "owned_hook.py", "codex/config.toml", "codex/models.json"):
            retained[name] = hashlib.sha256((args.root / name).read_bytes()).hexdigest()
        for name in ("Stop-first.json", "Stop-second.json"):
            hook = json.loads((args.root / name).read_text())
            assert not Path(f"/proc/{hook['pid']}").exists()
        commands = original["commands"]
        proof_file = "cold-state.json"
        provider = ReadOnlyPeer(args.root)
        provider.thread.start()
    else:
        provider = Provider(args.root, args.scenario)
        commands = configure(args, provider)
        provider.thread.start()
        proof_file = "state.json"
    environment = {key: os.environ[key] for key in (
        "HOME", "CODEX_HOME", "TMPDIR", "NO_COLOR", "RUST_LOG",
        "CODEX_DISABLE_REMOTE_CONTROL", "PYTHONDONTWRITEBYTECODE") if key in os.environ}
    environment.update({"SHELL": str(args.root / "bin" / "sh"),
                        "PATH": str(args.root / "bin") + ":/usr/bin:/bin"})
    native = None

    def terminate(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    try:
        native = subprocess.Popen([str(codex), "app-server", "--listen", "stdio://"],
                                  cwd=args.root / "workspace", env=environment,
                                  stdin=sys.stdin.buffer, stdout=sys.stdout.buffer,
                                  stderr=subprocess.DEVNULL)
        atomic_json(args.root / proof_file, {**proof, "native_pid": native.pid,
                    "controller_pid": os.getpid(), "namespace_owner_pid": os.getppid(),
                    "commands": commands, "ready": True,
                    "read_only_restart": args.read_only_restart,
                    "provider_mode": "reject_all" if args.read_only_restart else "fixed_responses",
                    "retained_sha256": retained})
        return native.wait()
    finally:
        if native is not None and native.poll() is None:
            native.terminate()
            try:
                native.wait(timeout=0.25)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=0.15)
        if provider is not None:
            provider.server.shutdown()
            provider.server.server_close()
            provider.thread.join(timeout=0.1)
        for name, digest in retained.items():
            assert hashlib.sha256((args.root / name).read_bytes()).hexdigest() == digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--ip", required=True)
    parser.add_argument("--unshare", required=True)
    parser.add_argument("--scenario", required=True, choices=SCENARIOS)
    parser.add_argument("--read-only-restart", action="store_true")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    for name in ("ip", "unshare"):
        assert Path(getattr(args, name)).is_absolute()
    raise SystemExit(run(args))


if __name__ == "__main__":
    main()
