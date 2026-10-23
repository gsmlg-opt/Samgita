#!/usr/bin/env python3
"""Loopback-only deterministic Responses backend for the real pinned Codex.

This is a model-provider fixture, not an app-server emulator. Event shapes follow
the pinned upstream core/tests/common/responses.rs helpers. No account, secret,
external network, billing or production workspace is involved.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading


def response_events(index, item):
    identity = f"fixture-response-{index}"
    return [
        {"type": "response.created", "response": {"id": identity}},
        {"type": "response.output_item.done", "item": item},
        {"type": "response.completed", "response": {"id": identity, "usage": {
            "input_tokens": 0, "input_tokens_details": None,
            "output_tokens": 0, "output_tokens_details": None, "total_tokens": 0,
        }}},
    ]


class ModelFixture:
    def __init__(self, scenario="assistant", workspace=None, requests_file=None):
        self.scenario = scenario
        self.workspace = str(Path(workspace).resolve()) if workspace else None
        self.requests = []
        self.requests_file = Path(requests_file) if requests_file else None
        self.lock = threading.Lock()
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                self.send_response(404)
                self.end_headers()

            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                if self.path != "/v1/responses" or not 0 < size <= 4_194_304:
                    self.send_response(400)
                    self.end_headers()
                    return
                request = json.loads(self.rfile.read(size))
                with fixture.lock:
                    fixture.requests.append(request)
                    index = len(fixture.requests)
                    if fixture.requests_file:
                        temporary = fixture.requests_file.with_suffix(".partial")
                        temporary.write_text(json.dumps(fixture.requests))
                        temporary.replace(fixture.requests_file)
                item = fixture.item(index)
                body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                               for event in response_events(index, item)).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def item(self, index):
        if index == 1 and self.scenario != "assistant":
            if self.scenario == "command":
                arguments = {"cmd": "printf samgita_fixture", "workdir": self.workspace,
                             "shell": "/bin/sh", "login": False,
                             "sandbox_permissions": "require_escalated",
                             "justification": "Synthetic fixture approval only"}
                name = "exec_command"
            elif self.scenario == "dynamic_tool":
                name, arguments = "fixture_lookup", {"key": "synthetic"}
            elif self.scenario == "user_input":
                name, arguments = "request_user_input", {"questions": [{
                    "id": "fixture", "header": "Fixture", "question": "Choose fixture input",
                    "options": [{"label": "One", "description": "Fixture one"},
                                {"label": "Two", "description": "Fixture two"}],
                }]}
            else:
                raise ValueError("Unknown local fixture scenario")
            return {"type": "function_call", "name": name, "call_id": "fixture-call-1",
                    "arguments": json.dumps(arguments)}
        return {"type": "message", "role": "assistant", "id": f"fixture-message-{index}",
                "content": [{"type": "output_text", "text": "Deterministic local fixture answer"}]}

    def start(self):
        self.thread.start()
        return self

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def config(self, codex_home):
        # All provider and account destinations point at this loopback fixture.
        body = f'''model = "mock-model"
model_provider = "fixture"
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
[model_providers.fixture]
name = "Local deterministic fixture"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
'''
        Path(codex_home, "config.toml").write_text(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant", "command", "dynamic_tool", "user_input"],
                        default="assistant")
    parser.add_argument("--workspace")
    parser.add_argument("--codex-home")
    parser.add_argument("--requests-file", type=Path)
    args = parser.parse_args()
    fixture = ModelFixture(args.scenario, args.workspace, args.requests_file).start()
    if args.codex_home:
        fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        # The caller owns this fixture and closes its stdin to shut it down.
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
