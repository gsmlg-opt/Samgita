#!/usr/bin/env python3
"""Owned HTTP image quota failure around the unmodified pinned native binary.

Only fixed Responses/image requests and the existing realtime peer are served.
The existing BEM fixture owns namespace/process lifecycle; it starts no native
process until its unused initial provider has been closed and replaced here.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from model_fixture import ModelFixture, response_events


ACCESS = "owned-synthetic-image-access"
ACCOUNT = "owned-synthetic-image-account"
CALL = "owned-image-limit-call"
MESSAGE = "owned-image-limit-message"
PROMPT = "Owned synthetic blue whale"
ANSWER = "Owned image quota result acknowledged"
RESET = 1786150800
IMAGE_REQUEST = {"prompt": PROMPT, "background": "opaque", "model": "gpt-image-2",
                 "quality": "auto", "size": "auto"}


def synthetic_auth():
    # Same intentionally unsigned JWT construction as official
    # app-server/tests/common/auth_fixtures.rs:134-167. Never real credentials.
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    token = encoded({"alg": "none", "typ": "JWT"}) + "." + encoded({
        "https://api.openai.com/auth": {"chatgpt_plan_type": "plus",
                                      "chatgpt_account_id": ACCOUNT}}) + "." + \
        base64.urlsafe_b64encode(b"signature").decode().rstrip("=")
    return {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
            "tokens": {"id_token": token, "access_token": ACCESS,
                       "refresh_token": "owned-synthetic-image-refresh", "account_id": ACCOUNT},
            "last_refresh": datetime.now(timezone.utc).isoformat()}


class ImageProvider(ModelFixture):
    def __init__(self, root, scenario):
        super().__init__(scenario, root / "workspace", root / "requests.json")
        self.root = root
        self.records, self.errors = [], []
        self.record_lock = threading.Lock()
        self.image_requests = 0
        self.release = threading.Event()
        atomic(self.requests_file, [])
        atomic(root / "imagegen-http.json", [])
        atomic(root / "provider-errors.json", [])
        provider = self
        responses_handler = self.server.RequestHandlerClass

        class Handler(responses_handler):
            def do_GET(self):
                bodies = {
                    "/api/codex/accounts/check": {"accounts": [{
                        "id": ACCOUNT,
                        "workspace_backend_origin": "https://owned-synthetic-image-backend.invalid",
                        "account_routing_override": "NO_CONSTRAINT"}]},
                    "/api/codex/settings/user": {"commit_attribution_enabled": False},
                    "/api/codex/config/bundle": {},
                }
                if self.path not in bodies:
                    provider.reject(self, "Unapproved GET: " + self.path)
                    return
                body = json.dumps(bodies[self.path]).encode()
                provider.record("startup_metadata", path=self.path)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                try:
                    assert self.path in {"/api/codex/responses", "/api/codex/images/generations"}
                    assert self.headers.get("Authorization") == "Bearer " + ACCESS
                    assert self.headers.get("Content-Encoding") in {None, "identity"}
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 4194304
                    assert not self.headers.get("Transfer-Encoding")
                    provider.record("http_request", path=self.path, method="POST",
                                    authorization=self.headers.get("Authorization"),
                                    content_encoding=self.headers.get("Content-Encoding"))
                    if self.path == "/api/codex/images/generations":
                        provider.image(self, size)
                    else:
                        # Reuse the exact owned Responses reader/journal/SSE
                        # implementation, with only the configured native path
                        # adapted to the official custom OpenAI provider path.
                        original = self.path
                        self.path = "/v1/responses"
                        try:
                            super().do_POST()
                        finally:
                            self.path = original
                except (AssertionError, KeyError, TypeError, ValueError) as error:
                    provider.reject(self, self.command + " " + self.path + ": " +
                                    type(error).__name__ + ": " + str(error))

        self.server.RequestHandlerClass = Handler

    def record(self, event, **values):
        with self.record_lock:
            self.records.append({"event": event, **values})
            atomic(self.root / "imagegen-http.json", self.records)

    def reject(self, handler, detail):
        with self.record_lock:
            self.errors.append(detail)
            atomic(self.root / "provider-errors.json", self.errors)
        handler.send_error(500, "Unapproved owned imagegen request")

    def image(self, handler, size):
        request = json.loads(handler.rfile.read(size))
        assert request == IMAGE_REQUEST
        with self.record_lock:
            self.image_requests += 1
            assert self.image_requests == 1, "image request budget exceeded"
        self.record("image_request", body=request)
        # The owner must observe actual native item-start and BEM promotion
        # before this fixed HTTP failure is allowed onto the wire.
        assert self.release.wait(timeout=10), "owned image response release deadline"
        headers = {"x-codex-active-limit": "image_gen",
                   "x-image-gen-primary-used-percent": "100",
                   "x-image-gen-primary-window-minutes": "1440"}
        error = {"type": "usage_limit_reached",
                 "message": "Owned synthetic image limit reached", "plan_type": "plus"}
        if self.scenario == "reset":
            headers["x-image-gen-primary-reset-at"] = str(RESET)
            error["resets_at"] = RESET
        body = json.dumps({"error": error}).encode()
        handler.send_response(429)
        for name, value in headers.items():
            handler.send_header(name, value)
        handler.send_header("Content-Type", "application/json")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        self.record("image_response", status=429, headers=headers, body={"error": error})
        handler.wfile.write(body)

    def write_response(self, handler, index, request):
        assert request["model"] == "mock-model"
        assert index in {1, 2}, "Responses request budget exceeded"
        outputs = [item for item in request["input"] if item.get("type") == "function_call_output"]
        if index == 1:
            assert outputs == []
            item = {"type": "function_call", "namespace": "image_gen", "name": "imagegen",
                    "call_id": CALL, "arguments": json.dumps({"prompt": PROMPT})}
        else:
            assert self.image_requests == 1
            assert len(outputs) == 1 and outputs[0]["call_id"] == CALL
            assert "image generation failed:" in str(outputs[0]["output"])
            item = {"type": "message", "role": "assistant", "id": MESSAGE,
                    "content": [{"type": "output_text", "text": ANSWER}]}
        events = response_events(index, item)
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        self.record("responses_response", index=index, status=200)
        handler.wfile.write(body)

    def close(self):
        self.release.set()
        super().close()


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        # Reuse the existing peer/catalog/native process lifecycle intact.
        # The original provider has no native consumer yet and no request.
        original_url = self.provider.url
        self.provider.close()
        assert self.provider.requests == [] and self.native is None
        self.provider = ImageProvider(self.root, args.scenario).start()
        path = self.root / "codex" / "config.toml"
        config = path.read_text()
        assert not any(line.strip().startswith("cli_auth_credentials_store")
                       for line in config.splitlines())
        config = 'cli_auth_credentials_store = "file"\n' + config
        assert config.count("[features]\n") == 1
        assert "enable_request_compression" not in config and "[analytics]" not in config
        # The pinned upstream local ChatGPT tests use this supported feature
        # setting so the fixed Responses peer receives plain JSON. Compression
        # is not part of this image-result profile.
        config = config.replace("[features]\n",
                                "[features]\nenable_request_compression = false\n")
        config += "\n[analytics]\nenabled = false\n"
        old_base = f'base_url = "{original_url}/v1"'
        assert config.count(old_base) == 2
        config = config.replace(old_base, f'base_url = "{self.provider.url}/api/codex"')
        old_chatgpt = f'chatgpt_base_url = "http://127.0.0.1:{self.peer.server.server_port}"'
        assert config.count(old_chatgpt) == 1
        config = config.replace(old_chatgpt, f'chatgpt_base_url = "{self.provider.url}"')
        assert config.count("requires_openai_auth = false") == 1
        config = config.replace("requires_openai_auth = false", "requires_openai_auth = true")
        lines = config.splitlines()
        assert len([line for line in lines if line.startswith("experimental_bearer_token = ")]) == 1
        # Pinned realtime_api_key does not accept ChatGPT-only auth. The
        # explicit provider bearer is independently selected by both realtime
        # and model-provider API auth; fake ChatGPT remains local account state.
        config = "\n".join('experimental_bearer_token = ' + json.dumps(ACCESS)
                           if line.startswith("experimental_bearer_token = ") else line
                           for line in lines) + "\n"
        path.write_text(config.replace('name = "Owned synthetic BEM fixture"', 'name = "OpenAI"'))
        auth = self.root / "codex" / "auth.json"
        atomic(auth, synthetic_auth())
        auth.chmod(0o600)
        self.record("image_provider_ready", source_provider_requests=0,
                    scenario=args.scenario, api_base=self.provider.url + "/api/codex",
                    request_auth="explicit_synthetic_provider_bearer",
                    local_account="synthetic_chatgpt_only")

    def control(self, message):
        if message.get("op") == "release429":
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
    parser.add_argument("--scenario", required=True, choices=["reset", "no_reset"])
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
