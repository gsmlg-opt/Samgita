#!/usr/bin/env python3
"""Real pinned local Bedrock configuration controls, with no AWS network route.

This source-only draft emits no app-server frames and opens no listener. Only
owned static credential files/environment are admitted; no credential process,
SSO, role assumption, model turn or AWS service acceptance is exercised.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading


SHA256 = "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
SECRETS = ["synthetic-owned-env-access", "synthetic-owned-env-secret",
           "synthetic-owned-bedrock-bearer", "synthetic-owned-engineering-access",
           "synthetic-owned-engineering-secret", "synthetic-owned-finance-access",
           "synthetic-owned-finance-secret"]
DISCOVER = "account/bedrock/discover"
SETUP = "account/bedrock/setup"
GOV = "account/bedrock/checkGovCloudRequirements"
ALLOWED = {"initialize", "initialized", DISCOVER, SETUP, GOV,
           "config/read", "config/value/write", "thread/loaded/list"}
BASE_URLS = ["https://bedrock-mantle.us-gov-west-1.api.aws/openai/v1",
             "https://bedrock-mantle.us-west-2.api.aws/openai/v1",
             "https://bedrock-mantle.us-gov-west-1.api.aws.synthetic.invalid/openai/v1"]
MAX_WIRE = 65_536


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


def configure(args):
    root, codex = args.root, args.root / "codex"
    aws = root / "aws"
    aws.mkdir(mode=0o700, exist_ok=True)
    (aws / "config").write_text("[profile engineering]\nregion = us-west-2\n")
    (aws / "credentials").write_text(
        "[engineering]\naws_access_key_id = " + SECRETS[3] +
        "\naws_secret_access_key = " + SECRETS[4] +
        "\n[finance]\naws_access_key_id = " + SECRETS[5] +
        "\naws_secret_access_key = " + SECRETS[6] + "\n")
    for path in aws.iterdir():
        path.chmod(0o600)
    catalog = codex / "models.json"
    write_json(catalog, {"models": [{
        "slug": "mock-model", "display_name": "No inference authorized",
        "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
        "supported_in_api": True, "priority": 1,
        "model_messages": {"instructions_template": "No turns in this profile."},
        "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
        "experimental_supported_tools": []}]})
    path = codex / "config.toml"
    if not path.exists():
        forced = 'forced_login_method = "chatgpt"\n' if args.forced_chatgpt else ""
        path.write_text(forced + f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
cli_auth_credentials_store = "file"
mcp_oauth_credentials_store = "file"
web_search = "disabled"
chatgpt_base_url = "http://127.0.0.1:9/backend-api"
openai_base_url = "http://127.0.0.1:9/v1"
[analytics]
enabled = false
[features]
apps = false
plugins = false
codex_hooks = false
recommended_plugins = false
shell_snapshot = false
[model_providers.fixture]
name = "No inference local Bedrock controls"
base_url = "http://127.0.0.1:9/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[model_providers.amazon-bedrock]
http_headers = {{ X-Existing = "preserved-synthetic" }}
[model_providers.amazon-bedrock.aws]
region = "us-east-1"
''')
    environment = {"HOME": str(root / "home"), "CODEX_HOME": str(codex),
        "TMPDIR": str(root / "tmp"), "PATH": os.environ["PATH"],
        "AWS_CONFIG_FILE": str(aws / "config"), "AWS_SHARED_CREDENTIALS_FILE": str(aws / "credentials"),
        "AWS_PROFILE": "engineering", "AWS_EC2_METADATA_DISABLED": "true",
        "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
        "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
    if args.env_mode in ["both", "access", "default-only"]:
        environment.update(AWS_ACCESS_KEY_ID=SECRETS[0], AWS_SECRET_ACCESS_KEY=SECRETS[1])
    if args.env_mode in ["both", "api", "default-only"]:
        environment["AWS_BEARER_TOKEN_BEDROCK"] = SECRETS[2]
    if args.env_mode == "default-only":
        environment["AWS_DEFAULT_REGION"] = "us-west-2"
    elif args.env_mode in ["both", "access", "api"]:
        environment["AWS_REGION"] = " us-west-2 "
    elif args.env_mode == "incomplete":
        environment.update(AWS_ACCESS_KEY_ID=SECRETS[0], AWS_SECRET_ACCESS_KEY=" ",
                           AWS_BEARER_TOKEN_BEDROCK=" ")
    return environment


def validate(wire):
    method, params = wire.get("method"), wire.get("params")
    assert method in ALLOWED, "unapproved native method"
    if method == SETUP:
        assert isinstance(params, dict)
        assert set(params) in [{"type", "region"}, {"type", "region", "profile"}]
        assert params.get("type") in ["environment", "profile"]
        assert params.get("region") in ["us-west-2", " us-east-2 ", "us-east-1", "us-west-1"]
        if params["type"] == "profile":
            assert params.get("profile") in [" engineering ", "engineering", "missing", " "]
        else:
            assert set(params) == {"type", "region"}
    elif method == "config/value/write":
        assert set(params) == {"keyPath", "value", "mergeStrategy"}
        allowed = {"model_provider": ["fixture", "amazon-bedrock"],
                   "model_providers.amazon-bedrock.aws.region": ["us-west-2"],
                   "model_providers.amazon-bedrock.base_url": BASE_URLS}
        assert params["mergeStrategy"] == "replace" and params["keyPath"] in allowed
        assert params["value"] in allowed[params["keyPath"]]
    elif method == "config/read":
        assert params in [None, {}, {"includeLayers": True}]
    elif method in [DISCOVER, GOV, "thread/loaded/list"]:
        assert params in [None, {}]


def isolated(args):
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
    proof = isolation(args.parent_netns)
    path = args.root / "journal.json"
    journal = json.loads(path.read_text()) if path.exists() else {"events": []}
    journal["namespace"] = proof
    lock = threading.RLock()
    native, reader = None, None

    def record(event, **fields):
        with lock:
            assert len(journal["events"]) < 160
            journal["events"].append({"event": event, **fields})
            write_json(path, journal)

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        environment = configure(args)
        with (args.root / "native-stderr.log").open("ab") as stderr:
            native = subprocess.Popen([str(args.codex), "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                cwd=args.root / "workspace", env=environment)
        record("native_started", pid=native.pid, controller_pid=os.getpid(),
               namespace_owner_pid=os.getppid(), binary_sha256=SHA256, env_mode=args.env_mode,
               no_listener=True, no_external_route=True, static_credentials_only=True)

        def output():
            try:
                while line := native.stdout.readline(MAX_WIRE + 1):
                    assert len(line) <= MAX_WIRE and line.endswith(b"\n")
                    if any(secret.encode() in line for secret in SECRETS):
                        record("secret_leak", surface="native-wire")
                        raise AssertionError("synthetic credential reached native wire")
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
            except Exception as error:
                record("fixture_error", stage="native-output", error_type=type(error).__name__)

        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        count = 0
        while line := sys.stdin.buffer.readline(MAX_WIRE + 1):
            count += 1
            assert count <= 48 and len(line) <= MAX_WIRE and line.endswith(b"\n")
            wire = json.loads(line)
            validate(wire)
            record("native_input", method=wire["method"], id=wire.get("id"))
            native.stdin.write(line)
            native.stdin.flush()
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if native is not None:
            native.stdin.close()
            if native.poll() is None:
                native.terminate()
            try:
                native.wait(timeout=5)
            except subprocess.TimeoutExpired:
                native.kill()
                native.wait(timeout=5)
        if reader is not None:
            reader.join(5)
            assert not reader.is_alive(), "owned native output reader did not stop"
        if native is not None:
            checked = [(args.root / name).read_bytes() for name in ["native-stderr.log", "journal.json"]]
            checked += [(args.root / "codex/config.toml").read_bytes()]
            record("secret_scan", passed=all(secret.encode() not in text for secret in SECRETS for text in checked))
            record("native_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--env-mode", choices=["both", "access", "api", "none", "default-only", "incomplete"], required=True)
    parser.add_argument("--forced-chatgpt", action="store_true")
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA256
    assert all((args.root / name).is_dir() and not (args.root / name).is_symlink()
               for name in ["home", "codex", "workspace", "tmp"])
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration must not enter synthetic profile"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"]), \
            "BLOCKED_ENV: Linux private user/network namespace and ip required"
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net")])
    isolated(args)


if __name__ == "__main__":
    main()
