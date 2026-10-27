#!/usr/bin/env python3
"""One held Responses request and one owned ordinary Interrupt command.

Stock Codex owns every app-server message. This peer never completes a model
response or emits a tool call. Hook input is reduced to functional identifiers
before an exclusive invocation record is written.
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


MARKER = "OWNED_V428_INTERRUPT_ROOT"
HOOK_MARKER = "Owned ordinary Interrupt λ🙂"
MAX_REQUEST_BYTES = 1_048_576
MAX_JOURNAL_BYTES = 2_097_152
MAX_HOOK_BYTES = 65_536


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False).encode()
    assert len(encoded) <= MAX_JOURNAL_BYTES, "Owned provider journal limit"
    temporary = path.with_suffix(".partial")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def hook(root):
    body = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    assert 0 < len(body) <= MAX_HOOK_BYTES, "Owned hook input limit"
    received = json.loads(body)
    # Never retain full hook stdin or copy nonfunctional metadata into evidence.
    record = {key: received[key] for key in
              ("hook_event_name", "session_id", "turn_id", "cwd")}
    assert record["hook_event_name"] == "Interrupt"
    assert record["cwd"] == str(root / "workspace")
    assert all(isinstance(record[key], str) and record[key]
               for key in ("session_id", "turn_id"))
    record.update(pid=os.getpid(), marker=HOOK_MARKER)
    encoded = json.dumps(record, ensure_ascii=False).encode()
    assert len(encoded) <= 4096, "Owned hook record limit"
    with (root / "hook-invocation.json").open("xb") as output:
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
            assert len(body) == size, "Incomplete owned provider request"
            fixture.hold(json.loads(body), size)
        except Exception as failure:
            with fixture.lock:
                fixture.state["errors"].append(type(failure).__name__)
                fixture.save()


class InterruptProvider:
    def __init__(self, root):
        self.root = root
        self.lock = threading.Lock()
        self.release = threading.Event()
        self.requests = []
        self.state = {"requests": 0, "thread_id": None, "turn_id": None,
                      "held": False, "released": False, "finished_handlers": 0,
                      "response_events": [], "errors": []}
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

    def hold(self, request, size):
        markers = [part.get("text") for item in request["input"]
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text" and part.get("text") == MARKER]
        assert markers == [MARKER] and request["model"] == "mock-model"
        metadata = json.loads(request["client_metadata"]["x-codex-turn-metadata"])
        assert all(isinstance(metadata.get(key), str) and metadata[key]
                   for key in ("thread_id", "turn_id"))
        # Only functional evidence enters the journal, never headers/full input.
        record = {"marker": MARKER, "model": "mock-model", "bytes": size,
                  "thread_id": metadata["thread_id"], "turn_id": metadata["turn_id"]}
        with self.lock:
            assert self.state["requests"] == 0, "Extra owned inference"
            self.requests.append(record)
            write_json(self.root / "requests.json", self.requests)
            self.state.update(requests=1, thread_id=record["thread_id"],
                              turn_id=record["turn_id"], held=True)
            self.save()
        # No HTTP headers, model item, completion or app-server frame is emitted.
        # Native cancellation is observed independently before the caller releases
        # this finite handler. close() also releases before joining request threads.
        assert self.release.wait(20), "Owned held request deadline"
        with self.lock:
            self.state["finished_handlers"] += 1
            self.save()

    def release_request(self):
        with self.lock:
            self.state["released"] = True
            self.save()
        self.release.set()

    def close(self):
        self.release_request()
        if self.thread.is_alive():
            self.server.shutdown()
        self.server.server_close()
        if self.thread.ident is not None:
            self.thread.join(timeout=5)
        assert not self.thread.is_alive(), "Owned provider thread did not stop"

    def configure(self):
        codex_home = self.root / "codex"
        catalog = codex_home / "models.json"
        write_json(catalog, {"models": [{
            "slug": "mock-model", "display_name": "Owned Interrupt fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec",
            "visibility": "list", "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "Owned Interrupt fixture instructions."},
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]})
        command = shlex.join([sys.executable, str(Path(__file__).resolve()),
                              "--root", str(self.root), "--hook"])
        (codex_home / "config.toml").write_text(f'''model = "mock-model"
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
name = "Owned Interrupt provider"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[[hooks.Interrupt]]
[[hooks.Interrupt.hooks]]
type = "command"
command = {json.dumps(command)}
timeout = 1
async = false
statusMessage = {json.dumps(HOOK_MARKER, ensure_ascii=False)}
''')
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
    fixture = InterruptProvider(root)
    signal.signal(signal.SIGTERM, terminate)
    try:
        fixture.configure()
        fixture.thread.start()
        print(json.dumps({"url": fixture.url, "pid": os.getpid()}), flush=True)
        command = sys.stdin.buffer.readline(1025)
        assert command in (b"", b"release\n"), "Unexpected owned provider control"
        fixture.release_request()
    finally:
        # Release BEFORE server_close joins non-daemon request handlers, including
        # failure teardown and SIGTERM from the standard stdio owner.
        fixture.close()


if __name__ == "__main__":
    main()
