#!/usr/bin/env python3
"""Finite Responses peer, ordinary MCP observer and one owned printf command.

Stock pinned Codex produces every app-server event. The peer supplies three
responses; hooks independently observe native stdin and the actual command effect.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shlex
import signal
import sys
import threading
import traceback

from model_fixture import response_events


SEED = "OWNED_V501_TOOL_TURN"
FOLLOWUP = "OWNED_V501_TOOL_FOLLOWUP"
CALL_ID = "owned-v501-exec-call"
EFFECT = "Owned finite printf λ🙂\n"
HOOK_MARKER = "Owned ordinary tool hook λ🙂"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 65_536
MAX_HOOK_BYTES = 65_536


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned MCP hook journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def invocation(root, event):
    path = root / f"{event}-invocation.json"
    encoded = path.read_bytes()
    assert 0 < len(encoded) <= 4096, "Owned MCP hook invocation record limit"
    return json.loads(encoded)


def command_plan(root):
    return "exec " + shlex.join([sys.executable, str(Path(__file__).resolve()),
                                 "--root", str(root), "--command"])


def command(root):
    pre = invocation(root, "PreToolUse")
    assert not (root / "PostToolUse-invocation.json").exists()
    assert not (root / "command-process.json").exists()
    assert not (root / "printf-effect.txt").exists()
    assert os.getcwd() == str(root / "workspace")
    record = {"pid": os.getpid(), "cwd": os.getcwd(), "tool_use_id": CALL_ID,
              "pre_pid": pre["pid"], "marker": EFFECT}
    encoded = json.dumps(record, ensure_ascii=False).encode()
    assert len(encoded) <= 4096
    with (root / "command-process.json").open("xb") as output:
        output.write(encoded)
    # This is the actual native command process, replacing itself with sh.
    # Only shell printf creates the effect file and stdout observed below.
    script = ("printf %s " + shlex.quote(EFFECT) + " > " +
              shlex.quote(str(root / "printf-effect.txt")) +
              " && printf %s " + shlex.quote(EFFECT))
    os.execv("/bin/sh", ["/bin/sh", "-c", script])


def observe(root, event, received):
    # Only ordinary functional fields are retained or compared. No policy,
    # permission, decision, credential or trust fields are examined.
    record = {key: received[key] for key in
              ("hook_event_name", "session_id", "turn_id", "cwd", "model",
               "tool_name", "tool_input", "tool_use_id")}
    assert record["hook_event_name"] == event
    assert record["cwd"] == str(root / "workspace") and record["model"] == "mock-model"
    assert record["tool_name"] == "Bash" and record["tool_use_id"] == CALL_ID
    assert record["tool_input"] == {"command": command_plan(root)}
    assert all(isinstance(record[key], str) and record[key]
               for key in ("session_id", "turn_id"))
    if event == "PreToolUse":
        assert not (root / "PostToolUse-invocation.json").exists()
        assert not (root / "command-process.json").exists()
        assert not (root / "printf-effect.txt").exists()
    else:
        pre = invocation(root, "PreToolUse")
        process = json.loads((root / "command-process.json").read_bytes())
        assert process["pre_pid"] == pre["pid"]
        assert process["cwd"] == record["cwd"] and process["tool_use_id"] == CALL_ID
        assert pre["session_id"] == record["session_id"] and pre["turn_id"] == record["turn_id"]
        assert (root / "printf-effect.txt").read_bytes() == EFFECT.encode()
        assert received["tool_response"] == EFFECT
        record["tool_response"] = received["tool_response"]
    record.update(pid=os.getpid(), marker=HOOK_MARKER)
    encoded = json.dumps(record, ensure_ascii=False).encode()
    assert len(encoded) <= 4096, "Owned MCP hook record limit"
    with (root / f"{event}-invocation.json").open("xb") as output:
        output.write(encoded)


def pre_hook(root):
    body = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    assert 0 < len(body) <= MAX_HOOK_BYTES, "Owned MCP hook input limit"
    observe(root, "PreToolUse", json.loads(body))
    print("{}", flush=True)


class McpObserver:
    """The only tool observes the already completed owned command; no app-server output."""
    def __init__(self, root):
        self.root = root
        self.journal = root / "mcp-journal.jsonl"
        self.initialized = False
        self.notified = False
        self.called = False
        self.ids = set()
        self.record({"event": "started"})

    def record(self, row):
        row = {**row, "pid": os.getpid()}
        encoded = (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        assert len(encoded) <= 16384, "Owned MCP observer journal row bound"
        with self.journal.open("rb") as source:
            previous = source.read(131073)
        assert len(previous) + len(encoded) <= 131072, "Owned MCP observer journal byte bound"
        assert previous.count(b"\n") < 64, "Owned MCP observer journal count bound"
        temporary = self.journal.with_suffix(".partial")
        assert temporary.write_bytes(previous + encoded) == len(previous) + len(encoded)
        temporary.replace(self.journal)

    def handle(self, line):
        request = json.loads(line)
        assert isinstance(request, dict) and request.get("jsonrpc") == "2.0"
        method = request.get("method")
        self.record({"event": "request", "encoded": line.decode(), "request": request})
        if method == "notifications/initialized":
            assert "id" not in request and self.initialized and not self.notified
            self.notified = True
            return
        native_id = request.get("id")
        assert type(native_id) in (int, str) and native_id not in self.ids
        self.ids.add(native_id)
        params = request.get("params", {})
        assert isinstance(params, dict)
        if method == "initialize":
            assert not self.initialized and params["protocolVersion"] == "2025-06-18"
            self.initialized = True
            result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                      "serverInfo": {"name": "owned-mcp-post-observer", "version": "1.0.0"}}
        else:
            assert self.initialized and self.notified, "Owned MCP observer startup order"
            if method == "tools/list":
                assert params.get("cursor") is None
                result = {"tools": [{"name": "observe_post",
                          "description": "Observe the finite owned command result only",
                          "inputSchema": {"type": "object", "properties": {}},
                          "annotations": {"readOnlyHint": True, "destructiveHint": False}}]}
            elif method == "resources/list":
                result = {"resources": []}
            elif method == "resources/templates/list":
                result = {"resourceTemplates": []}
            else:
                assert method == "tools/call" and not self.called
                assert params["name"] == "observe_post"
                arguments = params["arguments"]
                expected_keys = {"hook_event_name", "session_id", "turn_id", "cwd", "model",
                                 "tool_name", "tool_input", "tool_use_id", "tool_response"}
                assert isinstance(arguments, dict) and set(arguments) == expected_keys
                assert params["_meta"]["threadId"] == arguments["session_id"]
                self.called = True
                observe(self.root, "PostToolUse", arguments)
                self.record({"event": "observed", "arguments": arguments,
                             "effect": (self.root / "printf-effect.txt").read_text()})
                # CoreHookMcpExecutor joins text content; {} is the inert hook contract.
                result = {"content": [{"type": "text", "text": "{}"}], "isError": False}
        reply = {"jsonrpc": "2.0", "id": native_id, "result": result}
        encoded = (json.dumps(reply, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
        assert len(encoded) <= MAX_HOOK_BYTES, "Owned MCP observer reply frame bound"
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()
        self.record({"event": "reply", "method": method,
                     "encoded": encoded.decode(), "reply": reply})

    def run(self):
        while True:
            line = sys.stdin.buffer.readline(MAX_HOOK_BYTES + 1)
            if not line:
                self.record({"event": "eof"})
                return
            assert len(line) <= MAX_HOOK_BYTES and line.endswith(b"\n"), "Owned MCP frame bound"
            self.handle(line)


def mcp_observer(root):
    observer = McpObserver(root)
    try:
        observer.run()
    except (AssertionError, ValueError, TypeError, KeyError, OSError) as failure:
        observer.record({"event": "fatal", "reason": type(failure).__name__})
        raise SystemExit(2) from failure


class ProviderHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.send_error(404)

    def do_POST(self):
        fixture = self.server.fixture
        try:
            self.connection.settimeout(2)
            size = int(self.headers.get("Content-Length", "0"))
            assert self.path == "/v1/responses" and 0 < size <= MAX_REQUEST_BYTES
            body = self.rfile.read(size)
            assert len(body) == size, "Incomplete owned MCP hook provider request"
            fixture.respond(self, json.loads(body), size)
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append({
                    "type": type(failure).__name__,
                    "lines": [frame.lineno for frame in traceback.extract_tb(failure.__traceback__)
                              if frame.filename == __file__],
                })
                fixture.save()
            self.send_error(500, "Owned MCP hook fixture failure")


class ToolProvider:
    def __init__(self, root):
        self.root = root
        self.lock = threading.Lock()
        self.requests = []
        self.state = {"requests": 0, "finished_handlers": 0, "errors": [], "closed": False}
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), ProviderHandler)
        self.server.fixture = self
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        write_json(root / "requests.json", [])
        self.save()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def save(self):
        write_json(self.root / "provider-state.json", self.state)

    def respond(self, handler, request, size):
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert all(isinstance(metadata.get(key), str) and metadata[key]
                   for key in ("thread_id", "turn_id"))
        assert request["model"] == "mock-model"
        inputs = request.get("input", [])
        assert isinstance(inputs, list)
        markers = [part.get("text") for item in inputs if item.get("role") == "user"
                   for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") in (SEED, FOLLOWUP)]
        outputs = [item for item in inputs if item.get("type") == "function_call_output"]
        with self.lock:
            index = self.state["requests"] + 1
            assert index <= 3, "Extra owned MCP hook inference"
            kind = ("tool", "answer", "followup")[index - 1]
            pre_exists = (self.root / "PreToolUse-invocation.json").exists()
            post_exists = (self.root / "PostToolUse-invocation.json").exists()
            if index == 1:
                assert markers == [SEED] and outputs == []
                assert not pre_exists and not post_exists
                assert not (self.root / "command-process.json").exists()
                assert not (self.root / "printf-effect.txt").exists()
                tool_names = [tool.get("name") for tool in request["tools"]]
                # Native Responses tool serialization supports namespaces.
                tool_names += [member.get("name") for tool in request["tools"]
                               for member in tool.get("tools", [])]
                assert "exec_command" in tool_names
            else:
                assert markers == ([SEED] if index == 2 else [SEED, FOLLOWUP])
                assert pre_exists and post_exists
                pre = invocation(self.root, "PreToolUse")
                post = invocation(self.root, "PostToolUse")
                assert pre["session_id"] == post["session_id"] == metadata["thread_id"]
                assert pre["turn_id"] == post["turn_id"]
                assert (pre["turn_id"] == metadata["turn_id"]) == (index == 2)
                assert len(outputs) == 1 and outputs[0]["call_id"] == CALL_ID
                output = outputs[0]["output"]
                assert isinstance(output, str) and output.endswith("Output:\n" + EFFECT)
                assert "Process exited with code 0" in output.splitlines()
                assert (self.root / "printf-effect.txt").read_bytes() == EFFECT.encode()
            record = {"index": index, "kind": kind, "model": request["model"], "bytes": size,
                      "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"],
                      "markers": markers, "output_call_ids": [item["call_id"] for item in outputs],
                      "pre_present": pre_exists, "post_present": post_exists}
            self.requests.append(record)
            self.state["requests"] = index
            write_json(self.root / "requests.json", self.requests)
            self.save()
        item = ({"type": "function_call", "name": "exec_command", "call_id": CALL_ID,
                 "arguments": json.dumps({"cmd": command_plan(self.root),
                     "workdir": str(self.root / "workspace"), "shell": "/bin/sh",
                     "login": False, "tty": False, "yield_time_ms": 10000,
                     "max_output_tokens": 512})} if index == 1 else
                {"type": "message", "role": "assistant", "id": f"fixture-message-{index}",
                 "content": [{"type": "output_text", "text": f"Owned MCP hook answer {index}"}]})
        events = response_events(index, item)
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        handler.wfile.flush()
        with self.lock:
            self.state["finished_handlers"] += 1
            self.save()

    def close(self):
        if self.thread.is_alive():
            self.server.shutdown()
        self.server.server_close()
        if self.thread.ident is not None:
            self.thread.join(timeout=5)
        assert not self.thread.is_alive(), "Owned MCP hook provider thread did not stop"
        with self.lock:
            self.state["closed"] = True
            self.save()

    def configure(self):
        codex_home = self.root / "codex"
        catalog = codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned MCP hook fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned MCP hook fixture instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        command = shlex.join([sys.executable, str(Path(__file__).resolve()),
                              "--root", str(self.root), "--pre-hook"])
        peer_args = ["-B", str(Path(__file__).resolve()), "--root", str(self.root), "--mcp"]
        config = f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
check_for_update_on_startup = false
allow_login_shell = false
web_search = "disabled"
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[memories]
generate_memories = false
use_memories = false
[features]
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = true
concurrent_reasoning_summaries = false
shell_tool = true
unified_exec = true
stable_environment_tools = true
mcp_2026_07_28 = false
[model_providers.fixture]
name = "Owned MCP hook provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        template = {key: "${" + key + "}" for key in
                    ("hook_event_name", "session_id", "turn_id", "cwd", "model",
                     "tool_name", "tool_input", "tool_use_id", "tool_response")}
        input_toml = ", ".join(key + " = " + json.dumps(value) for key, value in template.items())
        config += f'''[mcp_servers.owned_hook]
command = {json.dumps(sys.executable)}
args = {json.dumps(peer_args)}
startup_timeout_sec = 5
tool_timeout_sec = 1
[[hooks.PreToolUse]]
matcher = "Bash"
[[hooks.PreToolUse.hooks]]
type = "command"
command = {json.dumps(command)}
timeout = 1
async = false
statusMessage = {json.dumps(HOOK_MARKER, ensure_ascii=False)}
[[hooks.PostToolUse]]
matcher = "Bash"
[[hooks.PostToolUse.hooks]]
type = "mcp_tool"
server = "owned_hook"
tool = "observe_post"
input = {{ {input_toml} }}
timeout = 1
statusMessage = {json.dumps(HOOK_MARKER, ensure_ascii=False)}
'''
        commands = {"PreToolUse": command,
                    "PostToolUse": {"server": "owned_hook", "tool": "observe_post", "input": template}}
        (self.root / "mcp-journal.jsonl").write_bytes(b"")
        (codex_home / "config.toml").write_text(config)
        write_json(self.root / "hook-definition.json", commands)
        write_json(self.root / "command-definition.json", {"command": command_plan(self.root)})


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--pre-hook", action="store_true")
    parser.add_argument("--mcp", action="store_true")
    parser.add_argument("--command", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.command:
        command(root)
        return
    if args.pre_hook:
        pre_hook(root)
        return
    if args.mcp:
        mcp_observer(root)
        return
    fixture = ToolProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.configure()
        fixture.thread.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        control = sys.stdin.buffer.readline(1025)
        assert control in (b"", b"stop\n"), "Unexpected owned MCP hook provider control"
    finally:
        # The stdio owner may send SIGTERM while this bounded shutdown is
        # already joining handlers. Finish the one cleanup path before exit.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        fixture.close()


if __name__ == "__main__":
    main()
