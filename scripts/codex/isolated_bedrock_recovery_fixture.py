#!/usr/bin/env python3
"""Pinned native Bedrock auth recovery against an owned SigV4/Responses peer.

No real AWS executable, credential, endpoint or model-selected tool is admitted.
Only Codex emits app-server frames; the HTTP peer emits fixed dependency data.
"""
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import traceback


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
KEYS = {
    "old": ("OWNED_BEDROCK_OLD_KEY", "owned-bedrock-old-secret-canary", "owned-bedrock-old-session-canary"),
    "new": ("OWNED_BEDROCK_NEW_KEY", "owned-bedrock-new-secret-canary", "owned-bedrock-new-session-canary")}
TEXT = "Owned Bedrock recovery completed."
MAX_WIRE = 262_144
ALLOWED = {"initialize", "initialized", "thread/start", "turn/start", "thread/read"}


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


def verify_signature(headers, body, state):
    key_id, secret, token = KEYS[state]
    authorization = headers["Authorization"]
    assert authorization.startswith("AWS4-HMAC-SHA256 ")
    fields = dict(part.strip().split("=", 1) for part in authorization.split(" ", 1)[1].split(","))
    credential = fields["Credential"].split("/")
    assert credential[0] == key_id and credential[2:] == ["us-east-1", "bedrock-mantle", "aws4_request"]
    assert headers["X-Amz-Security-Token"] == token
    timestamp = headers["X-Amz-Date"]
    assert timestamp[:8] == credential[1]
    names = fields["SignedHeaders"].split(";")
    assert names == sorted(set(names)) and "host" in names and "x-amz-date" in names
    canonical_headers = "".join(name + ":" + " ".join(headers[name].split()) + "\n" for name in names)
    digest = hashlib.sha256(body).hexdigest()
    assert headers.get("X-Amz-Content-Sha256", digest) == digest
    canonical = "POST\n/v1/responses\n\n" + canonical_headers + "\n" + fields["SignedHeaders"] + "\n" + digest
    scope = "/".join(credential[1:])
    to_sign = "AWS4-HMAC-SHA256\n" + timestamp + "\n" + scope + "\n" + hashlib.sha256(canonical.encode()).hexdigest()
    signing_key = ("AWS4" + secret).encode()
    for component in credential[1:]:
        signing_key = hmac.new(signing_key, component.encode(), hashlib.sha256).digest()
    expected = hmac.new(signing_key, to_sign.encode(), hashlib.sha256).hexdigest()
    assert hmac.compare_digest(expected, fields["Signature"])


