#!/usr/bin/env python3
"""Owned synthetic success results using the verified quota fixture lifecycle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

from isolated_imagegen_failure_fixture import (
    ACCESS, ACCOUNT, SHA, Fixture as QuotaFixture, ImageProvider as QuotaImageProvider,
    atomic, isolation, response_events,
)


CALL = "owned-image-success-call"
MESSAGE = "owned-image-success-message"
PROMPT = "Owned synthetic image success whale"
ANSWER = "Owned image success acknowledged"
RESULT = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
REQUEST_ID = "owned-image-success-request"
GENERATION_ID = "owned-image-success-generation"
IMAGE_REQUEST = {"prompt": PROMPT, "background": "transparent", "model": "gpt-image-2",
                 "quality": "auto", "size": "auto"}


class ImageProvider(QuotaImageProvider):
    def __init__(self, root, scenario):
        super().__init__(root, scenario)
        inherited_handler = self.server.RequestHandlerClass
        provider = self

        class Handler(inherited_handler):
            def do_GET(self):
                try:
                    assert self.headers.get("Authorization") == "Bearer " + ACCESS
                    assert self.headers.get("ChatGPT-Account-Id") == ACCOUNT
                    assert self.headers.get("Content-Length") in {None, "0"}
                    assert not self.headers.get("Transfer-Encoding")
                    if self.path == "/api/codex/settings/user":
                        assert self.headers.get("Cache-Control") == "no-cache, no-store"
                    provider.record("success_startup_auth", path=self.path,
                                    account=self.headers.get("ChatGPT-Account-Id"))
                    super().do_GET()
                except (AssertionError, KeyError, TypeError, ValueError) as error:
                    provider.reject(self, "GET " + self.path + ": " + repr(error))

        self.server.RequestHandlerClass = Handler

    def image(self, handler, size):
        request = json.loads(handler.rfile.read(size))
        assert request == IMAGE_REQUEST
        assert handler.headers.get("originator") == "chatgpt_cca"
        turn_id = handler.headers.get("x-codex-image-turn-id")
        assert isinstance(turn_id, str) and len(turn_id) == 36
        with self.record_lock:
            self.image_requests += 1
            assert self.image_requests == 1, "image request budget exceeded"
        self.record("image_request", body=request, turn_id=turn_id,
                    originator=handler.headers.get("originator"))
        assert self.release.wait(timeout=10), "owned image success response release deadline"
        response = {"created": 1, "background": self.scenario, "data": [
            {"b64_json": RESULT, "generation_id": GENERATION_ID},
            {"b64_json": "ignored", "generation_id": "owned-image-unused-generation"}]}
        headers = {"x-codex-imagegen-request-id": REQUEST_ID}
        body = json.dumps(response).encode()
        handler.send_response(200)
        for name, value in headers.items():
            handler.send_header(name, value)
        handler.send_header("Content-Type", "application/json")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        self.record("image_response", status=200, headers=headers, body=response)
        handler.wfile.write(body)

    def write_response(self, handler, index, request):
        assert request["model"] == "mock-model"
        assert index in {1, 2}, "Responses request budget exceeded"
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        if index == 1:
            assert outputs == []
            item = {"type": "function_call", "namespace": "image_gen", "name": "imagegen",
                    "call_id": CALL, "arguments": json.dumps({
                        "prompt": PROMPT, "transparent_background": True})}
        else:
            assert self.image_requests == 1
            assert len(outputs) == 1 and outputs[0]["call_id"] == CALL
            content = outputs[0]["output"]
            assert isinstance(content, list) and len(content) == 2
            assert content[0] == {"type": "input_image",
                                  "image_url": "data:image/png;base64," + RESULT,
                                  "detail": "high"}
            assert set(content[1]) == {"type", "text"} and content[1]["type"] == "input_text"
            assert str(self.root / "codex" / "generated_images") in content[1]["text"]
            assert "already displayed to the user" in content[1]["text"]
            item = {"type": "message", "role": "assistant", "id": MESSAGE,
                    "content": [{"type": "output_text", "text": ANSWER}]}
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in response_events(index, item)).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        self.record("responses_response", index=index, status=200)
        handler.wfile.write(body)


class Fixture(QuotaFixture):
    def __init__(self, args, proof):
        super().__init__(args, proof)
        previous_url = self.provider.url
        self.provider.close()
        assert self.provider.requests == [] and self.native is None
        self.provider = ImageProvider(self.root, args.scenario).start()
        path = self.root / "codex" / "config.toml"
        config = path.read_text()
        previous_base = f'base_url = "{previous_url}/api/codex"'
        assert config.count(previous_base) == 2
        config = config.replace(previous_base, f'base_url = "{self.provider.url}/api/codex"')
        previous_chatgpt = f'chatgpt_base_url = "{previous_url}"'
        assert config.count(previous_chatgpt) == 1
        path.write_text(config.replace(previous_chatgpt, f'chatgpt_base_url = "{self.provider.url}"'))
        self.record("image_success_provider_ready", source_provider_requests=0,
                    scenario=args.scenario, api_base=self.provider.url + "/api/codex",
                    request_auth="explicit_synthetic_provider_bearer",
                    local_account="synthetic_chatgpt_only")

    def control(self, message):
        assert message.get("op") in {"release200", "restart", "barrier", "close"}
        if message["op"] == "release200":
            assert set(message) == {"id", "op"} and not self.closed
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            assert self.provider.image_requests == 1 and not self.provider.release.is_set()
            self.provider.release.set()
            self.record("control_done", id=message["id"], op=message["op"])
        else:
            super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["opaque", "transparent"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args, isolation(args.parent_netns))
        fixture.start_native()
        for line in sys.stdin:
            assert len(line.encode()) <= 1024
            fixture.control(json.loads(line))
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


if __name__ == "__main__":
    main()
