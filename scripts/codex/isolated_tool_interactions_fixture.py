#!/usr/bin/env python3
"""Pinned native tool interactions with an isolated synthetic Responses peer.

Every app-server message originates in the real Codex executable. The synthetic
provider requests only user input or a registered client-side dynamic tool; no
shell command, account, external service or credential is involved.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

from model_fixture import ModelFixture


BINARY_SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"


def write_json(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def isolation(parent):
    namespace = os.readlink("/proc/self/ns/net")
    assert namespace != parent, "BLOCKED_ENV: unchanged network namespace"
    interfaces = json.loads(subprocess.check_output(["ip", "-j", "link", "show"]))
    routes = json.loads(subprocess.check_output(["ip", "-j", "route", "show", "table", "all"]))
    assert [row["ifname"] for row in interfaces] == ["lo"], "BLOCKED_ENV: nonloopback link"
    assert all(row.get("dev") == "lo" and row.get("dst") != "default" for row in routes)
    assert all(not row.get("prefsrc") or ipaddress.ip_address(row["prefsrc"]).is_loopback
               for row in routes)
    return {"namespace": namespace, "parent_namespace": parent,
            "interfaces": ["lo"], "default_route": False}


class ToolProvider(ModelFixture):
    def __init__(self, root):
        super().__init__("interactions", root / "workspace", root / "requests.json")
        self.calls = {}

    def response_item(self, index, request):
        markers = [part["text"] for item in request.get("input", [])
                   if item.get("role") == "user" for part in item.get("content", [])
                   if part.get("type") == "input_text"
                   and re.fullmatch(r"synthetic:[a-z-]+:[0-9]+", part.get("text", ""))]
        assert markers, "unexpected inference without synthetic scenario"
        marker = markers[-1]
        scenario = marker.split(":")[1]
        count = self.calls.get(marker, 0) + 1
        self.calls[marker] = count
        assert count <= 2, "unexpected extra inference for tool interaction"
        if count == 2:
            return {"type": "message", "role": "assistant", "id": f"owned-answer-{index}",
                    "content": [{"type": "output_text", "text": "Owned interaction finished"}]}
        async_scenarios = {
            "async-questions": ("request_user_input_async", {"questions": [
                {"title": "Choose owned color λ", "options": ["Green", "Blue"]},
                {"title": "Provide owned detail"},
                {"title": "Explicit null detail", "options": None},
            ]}),
            "async-notice": ("send_message_to_user_async", {"message": "  Owned async notice λ  "}),
            "async-empty-questions": ("request_user_input_async", {"questions": []}),
            "async-blank-title": ("request_user_input_async", {"questions": [{"title": " \n "}]}),
            "async-empty-options": ("request_user_input_async", {"questions": [
                {"title": "Owned invalid options", "options": []},
            ]}),
            "async-blank-option": ("request_user_input_async", {"questions": [
                {"title": "Owned invalid options", "options": ["Green", " \t "]},
            ]}),
            "async-blank-notice": ("send_message_to_user_async", {"message": " \n\t "}),
        }
        if scenario in async_scenarios:
            name, arguments = async_scenarios[scenario]
            return {"type": "function_call", "name": name, "namespace": "functions",
                    "call_id": marker, "arguments": json.dumps(arguments)}
        if scenario.startswith("input-"):
            questions = [{"id": "choice", "header": "Choice", "question": "Choose synthetic input",
                          "options": [{"label": "One", "description": "Synthetic one"},
                                      {"label": "Two", "description": "Synthetic two"}]}]
            if scenario == "input-multi":
                questions[0]["isOther"] = False
                questions.append({"id": "detail", "header": "Detail", "isSecret": True,
                                  "question": "Choose a synthetic detail",
                                  "options": [{"label": "Red", "description": "Synthetic red"},
                                              {"label": "Blue", "description": "Synthetic blue"}]})
            elif scenario == "input-empty-options":
                questions[0]["options"] = []
            return {"type": "function_call", "name": "request_user_input", "call_id": marker,
                    "arguments": json.dumps({"questions": questions})}
        assert scenario.startswith("dynamic-"), "unapproved synthetic tool"
        return {"type": "function_call", "name": "lookup", "namespace": "fixture",
                "call_id": marker, "arguments": json.dumps({
                    "key": "synthetic", "nested": {"null": None, "list": [1, "λ", False]},
                })}


def configure(root, provider):
    catalog = root / "codex" / "models.json"
    write_json(catalog, {"models": [{
        "slug": "mock-model", "display_name": "Owned synthetic interactions",
        "supported_reasoning_levels": [], "shell_type": "unified_exec",
        "visibility": "list", "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Synthetic tool qualification only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
        "input_modalities": ["text", "image", "audio"],
        "experimental_supported_tools": ["request_user_input_async", "send_message_to_user_async"],
    }]})
    (root / "codex" / "config.toml").write_text(f'''
model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "on-request"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
chatgpt_base_url = "{provider.url}"
openai_base_url = "{provider.url}/v1"
[features]
apps = false
plugins = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "Owned synthetic tool provider"
base_url = "{provider.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')


def run(args):
    root = args.root.resolve(strict=True)
    codex = Path(args.codex).resolve(strict=True)
    assert hashlib.sha256(codex.read_bytes()).hexdigest() == BINARY_SHA256, "unpinned native binary"
    if not args.inside:
        assert sys.platform == "linux", "BLOCKED_ENV: Linux required"
        assert shutil.which("unshare") and shutil.which("ip"), "BLOCKED_ENV: unshare/ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
                             "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:],
                             "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])

    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    proof = isolation(args.parent_netns)
    provider = ToolProvider(root)
    provider.server.daemon_threads = True
    provider.start()
    configure(root, provider)

    class ForbiddenFetch(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            write_json(root / "forbidden-fetch.json", {"path": self.path})
            self.send_response(400)
            self.end_headers()

    forbidden = ThreadingHTTPServer(("127.0.0.1", 0), ForbiddenFetch)
    forbidden.daemon_threads = True
    forbidden_thread = threading.Thread(target=forbidden.serve_forever, daemon=True)
    forbidden_thread.start()
    environment = {key: value for key, value in os.environ.items()
                   if key in {"HOME", "CODEX_HOME", "PATH", "TMPDIR", "NO_COLOR",
                              "RUST_LOG", "CODEX_DISABLE_REMOTE_CONTROL", "PYTHONDONTWRITEBYTECODE"}}
    native = subprocess.Popen([str(codex), "app-server", "--listen", "unix://" + str(root / "native.sock")],
                              cwd=root / "workspace", env=environment,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)

    def terminate(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    try:
        deadline = time.monotonic() + 5
        while not (root / "native.sock").exists():
            assert native.poll() is None, "native startup exited"
            assert time.monotonic() < deadline, "native owned UDS startup deadline"
            time.sleep(0.01)
        write_json(root / "state.json", {
            **proof, "controller_pid": os.getpid(), "namespace_owner_pid": os.getppid(),
            "native_pid": native.pid, "ready": True,
            "forbidden_url": f"http://127.0.0.1:{forbidden.server_port}/must-not-fetch",
        })
        assert not sys.stdin.readline(), "no fixture mutation control is supported"
    finally:
        native.terminate()
        try:
            native.wait(timeout=5)
        except subprocess.TimeoutExpired:
            native.kill()
            native.wait(timeout=5)
        provider.close()
        forbidden.shutdown()
        forbidden.server_close()
        forbidden_thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