class Fixture:
    def __init__(self, args, proof):
        self.args, self.lock = args, threading.RLock()
        self.journal = {"namespace": proof, "events": []}
        self.closing = threading.Event()
        self.peer_sockets, self.peer_threads = set(), set()
        self.requests, self.payload_digest, self.payload = 0, None, None
        fixture = self

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            block_on_close = False

            def process_request_thread(self, request, client_address):
                worker = threading.current_thread()
                with fixture.lock:
                    if fixture.closing.is_set():
                        request.close()
                        return
                    fixture.peer_sockets.add(request)
                    fixture.peer_threads.add(worker)
                try:
                    super().process_request_thread(request, client_address)
                finally:
                    with fixture.lock:
                        fixture.peer_sockets.discard(request)
                        fixture.peer_threads.discard(worker)

            def handle_error(self, _request, _address):
                if not fixture.closing.is_set():
                    fixture.record("fixture_error", stage="http-worker", error_type=sys.exc_info()[0].__name__)

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(5)

            def log_message(self, *_args):
                pass

            def reply(self, status, body, content_type="application/json"):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                fixture.record("unexpected_http", method="GET", path=self.path)
                self.reply(404, b"{}")

            def do_POST(self):
                try:
                    assert self.path == "/v1/responses"
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 1_048_576
                    assert self.headers.get("Content-Encoding") is None
                    assert self.headers.get("ChatGPT-Account-ID") is None
                    assert self.headers.get("Host") == f"127.0.0.1:{fixture.server.server_port}"
                    body = self.rfile.read(size)
                    payload = json.loads(body)
                    assert payload["model"] == "openai.gpt-5.5"
                    assert "synthetic:bedrock:recover" in json.dumps(payload["input"])
                    state = json.loads((args.root / "credential-state.json").read_text())
                    verify_signature(self.headers, body, state)
                    with fixture.lock:
                        fixture.requests += 1
                        assert fixture.requests <= 2
                        assert state == ("old" if fixture.requests == 1 else "new")
                        digest = hashlib.sha256(body).hexdigest()
                        if fixture.payload_digest is None:
                            fixture.payload_digest = digest
                            fixture.payload = payload
                        else:
                            fixture.record("retry_payload", raw_equal=fixture.payload_digest == digest,
                                semantic_equal=fixture.payload == payload,
                                changed_keys=sorted(key for key in fixture.payload.keys() | payload.keys()
                                                    if fixture.payload.get(key) != payload.get(key)))
                        # Native rebuilds HashMap metadata on unauthorized recovery;
                        # JSON key order is not a replay identity. Compare every
                        # decoded value, while SigV4 above still checks raw bytes.
                        assert fixture.payload == payload
                    status = 401 if state == "old" else 200
                    fixture.record("signed_request", credential_state=state, status=status,
                                   sigv4_verified=True, semantic_payload_preserved=True, host_verified=True)
                    if status == 401:
                        self.reply(401, b'{"error":{"message":"ExpiredTokenException"}}')
                        return
                    events = [
                        {"type": "response.created", "response": {"id": "owned-bedrock-response"}},
                        {"type": "response.output_item.done", "item": {"type": "message",
                         "role": "assistant", "id": "owned-bedrock-message",
                         "content": [{"type": "output_text", "text": TEXT}]}},
                        {"type": "response.completed", "response": {"id": "owned-bedrock-response",
                         "usage": {"input_tokens": 1, "input_tokens_details": None,
                         "output_tokens": 1, "output_tokens_details": None, "total_tokens": 2}}}]
                    wire = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in events).encode()
                    self.reply(200, wire, "text/event-stream")
                except (BrokenPipeError, ConnectionResetError):
                    fixture.record("peer_closed")
                except Exception as error:
                    site = traceback.extract_tb(error.__traceback__)[-1]
                    fixture.record("fixture_error", stage="provider", error_type=type(error).__name__,
                                   function=site.name, line=site.lineno)
                    self.reply(400, b"{}")

        self.server = Server(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True)

    def record(self, event, **fields):
        with self.lock:
            assert len(self.journal["events"]) < 160
            self.journal["events"].append({"event": event, **fields})
            write_json(self.args.root / "journal.json", self.journal)


