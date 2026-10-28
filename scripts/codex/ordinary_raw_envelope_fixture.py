#!/usr/bin/env python3
"""One bounded ordinary Responses SSE reply; never an app-server emulator.

Reuse only the reviewed pure response_events encoder, not ModelFixture startup,
scenario selection, configuration, command branches or lifecycle.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import signal
import sys
import traceback
from urllib.parse import urlparse

sys.dont_write_bytecode = True

from model_fixture import response_events

MAX_BODY = 131_072
MARKER = "Owned ordinary raw envelope λ🙂"
ANSWER = "Owned ordinary raw envelope answer β🙂"
ITEM_ID = "owned-ordinary-raw-item-3234"


def write_json(path, value):
    data = json.dumps(value, ensure_ascii=False).encode()
    assert len(data) <= MAX_BODY, "Owned ordinary file bound"
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_bytes(data)
    pending.replace(path)


class Peer:
    def __init__(self, args):
        self.args = args
        self.root = args.codex_home.parent
        self.journal = self.root / "ordinary-raw-envelope-journal.json"
        self.events = []
        self.requests = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, data, content_type="application/json"):
                assert len(data) <= MAX_BODY, "Owned ordinary response bound"
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True

            def do_POST(self):
                try:
                    parsed = urlparse(self.path)
                    assert parsed.path == "/v1/responses" and parsed.query == ""
                    assert owner.requests == [], "Owned one ordinary provider request"
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= MAX_BODY, "Owned provider body bound"
                    request = json.loads(self.rfile.read(size))
                    assert request["model"] == "mock-model"
                    markers = [part["text"] for item in request.get("input", [])
                        if item.get("role") == "user" for part in item.get("content", [])
                        if isinstance(part, dict) and part.get("type") == "input_text"]
                    assert markers.count(MARKER) == 1, "Owned unique ordinary input"
                    owner.requests.append(request)
                    write_json(args.requests_file, owner.requests)
                    owner.record("provider_request", method="POST", path=parsed.path,
                        query=parsed.query, status=200, sequence=1)
                    item = {"type": "message", "role": "assistant", "id": ITEM_ID,
                        "content": [{"type": "output_text", "text": ANSWER}]}
                    events = response_events(1, item)
                    body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                        for event in events).encode()
                    self.reply(200, body, "text/event-stream")
                except Exception as error:
                    owner.record("fixture_error", kind=type(error).__name__,
                        line=traceback.extract_tb(error.__traceback__)[-1].lineno)
                    self.reply(500, b'{"error":"owned ordinary provider failed"}')

            def unexpected(self):
                parsed = urlparse(self.path)
                owner.record("unexpected_http", method=self.command,
                    path=parsed.path, query=parsed.query)
                self.reply(404, b"{}")

            do_GET = unexpected
            do_PUT = unexpected
            do_PATCH = unexpected
            do_DELETE = unexpected
            do_HEAD = unexpected
            do_OPTIONS = unexpected

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 5
        self.record("fixture_started", pid=os.getpid())

    def record(self, event, **fields):
        assert len(self.events) < 32, "Owned journal event bound"
        self.events.append({"event": event, **fields})
        write_json(self.journal, {"events": self.events})

    def configure(self):
        codex = self.args.codex_home
        catalog = codex / "models.json"
        write_json(catalog, {"models": [{"slug": "mock-model",
            "display_name": "Owned ordinary raw envelope peer", "supported_reasoning_levels": [],
            "shell_type": "unified_exec", "visibility": "list", "supported_in_api": True,
            "priority": 1, "model_messages": {"instructions_template": "Ordinary local text only."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": []}]})
        endpoint = f"http://127.0.0.1:{self.http.server_port}"
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "danger-full-access"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{endpoint}"
openai_base_url = "{endpoint}/v1"
[features]
apps = false
plugins = false
remote_plugin = false
recommended_plugins = false
shell_snapshot = false
memories = false
codex_hooks = false
[memories]
generate_memories = false
use_memories = false
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
[model_providers.fixture]
name = "Owned ordinary raw envelope peer"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
        write_json(self.args.requests_file, [])

    def close(self):
        self.http.server_close()
        self.record("fixture_closed", pid=os.getpid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--requests-file", required=True, type=Path)
    args = parser.parse_args()
    peer = Peer(args)

    def stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        peer.configure()
        print(json.dumps({"pid": os.getpid(),
            "url": f"http://127.0.0.1:{peer.http.server_port}"}), flush=True)
        peer.http.serve_forever(poll_interval=0.1)
    finally:
        peer.close()


if __name__ == "__main__":
    main()
