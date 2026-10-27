#!/usr/bin/env python3
"""One finite MAv2 child and two inert ordinary child hook commands.

Stock pinned Codex produces every app-server event. This peer only supplies
four finite model responses and journals bounded functional facts from their requests.
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


ROOT = "OWNED_V495_HOOK_ROOT"
CHILD = "OWNED_V495_HOOK_CHILD"
CHILD_PATH = "/root/hook_child"
SPAWN = "owned-v495-spawn-hook-child"
WAIT = "owned-v495-wait-hook-child"
CHILD_ANSWER = "Owned V495 child hook answer"
ROOT_ANSWER = "Owned V495 root hook answer"
NEW_TASK = "Message Type: NEW_TASK\nTask name: /root/hook_child\nSender: /root\nPayload:\n" + CHILD
FINAL_ANSWER = "Message Type: FINAL_ANSWER\nTask name: /root\nSender: /root/hook_child\nPayload:\n" + CHILD_ANSWER
HOOK_MARKER = "Owned ordinary subagent hook λ🙂"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 65_536
MAX_HOOK_BYTES = 65_536


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned subagent hook journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def invocation(root, event):
    encoded = (root / f"{event}-invocation.json").read_bytes()
    assert 0 < len(encoded) <= 4096, "Owned subagent hook invocation limit"
    return json.loads(encoded)


def hook(root, event):
    body = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    assert 0 < len(body) <= MAX_HOOK_BYTES, "Owned subagent hook input limit"
    received = json.loads(body)
    record = {key: received[key] for key in
              ("hook_event_name", "session_id", "turn_id", "cwd", "model", "agent_id", "agent_type")}
    assert record["hook_event_name"] == event and record["cwd"] == str(root / "workspace")
    assert record["model"] == "mock-model" and record["agent_type"] == "default"
    requests_body = (root / "requests.json").read_bytes()
    assert 0 < len(requests_body) <= MAX_JOURNAL_BYTES
    requests = json.loads(requests_body)
    assert 1 <= len(requests) <= 4
    assert requests[0]["kind"] == "root" and requests[0]["step"] == 1
    # Native session identity is shared with the root; agent/thread identity is
    # the actual child. Resolve the root from its preceding real model request.
    assert record["session_id"] == requests[0]["thread_id"]
    assert record["agent_id"] != record["session_id"]
    assert all(isinstance(record[key], str) and record[key]
               for key in ("session_id", "turn_id", "agent_id"))
    if event == "SubagentStop":
        record.update(last_assistant_message=received["last_assistant_message"],
                      stop_hook_active=received["stop_hook_active"])
        assert record["last_assistant_message"] == CHILD_ANSWER and record["stop_hook_active"] is False
    record.update(pid=os.getpid(), marker=HOOK_MARKER)
    encoded = json.dumps(record, ensure_ascii=False).encode()
    assert len(encoded) <= 4096, "Owned subagent hook record limit"
    with (root / f"{event}-invocation.json").open("xb") as output:
        output.write(encoded)
    print("{}", flush=True)


def outputs(request):
    return {item["call_id"]: json.loads(item["output"])
            for item in request.get("input", []) if item.get("type") == "function_call_output"}


def agent_messages(request, author, recipient):
    return [item for item in request.get("input", []) if item.get("type") == "agent_message"
            and item.get("author") == author and item.get("recipient") == recipient]


def final_message(identity, text):
    return {"type": "message", "role": "assistant", "id": identity,
            "content": [{"type": "output_text", "text": text}]}

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
            assert len(body) == size, "Incomplete owned subagent hook provider request"
            fixture.respond(self, json.loads(body), size)
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append({
                    "type": type(failure).__name__,
                    "lines": [frame.lineno for frame in traceback.extract_tb(failure.__traceback__)
                              if frame.filename == __file__],
                })
                fixture.save()
            self.send_error(500, "Owned subagent hook fixture failure")


class SubagentHookProvider:
    def __init__(self, root):
        self.root = root
        self.lock = threading.Lock()
        self.requests = []
        self.release_child = threading.Event()
        self.closing = threading.Event()
        self.state = {"root_requests": 0, "child_requests": 0, "finished_handlers": 0,
                      "child_held": False, "released": False, "errors": [], "closed": False}
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
        assert request["model"] == "mock-model" and request["reasoning"]["effort"] == "medium"
        root = any(part.get("text") == ROOT for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", []))
        values = outputs(request)
        pre = (self.root / "SubagentStart-invocation.json").exists()
        post = (self.root / "SubagentStop-invocation.json").exists()
        with self.lock:
            kind = "root" if root else "child"
            key = f"{kind}_requests"
            self.state[key] += 1
            step = self.state[key]
            assert self.state["root_requests"] <= 3 and self.state["child_requests"] <= 1
            if root:
                if step == 1:
                    assert values == {} and not pre and not post
                    namespaces = [tool for tool in request["tools"] if tool.get("name") == "collaboration"]
                    assert len(namespaces) == 1
                    assert {"spawn_agent", "wait_agent"} <= {tool["name"] for tool in namespaces[0]["tools"]}
                    item = {"type": "function_call", "namespace": "collaboration", "name": "spawn_agent",
                            "call_id": SPAWN, "encrypted_function_args": [],
                            "arguments": json.dumps({"task_name": "hook_child", "message": CHILD,
                                "fork_turns": "none", "model": "mock-model", "reasoning_effort": "medium"})}
                elif step == 2:
                    assert values == {SPAWN: {"task_name": CHILD_PATH}}
                    item = {"type": "function_call", "namespace": "collaboration", "name": "wait_agent",
                            "call_id": WAIT, "arguments": json.dumps({"timeout_ms": 10000})}
                else:
                    assert values == {SPAWN: {"task_name": CHILD_PATH},
                                      WAIT: {"message": "Wait completed.", "timed_out": False}}
                    messages = agent_messages(request, CHILD_PATH, "/root")
                    assert len(messages) == 1 and messages[0]["content"] == [
                        {"type": "input_text", "text": FINAL_ANSWER}]
                    assert pre and post and self.state["child_requests"] == 1
                    item = final_message("owned-v495-root-final", ROOT_ANSWER)
            else:
                messages = agent_messages(request, "/root", CHILD_PATH)
                assert len(messages) == 1 and messages[0]["content"] == [
                    {"type": "input_text", "text": NEW_TASK}]
                assert values == {}
                assert pre
                assert not post
                start = invocation(self.root, "SubagentStart")
                assert start["session_id"] == self.requests[0]["thread_id"]
                assert start["agent_id"] == metadata["thread_id"]
                assert start["session_id"] != start["agent_id"]
                assert start["turn_id"] == metadata["turn_id"]
                self.state["child_held"] = True
                item = final_message("owned-v495-child-final", CHILD_ANSWER)
            index = len(self.requests) + 1
            self.requests.append({"index": index, "kind": kind, "step": step,
                "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"],
                "model": request["model"], "effort": request["reasoning"]["effort"], "bytes": size,
                "pre_present": pre, "post_present": post,
                "tool_outputs": values, "message": NEW_TASK if not root else FINAL_ANSWER if step == 3 else None})
            write_json(self.root / "requests.json", self.requests)
            self.save()
        if not root:
            assert self.release_child.wait(10), "Owned child-response release deadline"
            assert not self.closing.is_set(), "Owned child provider closed before release"
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

    def release(self):
        with self.lock:
            self.state["released"] = True
            self.save()
        self.release_child.set()

    def close(self):
        self.closing.set()
        self.release_child.set()
        if self.thread.is_alive():
            self.server.shutdown()
        self.server.server_close()
        if self.thread.ident is not None:
            self.thread.join(timeout=5)
        assert not self.thread.is_alive(), "Owned subagent hook provider thread did not stop"
        with self.lock:
            self.state["closed"] = True
            self.save()

    def configure(self):
        codex_home = self.root / "codex"
        catalog = codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned subagent hook fixture",
            "supported_reasoning_levels": [{"effort": "medium", "description": "Owned medium"}],
            "default_reasoning_level": "medium", "multi_agent_version": "v2",
            "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned subagent hook fixture instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        command = shlex.join([sys.executable, str(Path(__file__).resolve()),
                              "--root", str(self.root), "--hook"])
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
[agents]
enabled = true
max_depth = 1
max_concurrent_threads_per_session = 2
[features]
multi_agent = true
multi_agent_v2 = true
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
remote_models = false
shell_snapshot = false
memories = false
hooks = true
concurrent_reasoning_summaries = false
[model_providers.fixture]
name = "Owned subagent hook provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        commands = {}
        for event in ("SubagentStart", "SubagentStop"):
            commands[event] = f"{command} {event}"
            config += f'''[[hooks.{event}]]
matcher = "default"
[[hooks.{event}.hooks]]
type = "command"
command = {json.dumps(commands[event])}
timeout = 1
async = false
statusMessage = {json.dumps(HOOK_MARKER, ensure_ascii=False)}
'''
        (codex_home / "config.toml").write_text(config)
        write_json(self.root / "hook-definition.json", commands)


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--hook", choices=["SubagentStart", "SubagentStop"])
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.hook:
        hook(root, args.hook)
        return
    fixture = SubagentHookProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.configure()
        fixture.thread.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        while True:
            command = sys.stdin.buffer.readline(1025)
            if command in (b"", b"stop\n"):
                break
            assert command == b"release\n", "Unexpected owned subagent provider control"
            fixture.release()

    finally:
        # The stdio owner may send SIGTERM while this bounded shutdown is
        # already joining handlers. Finish the one cleanup path before exit.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        fixture.close()


if __name__ == "__main__":
    main()
