#!/usr/bin/env python3
"""Pinned native Guardian controls with an owned fixed MCP/Responses peer.

All app-server messages come from Codex. Only the allow scenario returns one
fixed in-memory tool result; no command execution or network forwarding exists.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
import re
from pathlib import Path
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SERVER, TOOL, CALL = "owned_guardian", "denied_action", "owned-guardian-action"
RATIONALE = "Owned synthetic action is not authorized."
DENIAL_ASSESSMENTS = {
    "deny-medium-low": {"risk_level": "medium", "user_authorization": "low",
                        "outcome": "deny", "rationale": "Owned medium-risk action remains denied."},
    "deny-critical-medium": {"risk_level": "critical", "user_authorization": "medium",
                             "outcome": "deny", "rationale": "Owned critical-risk action remains denied."},
}
ALLOW_RATIONALE = "Owned fixed in-memory action is authorized."
ALLOW_ARGUMENTS = {"message": "owned harmless allow payload"}
ALLOW_RESULT_TEXT = "owned harmless allow result"
CANARY = "OWNED_GUARDIAN_PRIVATE_CANARY"
APPROVE = "thread/approveGuardianDeniedAction"
MAX_WIRE = 262_144
ALLOWED = {"initialize", "initialized", "thread/start", "turn/start", "turn/interrupt",
           "thread/read", APPROVE}


def write_json(path, value):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(value))
    pending.replace(path)


def isolation(parent):
    current = os.readlink("/proc/self/ns/net")
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], timeout=5))
    routes = []
    for family in [[], ["-6"]]:
        routes += json.loads(subprocess.check_output(
            ["ip", *family, "-j", "route", "show", "table", "all"], timeout=5))
    assert current != parent and [link["ifname"] for link in links] == ["lo"]
    for route in routes:
        assert route.get("dev") == "lo" and route.get("dst") != "default"
        assert not route.get("prefsrc") or ipaddress.ip_address(route["prefsrc"]).is_loopback
    return {"parent": parent, "child": current, "interfaces": ["lo"],
            "default_route": False, "ipv6_default_route": False}


def denial_event(params):
    action = params["action"]
    assert action["type"] == "mcpToolCall"
    assert action["server"] == SERVER and action["toolName"] == TOOL
    event = {"id": params["reviewId"], "target_item_id": params.get("targetItemId"),
             "turn_id": params["turnId"], "started_at_ms": params["startedAtMs"],
             "completed_at_ms": params["completedAtMs"], "status": "denied",
             "decision_source": "agent", "risk_level": params["review"]["riskLevel"],
             "user_authorization": params["review"]["userAuthorization"],
             "rationale": params["review"]["rationale"],
             "action": {"type": "mcp_tool_call", "server": action["server"],
                        "tool_name": action["toolName"], "connector_id": action.get("connectorId"),
                        "connector_name": action.get("connectorName"), "tool_title": action.get("toolTitle")}}
    assert event["risk_level"] == "high" and event["user_authorization"] == "unknown"
    assert event["rationale"] == RATIONALE
    return event


class Fixture:
    def __init__(self, args, proof):
        self.args, self.lock = args, threading.RLock()
        self.journal = {"namespace": proof, "events": []}
        self.requests, self.parent_calls, self.reviewer_calls = [], 0, 0
        self.denial, self.closing = None, threading.Event()
        self.allow_released, self.action_calls = False, 0
        self.peer_sockets, self.peer_threads = set(), set()
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            block_on_close = False

            def process_request_thread(self, request, client_address):
                thread = threading.current_thread()
                with fixture.lock:
                    if fixture.closing.is_set():
                        request.close()
                        return
                    fixture.peer_sockets.add(request)
                    fixture.peer_threads.add(thread)
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    with fixture.lock:
                        fixture.peer_sockets.discard(request)
                        fixture.peer_threads.discard(thread)

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="http-worker",
                                   error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, body):
                wire = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(wire)))
                self.end_headers()
                self.wfile.write(wire)

            def do_GET(self):
                # MCP's optional independent GET and Guardian V2 prewarm are
                # deliberately unavailable. Neither response carries a score.
                if self.path == "/mcp":
                    fixture.record("mcp_get_unavailable")
                    self.reply(405, {})
                elif self.path == "/v1/responses" and args.scenario == "strict-overflow":
                    fixture.record("classifier_prewarm_unavailable")
                    self.reply(426, {})
                else:
                    fixture.record("forbidden_http", method="GET", path=self.path)
                    self.reply(404, {})

            def do_DELETE(self):
                if self.path == "/mcp":
                    fixture.record("mcp_delete")
                    self.reply(405, {})
                else:
                    fixture.record("forbidden_http", method="DELETE", path=self.path)
                    self.reply(404, {})

            def do_POST(self):
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 1_048_576
                    assert self.headers.get("Authorization") is None
                    assert self.headers.get("ChatGPT-Account-ID") is None
                    value = json.loads(self.rfile.read(size))
                    if self.path == "/mcp":
                        self.mcp(value)
                    elif self.path == "/v1/responses":
                        self.model_response(value)
                    else:
                        fixture.record("forbidden_http", method="POST", path=self.path)
                        self.reply(404, {})
                except (BrokenPipeError, ConnectionResetError):
                    fixture.record("peer_closed")
                except Exception as error:
                    fixture.record("fixture_error", stage="http", error_type=type(error).__name__)
                    self.reply(400, {})

            def mcp(self, value):
                method, identity = value.get("method"), value.get("id")
                fixture.record("mcp", method=method, id=identity)
                if identity is None:
                    assert method in ["notifications/initialized", "notifications/cancelled"]
                    self.reply(202, {})
                    return
                if method == "initialize":
                    result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                              "serverInfo": {"name": SERVER, "version": "1"}}
                elif method == "tools/list":
                    description = "Owned fixed in-memory allow result" if args.scenario == "allow" else \
                        "Owned synthetic denied action; no execution implementation"
                    result = {"tools": [{"name": TOOL, "description": description,
                        "inputSchema": {"type": "object", "properties": {"message": {"type": "string"}},
                                        "required": ["message"], "additionalProperties": False}}]}
                elif method == "tools/call" and args.scenario == "allow":
                    params = value["params"]
                    assert set(params) <= {"name", "arguments", "_meta"}
                    assert params["name"] == TOOL and params["arguments"] == ALLOW_ARGUMENTS
                    assert "_meta" not in params or isinstance(params["_meta"], dict)
                    with fixture.lock:
                        assert fixture.allow_released and fixture.reviewer_calls == 1
                        assert fixture.parent_calls == 1
                        fixture.action_calls += 1
                        assert fixture.action_calls == 1, "fixed allow action dispatched twice"
                        fixture.record("mcp_action_dispatched", tool=TOOL,
                                       arguments=params["arguments"], result_text=ALLOW_RESULT_TEXT)
                    result = {"content": [{"type": "text", "text": ALLOW_RESULT_TEXT}], "isError": False}
                elif method == "resources/list":
                    result = {"resources": []}
                elif method == "resources/templates/list":
                    result = {"resourceTemplates": []}
                elif method == "ping":
                    result = {}
                else:
                    fixture.record("forbidden_mcp", method=method)
                    self.reply(200, {"jsonrpc": "2.0", "id": identity,
                                     "error": {"code": -32601, "message": "no execution implementation"}})
                    return
                self.reply(200, {"jsonrpc": "2.0", "id": identity, "result": result})

            def model_response(self, value):
                reviewer = value.get("client_metadata", {}).get("x-openai-subagent") == "guardian"
                assert value.get("model") == "mock-model"
                with fixture.lock:
                    fixture.requests.append(value)
                    assert len(fixture.requests) <= 4
                    write_json(args.root / "requests.json", fixture.requests)
                    if reviewer:
                        fixture.reviewer_calls += 1
                        assert fixture.reviewer_calls == 1
                    else:
                        fixture.parent_calls += 1
                        assert fixture.parent_calls <= (3 if args.scenario == "deny" else 2)
                    parent_index = fixture.parent_calls
                fixture.record("provider_request", reviewer=reviewer, parent_index=parent_index,
                               auth_absent=True)
                if reviewer:
                    assert CALL in json.dumps(value) or TOOL in json.dumps(value)
                    if args.scenario == "cancel":
                        deadline = time.monotonic() + 15
                        while not fixture.closing.is_set():
                            assert time.monotonic() < deadline, "held reviewer cancellation deadline"
                            readable, _, _ = select.select([self.connection], [], [], 0.02)
                            if readable:
                                try:
                                    closed = not self.connection.recv(1, socket.MSG_PEEK)
                                except ConnectionResetError:
                                    closed = True
                                if closed:
                                    fixture.record("reviewer_transport_closed")
                                    return
                        return
                    if args.scenario == "allow":
                        fixture.record("allow_reviewer_held")
                        release = args.root / "allow-review.release"
                        deadline = time.monotonic() + 15
                        while not release.exists():
                            if fixture.closing.is_set():
                                return
                            assert time.monotonic() < deadline, "held allow reviewer deadline"
                            time.sleep(0.01)
                        assert release.is_file() and not release.is_symlink()
                        assert release.read_text() == "allow\n"
                        with fixture.lock:
                            assert fixture.action_calls == 0
                            fixture.allow_released = True
                            fixture.record("allow_reviewer_released")
                        assessment = {"risk_level": "low", "user_authorization": "high",
                                      "outcome": "allow", "rationale": ALLOW_RATIONALE}
                    else:
                        assessment = DENIAL_ASSESSMENTS.get(args.scenario, {
                            "risk_level": "high", "user_authorization": "unknown",
                            "outcome": "deny", "rationale": RATIONALE})
                    text = json.dumps(assessment)
                    item = fixture.message("owned-review-result", text)
                elif parent_index == 1:
                    message = ALLOW_ARGUMENTS["message"] if args.scenario == "allow" else "owned denied payload"
                    if args.scenario == "strict-overflow":
                        message = "owned oversized payload " * 100
                    item = {"type": "function_call", "namespace": "mcp__" + SERVER,
                            "name": TOOL, "call_id": CALL,
                            "arguments": json.dumps({"message": message})}
                else:
                    if args.scenario == "allow":
                        assert parent_index == 2 and fixture.action_calls == 1
                        outputs = [item for item in value.get("input", [])
                                   if item.get("type") == "function_call_output" and item.get("call_id") == CALL]
                        assert len(outputs) == 1
                        output = outputs[0]["output"]
                        assert len(output) == 2 and output[0]["type"] == "input_text"
                        assert re.fullmatch(r"Wall time: \d+\.\d{4} seconds\nOutput:", output[0]["text"])
                        assert output[1] == {"type": "input_text", "text": ALLOW_RESULT_TEXT}
                        fixture.record("allow_parent_continuation", call_id=CALL, content=output[1])
                    if parent_index == 3:
                        assert args.scenario == "deny"
                        assert any(item.get("role") == "developer" and
                                   "Treat this as approval to perform that exact action" in json.dumps(item) and
                                   TOOL in json.dumps(item) for item in value.get("input", []))
                        fixture.record("approved_context_observed")
                    parent_text = "Owned parent finished after one approved fixed action." if args.scenario == "allow" else \
                        "Owned parent finished without executing tools."
                    item = fixture.message("owned-parent-result", parent_text)
                identity = "owned-review" if reviewer else "owned-parent-" + str(parent_index)
                events = [
                    {"type": "response.created", "response": {"id": identity}},
                    {"type": "response.output_item.done", "item": item},
                    {"type": "response.completed", "response": {"id": identity, "usage": {
                        "input_tokens": 1, "input_tokens_details": None,
                        "output_tokens": 1, "output_tokens_details": None, "total_tokens": 2}}}]
                body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                               for event in events).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                self.wfile.flush()
                fixture.record("provider_response_sent", reviewer=reviewer, parent_index=parent_index)

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)

    @staticmethod
    def message(identity, text):
        return {"type": "message", "role": "assistant", "id": identity,
                "content": [{"type": "output_text", "text": text}]}

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 180
            self.journal["events"].append({"event": event, **fields})
            write_json(self.args.root / "journal.json", self.journal)

    def validate(self, value):
        method, params = value.get("method"), value.get("params", {})
        assert method in ALLOWED, "unapproved app-server method"
        if method == "thread/start":
            assert params == {"cwd": str(self.args.root / "workspace")}
        elif method == "turn/start":
            assert set(params) == {"threadId", "input"}
            inputs = [[{"type": "text", "text": "synthetic:guardian:deny"}],
                      [{"type": "text", "text": "synthetic:guardian:observe-approval"}]]
            if self.args.scenario == "allow":
                inputs.append([{"type": "text", "text": "synthetic:guardian:allow"}])
            assert params["input"] in inputs
        elif method == APPROVE:
            assert self.args.scenario == "deny" and self.denial is not None
            assert params == {"threadId": self.denial["threadId"], "event": denial_event(self.denial)}


def configure(args, endpoint):
    catalog = args.root / "codex/models.json"
    write_json(catalog, {"models": [{"slug": "mock-model", "display_name": "Owned Guardian fixture",
        "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
        "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Owned synthetic Guardian qualification only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 20000},
        "experimental_supported_tools": []}]})
    guardian = 'enabled = true\nmax_action_tokens = 128\n[features.guardianv2.review_scope]\ncomputer_use_only = false' \
        if args.scenario == "strict-overflow" else 'enabled = false'
    (args.root / "codex/config.toml").write_text(f'''# {CANARY}
model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "on-request"
approvals_reviewer = "auto_review"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
chatgpt_base_url = "{endpoint}"
openai_base_url = "{endpoint}/v1"
[analytics]
enabled = false
[features]
guardian_approval = true
apps = false
plugins = false
hooks = false
recommended_plugins = false
shell_snapshot = false
shell_tool = false
unified_exec = false
enable_request_compression = false
[features.guardianv2]
{guardian}
[model_providers.fixture]
name = "Owned fixed Guardian provider"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[mcp_servers.{SERVER}]
url = "{endpoint}/mcp"
default_tools_approval_mode = "prompt"
''')


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = Fixture(args, isolation(args.parent_netns))
    fixture.thread.start()
    configure(args, f"http://127.0.0.1:{fixture.server.server_port}")
    native, reader = None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        environment = {"HOME": str(args.root / "home"), "CODEX_HOME": str(args.root / "codex"),
            "TMPDIR": str(args.root / "tmp"), "PATH": os.environ["PATH"],
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
        with (args.root / "native-stderr.log").open("wb") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        fixture.record("native_started", pid=native.pid, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=SHA256)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n")
                    assert CANARY.encode() not in line
                    value = json.loads(line)
                    if value.get("method") == "item/autoApprovalReview/completed":
                        params = value["params"]
                        if params["review"]["status"] == "denied":
                            if args.scenario in DENIAL_ASSESSMENTS:
                                expected = DENIAL_ASSESSMENTS[args.scenario]
                                assert params["review"] == {"status": "denied",
                                    "riskLevel": expected["risk_level"],
                                    "userAuthorization": expected["user_authorization"],
                                    "rationale": expected["rationale"]}
                                assert params["action"]["type"] == "mcpToolCall"
                                assert params["action"]["server"] == SERVER
                                assert params["action"]["toolName"] == TOOL
                            else:
                                denial_event(params)
                                fixture.denial = params
                        elif args.scenario == "allow" and params["review"]["status"] == "approved":
                            assert params["review"] == {"status": "approved", "riskLevel": "low",
                                "userAuthorization": "high", "rationale": ALLOW_RATIONALE}
                            assert params["action"]["type"] == "mcpToolCall"
                            assert params["action"]["server"] == SERVER
                            assert params["action"]["toolName"] == TOOL
                            fixture.record("allow_review_completed", review_id=params["reviewId"],
                                thread_id=params["threadId"], turn_id=params["turnId"],
                                target_item_id=params["targetItemId"])
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 24 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            value = json.loads(line)
            fixture.validate(value)
            fixture.record("native_input", method=value["method"], id=value.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        # The outer stdio owner kills its owned group after one second. Release
        # held peers first, then fit all explicit child/thread waits inside 0.75s.
        deadline = time.monotonic() + 0.75
        def remaining(cap):
            return max(0.0, min(cap, deadline - time.monotonic()))

        fixture.closing.set()
        with fixture.lock:
            peers = list(fixture.peer_sockets)
        for peer in peers:
            try:
                peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        fixture.server.shutdown()
        fixture.server.server_close()
        if native is not None:
            try:
                native.stdin.close()
            except OSError:
                pass
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=remaining(0.25))
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=remaining(0.15))
        if reader:
            reader.join(remaining(0.15))
            assert not reader.is_alive()
        with fixture.lock:
            peer_threads = list(fixture.peer_threads)
        for peer_thread in peer_threads:
            peer_thread.join(remaining(0.15))
            assert not peer_thread.is_alive(), "owned Guardian peer cleanup deadline"
        fixture.thread.join(remaining(0.1))
        assert not fixture.thread.is_alive()
        checked = [(args.root / name).read_bytes() for name in ["native-stderr.log", "journal.json"]]
        checked += [json.dumps(fixture.requests).encode()]
        fixture.record("secret_scan", passed=all(CANARY.encode() not in data for data in checked))
        fixture.record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["deny", "cancel", "strict-overflow", "allow",
        "deny-medium-low", "deny-critical-medium"])
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
    assert all((args.root / name).is_dir() and not (args.root / name).is_symlink()
               for name in ["home", "codex", "workspace", "tmp"])
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter fixture"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