def configure(args, endpoint):
    root, codex = args.root, args.root / "codex"
    for directory in ["aws", "bin", "helpers"]:
        (root / directory).mkdir(mode=0o700)
    helper = root / "bin/aws"
    helper.write_bytes(("#!" + sys.executable + " -I\n").encode() +
        Path(__file__).with_name("owned_bedrock_credential_helper.py").read_bytes())
    helper.chmod(0o700)
    (root / "aws/config").write_text("[profile owned]\nregion = us-east-1\n")
    key, secret, token = KEYS["old"]
    (root / "aws/credentials").write_text("[owned]\naws_access_key_id = " + key +
        "\naws_secret_access_key = " + secret + "\naws_session_token = " + token + "\n")
    for path in (root / "aws").iterdir():
        path.chmod(0o600)
    write_json(root / "credential-state.json", "old")
    catalog = codex / "models.json"
    write_json(catalog, {"models": [{"slug": "openai.gpt-5.5", "display_name": "Owned Bedrock recovery",
        "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
        "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "Owned synthetic credential recovery only."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 20000},
        "experimental_supported_tools": []}]})
    source = f'''credential_export = {{ command = {json.dumps(str(helper))}, args = ["--owned-export"], timeout_ms = 2000 }}\n''' \
        if args.scenario == "export" else 'profile = "owned"\n'
    refresh = 'auth_refresh = { command = "aws", args = ["--owned-refresh"], timeout_ms = 2000 }\n'
    (codex / "config.toml").write_text(f'''model = "openai.gpt-5.5"
model_provider = "amazon-bedrock"
model_catalog_json = {json.dumps(str(catalog))}
approval_policy = "never"
sandbox_mode = "read-only"
web_search = "disabled"
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
[analytics]
enabled = false
[features]
apps = false
plugins = false
hooks = false
recommended_plugins = false
shell_snapshot = false
shell_tool = false
unified_exec = false
enable_request_compression = false
[model_providers.amazon-bedrock]
base_url = "{endpoint}/v1"
[model_providers.amazon-bedrock.aws]
region = "us-east-1"
{source}{refresh}''')
    return {"HOME": str(root / "home"), "CODEX_HOME": str(codex), "TMPDIR": str(root / "tmp"),
        "PATH": str(root / "bin"), "AWS_CONFIG_FILE": str(root / "aws/config"),
        "AWS_SHARED_CREDENTIALS_FILE": str(root / "aws/credentials"), "AWS_EC2_METADATA_DISABLED": "true",
        "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1", "NO_COLOR": "1",
        "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1", "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    fixture = Fixture(args, isolation(args.parent_netns))
    fixture.thread.start()
    environment = configure(args, f"http://127.0.0.1:{fixture.server.server_port}")
    native, reader = None, None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        with (args.root / "native-stderr.log").open("wb") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        identity = {"pid": native.pid, "pgid": os.getpgid(native.pid), "scenario": args.scenario,
                    "netns": os.readlink("/proc/self/ns/net"), "parent_netns": args.parent_netns}
        write_json(args.root / "native-owner.json", identity)
        fixture.record("native_started", **identity, controller_pid=os.getpid(),
                       namespace_owner_pid=os.getppid(), binary_sha256=SHA256,
                       exclusive_helper_path=True, inherited_credentials=False)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n")
                    assert all(secret.encode() not in line for values in KEYS.values() for secret in values)
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                fixture.record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 10 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            value = json.loads(line)
            method, params = value.get("method"), value.get("params")
            assert method in ALLOWED
            if method == "initialize":
                assert params.get("capabilities", {}).get("experimentalApi", False) is False
            elif method == "thread/start":
                assert params == {"cwd": str(args.root / "workspace")}
            elif method == "turn/start":
                assert set(params) == {"threadId", "input"}
                assert params["input"] == [{"type": "text", "text": "synthetic:bedrock:recover"}]
            elif method == "thread/read":
                assert set(params) == {"threadId", "includeTurns"} and params["includeTurns"] is True
            else:
                assert params is None
            fixture.record("native_input", method=method, id=value.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
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
            workers = list(fixture.peer_threads)
        for worker in workers:
            worker.join(remaining(0.1))
            assert not worker.is_alive()
        fixture.thread.join(remaining(0.1))
        assert not fixture.thread.is_alive()
        helpers = [json.loads(path.read_text()) for path in (args.root / "helpers").glob("*.json")]
        for helper in helpers:
            assert not Path(f"/proc/{helper['pid']}").exists(), "owned credential helper did not exit"
        checked = [(args.root / name).read_bytes() for name in ["native-stderr.log", "journal.json", "codex/config.toml"]]
        checked += [json.dumps(helpers).encode()]
        passed = all(secret.encode() not in value for values in KEYS.values() for secret in values for value in checked)
        fixture.record("secret_scan", passed=passed)
        fixture.record("native_closed", helpers_exited=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["profile", "export"])
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
