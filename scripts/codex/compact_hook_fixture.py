#!/usr/bin/env python3
"""Finite local Responses peer and inert synchronous compact commands.

Stock pinned Codex produces every app-server event. This peer only supplies
three model responses and journals bounded functional facts from their requests.
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

from model_fixture import response_events


SEED = "OWNED_V493_BEFORE_COMPACT"
FOLLOWUP = "OWNED_V493_AFTER_COMPACT"
CHECKPOINT = "SYNTHETIC_V493_COMPACT_HOOK_CHECKPOINT"
HOOK_MARKER = "Owned ordinary compact hook λ🙂"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 65_536
MAX_HOOK_BYTES = 65_536


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned compact journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def invocation(root, event):
    path = root / f"{event}-invocation.json"
    encoded = path.read_bytes()
    assert 0 < len(encoded) <= 4096, "Owned compact invocation record limit"
    return json.loads(encoded)


def hook(root, event):
    body = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    assert 0 < len(body) <= MAX_HOOK_BYTES, "Owned compact hook input limit"
    received = json.loads(body)
    record = {key: received[key] for key in
              ("hook_event_name", "session_id", "turn_id", "cwd", "model", "trigger")}
    assert record["hook_event_name"] == event
    assert record["cwd"] == str(root / "workspace")
    assert record["model"] == "mock-model" and record["trigger"] == "manual"
    assert all(isinstance(record[key], str) and record[key]
               for key in ("session_id", "turn_id"))
    record.update(pid=os.getpid(), marker=HOOK_MARKER)
    encoded = json.dumps(record, ensure_ascii=False).encode()
    assert len(encoded) <= 4096, "Owned compact hook record limit"
    with (root / f"{event}-invocation.json").open("xb") as output:
        output.write(encoded)
    print("{}", flush=True)


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
            assert len(body) == size, "Incomplete owned compact provider request"
            fixture.respond(self, json.loads(body), size)
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append(type(failure).__name__)
                fixture.save()
            self.send_error(500, "Owned compact fixture failure")


class CompactProvider:
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
        checkpoints = [item["encrypted_content"] for item in inputs
                       if item.get("type") == "compaction"]
        markers = [part.get("text") for item in inputs if item.get("role") == "user"
                   for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") in (SEED, FOLLOWUP)]
        compact = any(item.get("type") == "compaction_trigger" for item in inputs)
        with self.lock:
            index = self.state["requests"] + 1
            assert index <= 3, "Extra owned compact inference"
            kind = ("seed", "compact", "followup")[index - 1]
            pre_exists = (self.root / "PreCompact-invocation.json").exists()
            post_exists = (self.root / "PostCompact-invocation.json").exists()
            if index == 1:
                assert not compact and markers == [SEED] and checkpoints == []
                assert not pre_exists and not post_exists
            elif index == 2:
                assert compact and markers == [SEED] and checkpoints == []
                assert pre_exists and not post_exists
                pre = invocation(self.root, "PreCompact")
                assert pre["session_id"] == metadata["thread_id"]
                assert pre["turn_id"] == metadata["turn_id"]
            else:
                assert not compact and markers == [SEED, FOLLOWUP] and checkpoints == [CHECKPOINT]
                assert pre_exists and post_exists
                pre = invocation(self.root, "PreCompact")
                post = invocation(self.root, "PostCompact")
                assert pre["session_id"] == post["session_id"] == metadata["thread_id"]
                assert pre["turn_id"] == post["turn_id"] != metadata["turn_id"]
            record = {"index": index, "kind": kind, "model": request["model"], "bytes": size,
                      "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"],
                      "markers": markers, "checkpoints": checkpoints,
                      "pre_present": pre_exists, "post_present": post_exists}
            self.requests.append(record)
            self.state["requests"] = index
            write_json(self.root / "requests.json", self.requests)
            self.save()
        item = ({"type": "compaction", "encrypted_content": CHECKPOINT} if compact else
                {"type": "message", "role": "assistant", "id": f"fixture-message-{index}",
                 "content": [{"type": "output_text", "text": f"Owned compact answer {index}"}]})
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
        assert not self.thread.is_alive(), "Owned compact provider thread did not stop"
        with self.lock:
            self.state["closed"] = True
            self.save()

    def configure(self):
        codex_home = self.root / "codex"
        catalog = codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned compact fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned compact fixture instructions."},
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
[model_providers.fixture]
name = "Owned compact provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[model_providers.fixture.capabilities]
remote_compaction = "v2"
'''
        commands = {}
        for event in ("PreCompact", "PostCompact"):
            commands[event] = f"{command} {event}"
            config += f'''[[hooks.{event}]]
matcher = "manual"
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
    parser.add_argument("--hook", choices=["PreCompact", "PostCompact"])
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.hook:
        hook(root, args.hook)
        return
    fixture = CompactProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.configure()
        fixture.thread.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        command = sys.stdin.buffer.readline(1025)
        assert command in (b"", b"stop\n"), "Unexpected owned compact provider control"
    finally:
        # The stdio owner may send SIGTERM while this bounded shutdown is
        # already joining handlers. Finish the one cleanup path before exit.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        fixture.close()


if __name__ == "__main__":
    main()
