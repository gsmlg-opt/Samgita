#!/usr/bin/env python3
"""Finite local Responses peer and one inert root SessionEnd command.

Stock pinned Codex produces every app-server event. This peer only supplies
three ordinary model responses and journals bounded functional facts from their requests.
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


FIRST = "OWNED_V494_RETAINED_FIRST"
SECOND = "OWNED_V494_REVERTED_SECOND"
FOLLOWUP = "OWNED_V494_AFTER_REVERT"
HOOK_MARKER = "Owned ordinary SessionEnd λ🙂"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 65_536
MAX_HOOK_BYTES = 65_536


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned SessionEnd journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def invocation(root, ordinal):
    path = root / f"SessionEnd-invocation-{ordinal}.json"
    encoded = path.read_bytes()
    assert 0 < len(encoded) <= 4096, "Owned SessionEnd invocation record limit"
    return json.loads(encoded)


def hook(root):
    body = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    assert 0 < len(body) <= MAX_HOOK_BYTES, "Owned SessionEnd hook input limit"
    received = json.loads(body)
    record = {key: received[key] for key in
              ("hook_event_name", "session_id", "cwd", "reason")}
    assert record["hook_event_name"] == "SessionEnd"
    assert record["cwd"] == str(root / "workspace") and record["reason"] == "other"
    assert isinstance(record["session_id"], str) and record["session_id"]
    # Native SessionEnd input has no turn_id. Keep this actual contract rather
    # than inventing a correlation field from the later wire notifications.
    assert "turn_id" not in received
    record.update(pid=os.getpid(), marker=HOOK_MARKER)
    for ordinal in range(3):
        record["ordinal"] = ordinal
        encoded = json.dumps(record, ensure_ascii=False).encode()
        assert len(encoded) <= 4096, "Owned SessionEnd hook record limit"
        try:
            with (root / f"SessionEnd-invocation-{ordinal}.json").open("xb") as output:
                output.write(encoded)
            break
        except FileExistsError:
            continue
    else:
        raise AssertionError("Owned SessionEnd invocation storage exhausted")
    # A third call is preserved as evidence and fails, never silently discarded.
    assert ordinal < 2, "Extra owned SessionEnd invocation"
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
            assert len(body) == size, "Incomplete owned session end provider request"
            fixture.respond(self, json.loads(body), size)
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append(type(failure).__name__)
                fixture.save()
            self.send_error(500, "Owned SessionEnd fixture failure")


class SessionEndProvider:
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
                   if part.get("type") == "input_text" and part.get("text") in
                   (FIRST, SECOND, FOLLOWUP)]
        with self.lock:
            index = self.state["requests"] + 1
            assert index <= 3, "Extra owned SessionEnd inference"
            expected = ([FIRST], [FIRST, SECOND], [FIRST, FOLLOWUP])[index - 1]
            assert markers == expected
            paths = sorted(self.root.glob("SessionEnd-invocation-*.json"))
            if index < 3:
                assert paths == []
            else:
                assert paths == [self.root / "SessionEnd-invocation-0.json"]
                assert invocation(self.root, 0)["session_id"] == metadata["thread_id"]
            record = {"index": index, "model": request["model"], "bytes": size,
                      "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"],
                      "markers": markers, "hook_invocations": len(paths)}
            self.requests.append(record)
            self.state["requests"] = index
            write_json(self.root / "requests.json", self.requests)
            self.save()
        item = {"type": "message", "role": "assistant", "id": f"fixture-message-{index}",
                "content": [{"type": "output_text", "text": f"Owned SessionEnd answer {index}"}]}
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
        assert not self.thread.is_alive(), "Owned SessionEnd provider thread did not stop"
        with self.lock:
            self.state["closed"] = True
            self.save()

    def configure(self):
        codex_home = self.root / "codex"
        catalog = codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned SessionEnd fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned SessionEnd fixture instructions."},
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
name = "Owned SessionEnd provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        config += f'''[[hooks.SessionEnd]]
matcher = "other"
[[hooks.SessionEnd.hooks]]
type = "command"
command = {json.dumps(command)}
timeout = 1
async = false
statusMessage = {json.dumps(HOOK_MARKER, ensure_ascii=False)}
'''
        (codex_home / "config.toml").write_text(config)
        write_json(self.root / "hook-definition.json", {"command": command})


def terminate(_signal, _frame):
    raise SystemExit(0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--hook", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if args.hook:
        hook(root)
        return
    fixture = SessionEndProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.configure()
        fixture.thread.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        command = sys.stdin.buffer.readline(1025)
        assert command in (b"", b"stop\n"), "Unexpected owned session end provider control"
    finally:
        # The stdio owner may send SIGTERM while this bounded shutdown is
        # already joining handlers. Finish the one cleanup path before exit.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        fixture.close()


if __name__ == "__main__":
    main()
