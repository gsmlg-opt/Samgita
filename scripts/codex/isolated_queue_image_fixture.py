#!/usr/bin/env python3
"""Owned queued PNG snapshots around the unmodified pinned app-server.

The existing BEM controller owns namespace proof, native restart and shutdown.
This peer returns two fixed no-tool assistant messages and journals real native
Responses bytes plus queue metadata. It synthesizes no app-server message.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import threading
import zlib

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture


MATERIALIZE = "Owned queue image materialization"
TEXT = {"enqueue": "Owned immutable queue image", "update": "Owned replacement queue image"}
ANSWER = "Owned queued image snapshot acknowledged"


def assert_png(url, dimensions):
    assert url.startswith("data:image/png;base64,"), "Unexpected image representation"
    data = base64.b64decode(url.split(",", 1)[1], validate=True)
    assert len(data) <= 4096 and data[:8] == b"\x89PNG\r\n\x1a\n"
    rest, chunks = data[8:], []
    while rest:
        assert len(rest) >= 12
        size, kind = struct.unpack(">I4s", rest[:8])
        assert size <= 4096 and len(rest) >= size + 12
        payload, crc = rest[8:8 + size], struct.unpack(">I", rest[8 + size:12 + size])[0]
        assert crc == zlib.crc32(kind + payload)
        assert kind in {b"IHDR", b"IDAT", b"IEND"}
        chunks.append((kind, payload))
        rest = rest[12 + size:]
    assert [kind for kind, _ in chunks] == [b"IHDR", b"IDAT", b"IEND"]
    width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    assert (width, height) == dimensions
    assert (depth, color, compression, filtering, interlace) == (8, 2, 0, 0, 0)
    assert chunks[-1][1] == b""
    decoded = zlib.decompress(chunks[1][1])
    assert decoded == (b"\x00" + bytes([17, 34, 51]) * width) * height
    return hashlib.sha256(data).hexdigest()


class QueueImageProvider(ModelFixture):
    def __init__(self, root, scenario):
        super().__init__(scenario, root / "workspace", root / "requests.json")
        self.root, self.records, self.errors = root, [], []
        self.record_lock = threading.Lock()
        self.closing = threading.Event()
        self.server.daemon_threads = True
        for path in [self.requests_file, root / "queue-http.json", root / "provider-errors.json"]:
            atomic(path, [])
        provider, base = self, self.server.RequestHandlerClass

        class Handler(base):
            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def do_GET(self):
                provider.reject(self, "Unapproved HTTP method: " + self.command)

            do_PUT = do_DELETE = do_PATCH = do_HEAD = do_GET

            def do_POST(self):
                try:
                    assert self.path == "/v1/responses", "Unapproved POST path"
                    assert self.headers.get("Authorization") is None, "Unexpected auth"
                    assert self.headers.get("Content-Encoding") in {None, "identity"}
                    assert not self.headers.get("Transfer-Encoding")
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 4_194_304, "Request size out of bounds"
                    raw = self.rfile.read(size)
                    assert len(raw) == size, "Truncated owned model request"
                    request = json.loads(raw)
                    metadata = json.loads(self.headers.get("x-codex-turn-metadata", "null"))
                    assert isinstance(metadata, dict), "Missing native turn metadata"
                    assert all(isinstance(metadata.get(key), str) and metadata[key]
                               for key in ["thread_id", "turn_id"])
                    with provider.lock:
                        assert len(provider.requests) < 2, "Responses request budget exceeded"
                        provider.requests.append(request)
                        index = len(provider.requests)
                        atomic(provider.requests_file, provider.requests)
                    provider.record(index=index, metadata=metadata, path=self.path,
                                    rawBodyBase64=base64.b64encode(raw).decode(),
                                    rawBodySHA256=hashlib.sha256(raw).hexdigest(),
                                    requestAuth="none", responded=False)
                    provider.write_response(self, index, request)
                    provider.responded(index)
                except (AssertionError, KeyError, TypeError, ValueError, OSError, zlib.error) as error:
                    if not provider.closing.is_set():
                        provider.reject(self, type(error).__name__ + ": " + str(error))

        self.server.RequestHandlerClass = Handler

    def record(self, **values):
        with self.record_lock:
            assert len(self.records) < 2, "Owned queue journal bound"
            self.records.append(values)
            atomic(self.root / "queue-http.json", self.records)

    def responded(self, index):
        with self.record_lock:
            self.records[index - 1]["responded"] = True
            atomic(self.root / "queue-http.json", self.records)

    def reject(self, handler, message):
        with self.record_lock:
            assert len(self.errors) < 8, "Owned queue error bound"
            self.errors.append(message)
            atomic(self.root / "provider-errors.json", self.errors)
        handler.send_error(500, "Unapproved synthetic queued image request")

    def write_response(self, handler, index, request):
        assert request["model"] == "mock-model"
        assert not any(item.get("type") in {"function_call", "function_call_output",
                                           "custom_tool_call", "custom_tool_call_output"}
                       for item in request["input"]), "Unexpected tool execution"
        content = [part for item in request["input"] if item.get("role") == "user"
                   for part in item.get("content", [])]
        texts = [part["text"] for part in content if part.get("type") == "input_text"]
        images = [part for part in content if part.get("type") == "input_image"]
        assert MATERIALIZE in texts
        if index == 1:
            assert images == [] and TEXT[self.scenario] not in texts
        else:
            assert TEXT[self.scenario] in texts and len(images) == 1
            assert set(images[0]) == {"type", "image_url", "detail"}
            assert images[0]["detail"] == "original"
            assert_png(images[0]["image_url"], (2, 3) if self.scenario == "enqueue" else (4, 5))
            assert self.records[index - 1]["metadata"]["turn_trigger"] == "queue"
        super().write_response(handler, index, request)

    def response_item(self, index, _request):
        text = "Owned queue image thread materialized" if index == 1 else ANSWER
        return {"type": "message", "role": "assistant", "id": f"owned-queue-image-{index}",
                "content": [{"type": "output_text", "text": text}]}

    def close(self):
        self.closing.set()
        super().close()


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            (self.root / "bin").mkdir()
            shutil.copyfile("/bin/sh", self.root / "bin/sh")
            (self.root / "bin/sh").chmod(0o700)
            self.provider = QueueImageProvider(self.root, args.scenario).start()
            configure(self.root, self.provider)
            catalog = self.root / "codex/models.json"
            body = json.loads(catalog.read_text())
            body["models"][0]["supports_image_detail_original"] = True
            atomic(catalog, body)
            path = self.root / "codex/config.toml"
            config = path.read_text().replace("[features]\n", "[features]\n"
                "enable_request_compression = false\nhooks = false\nremote_models = false\n"
                "shell_tool = false\nunified_exec = false\nbrowser_use = false\ncomputer_use = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                            + config + "\n[analytics]\nenabled = false\n")
            self.config, self.catalog = path.read_bytes(), catalog.read_bytes()
            self.record("queue_provider_ready", scenario=args.scenario, source_provider_requests=0,
                        request_auth="none", output="fixed_assistant_messages_only")
        except BaseException:
            self.close()
            raise

    def start_native(self):
        assert (self.root / "codex/config.toml").read_bytes() == self.config
        assert (self.root / "codex/models.json").read_bytes() == self.catalog
        assert not (self.root / "codex/auth.json").exists()
        super().start_native()
        assert os.readlink(f"/proc/{self.native.pid}/ns/net") == self.proof["namespace"]

    def control(self, message):
        assert len(self.journal) < 48, "Owned queue controller journal bound"
        super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["enqueue", "update"])
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
