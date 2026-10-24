#!/usr/bin/env python3
"""Owned native required-skills gate; real executor reads and one fixed assistant reply."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import threading
import tomllib
import uuid

import isolated_thread_environment_fixture as shared
from isolated_environment_fixture import TOKEN
from model_fixture import ModelFixture


AVAILABLE = "skills-available"
MISSING = "skills-missing"
PROMPTS = {AVAILABLE: "Owned required skill available input", MISSING: "Owned required skill missing input"}
ANSWER = "Owned required skill gate admitted this assistant-only response"
REQUIRED = {AVAILABLE: "owned:review", MISSING: "owned:absent"}
SKILL = "---\nname: review\ndescription: Synthetic inert fixture metadata.\n---\nThis fixture has no executable actions.\n"
ORIGINAL_VALIDATE = shared.validate


def atomic(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


class SkillsProvider(ModelFixture):
    def __init__(self, fixture):
        super().__init__("assistant", fixture.root / "workspace", fixture.root / "skills-requests.json")
        self.fixture, self.errors = fixture, []
        self.server.daemon_threads = True
        atomic(self.requests_file, [])
        atomic(fixture.root / "skills-provider-errors.json", [])
        provider, base = self, self.server.RequestHandlerClass

        class Handler(base):
            def setup(self):
                fixture.remember()
                super().setup()
                self.connection.settimeout(3)

            def do_GET(self):
                provider.reject(self, "unapproved_method")

            do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = do_GET

            def do_POST(self):
                try:
                    assert self.path == "/v1/responses"
                    assert self.headers.get("Authorization") is None
                    assert self.headers.get("Content-Encoding") in {None, "identity"}
                    assert not self.headers.get("Transfer-Encoding")
                    size = int(self.headers.get("Content-Length", "0"))
                    assert 0 < size <= 4_194_304
                    raw = self.rfile.read(size)
                    assert len(raw) == size and TOKEN.encode() not in raw
                    request = json.loads(raw)
                    metadata = json.loads(self.headers.get("x-codex-turn-metadata", "null"))
                    assert request["model"] == "mock-model" and isinstance(request["input"], list)
                    assert isinstance(metadata, dict)
                    with fixture.state_lock:
                        assert fixture.threads.get(metadata.get("thread_id")) == AVAILABLE
                        assert metadata.get("turn_id")
                    assert not any(item.get("type") in {
                        "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output"
                    } for item in request["input"])
                    texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                             for part in item.get("content", []) if part.get("type") == "input_text"]
                    assert texts.count(PROMPTS[AVAILABLE]) == 1 and PROMPTS[MISSING] not in texts
                    with provider.lock:
                        assert provider.requests == [], "owned provider request budget"
                        provider.requests.append(request)
                        atomic(provider.requests_file, provider.requests)
                    fixture.record("skills_model_request", thread_id=metadata["thread_id"],
                                   turn_id=metadata["turn_id"], model="mock-model", request_auth="none")
                    provider.write_response(self, 1, request)
                    self.wfile.flush()
                    fixture.record("skills_model_response", count=1)
                except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
                    if not fixture.closed.is_set():
                        provider.reject(self, type(error).__name__)

        self.server.RequestHandlerClass = Handler

    def reject(self, handler, kind):
        with self.lock:
            assert len(self.errors) < 8
            self.errors.append(kind)
            atomic(self.fixture.root / "skills-provider-errors.json", self.errors)
        self.fixture.record("fixture_error", stage="skills-provider", error_type=kind)
        handler.send_error(500, "Unapproved owned fixture request")

    def response_item(self, index, _request):
        assert index == 1
        return {"type": "message", "role": "assistant", "id": "owned-skills-answer",
                "content": [{"type": "output_text", "text": ANSWER}]}


class NativeOutput:
    """Observe original response IDs; return every byte unchanged to the shared reader."""
    def __init__(self, original, fixture):
        self.original, self.fixture = original, fixture

    def readline(self, size):
        line = self.original.readline(size)
        if line.endswith("\n") and len(line.encode()) <= shared.MAX_FRAME:
            wire = json.loads(line)
            with self.fixture.state_lock:
                environment = self.fixture.pending_threads.pop(wire.get("id"), None)
                if environment is not None:
                    identity = wire["result"]["thread"]["id"]
                    assert str(uuid.UUID(identity)) == identity
                    assert identity not in self.fixture.threads
                    self.fixture.threads[identity] = environment
        return line

    def __getattr__(self, name):
        return getattr(self.original, name)


class Fixture(shared.Fixture):
    def __init__(self, root, namespace):
        super().__init__(root, namespace)
        self.gate.set()
        self.state_lock = threading.Lock()
        self.registrations, self.thread_environments, self.turn_threads = set(), set(), set()
        self.pending_threads, self.threads = {}, {}
        self.snapshots = {}
        self.header_owner = threading.local()

    def configure(self):
        secret = super().configure()
        # The original deny-only listener is explicitly stopped and joined before replacement.
        self.http.shutdown()
        self.http.server_close()
        with self.worker_lock:
            original_workers = list(self.workers)
        for worker in original_workers:
            worker.join(5)
            assert not worker.is_alive(), "original deny HTTP worker did not stop"
        self.provider = SkillsProvider(self)
        self.http = self.provider.server
        self.remember(self.provider.thread)
        self.provider.start()
        for name in ["app", "executor"]:
            path = self.root / name / "config.toml"
            text = path.read_text()
            assert text.count("\nplugins = false\n") == 1
            old_url = tomllib.loads(text)["model_providers"]["fixture"]["base_url"].removesuffix("/v1")
            assert old_url.startswith("http://127.0.0.1:")
            text = text.replace(old_url, self.provider.url).replace("[features]\n", "[features]\n"
                "executor_capability_discovery = false\nenable_request_compression = false\n"
                "remote_models = false\nshell_tool = false\nunified_exec = false\n"
                "browser_use = false\ncomputer_use = false\n")
            text = ("check_for_update_on_startup = false\nallow_login_shell = false\n"
                    "project_doc_max_bytes = 0\nproject_root_markers = []\n" + text +
                    "\n[plugins._default]\nenabled = false\n"
                    "[plugins.owned-skills-root]\nenabled = true\n")
            config = tomllib.loads(text)
            assert config["chatgpt_base_url"] == self.provider.url + "/backend-api"
            assert config["openai_base_url"] == self.provider.url + "/v1"
            assert config["model_providers"]["fixture"]["base_url"] == self.provider.url + "/v1"
            assert "mcp_servers" not in config
            assert config["features"]["plugins"] is False
            assert config["features"]["recommended_plugins"] is False
            assert config["plugins"] == {"_default": {"enabled": False},
                                         "owned-skills-root": {"enabled": True}}
            assert config["project_doc_max_bytes"] == 0 and config["project_root_markers"] == []
            path.write_text(text)
        catalog = self.root / "app/models.json"
        models = json.loads(catalog.read_text())
        models["models"][0]["model_messages"]["instructions_template"] = "Return only the fixed assistant response. Do not call tools."
        catalog.write_text(json.dumps(models))
        self.skill_root = self.root / "owned-capability-root"
        (self.skill_root / ".codex-plugin").mkdir(parents=True)
        (self.skill_root / "review").mkdir()
        (self.skill_root / ".codex-plugin/plugin.json").write_text('{"name":"owned","mcpServers":{}}\n')
        (self.skill_root / "review/SKILL.md").write_text(SKILL)
        paths = [self.root / "app/config.toml", self.root / "executor/config.toml", catalog,
                 self.skill_root / ".codex-plugin/plugin.json", self.skill_root / "review/SKILL.md"]
        self.snapshots = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        for ancestor in [self.root, *self.root.parents]:
            assert not (ancestor / ".codex/config.toml").exists(), "unowned ancestor config"
        self.assert_owned_files()
        self.record("skills_fixture_ready", owned_files=self.snapshots,
                    available=REQUIRED[AVAILABLE], missing=REQUIRED[MISSING], provider_budget=1)
        return secret

    def assert_owned_files(self):
        expected = {self.skill_root / ".codex-plugin", self.skill_root / "review",
                    self.skill_root / ".codex-plugin/plugin.json", self.skill_root / "review/SKILL.md"}
        assert set(self.skill_root.rglob("*")) == expected
        for path in [self.root, self.skill_root, *expected]:
            assert not path.is_symlink() and path.resolve().is_relative_to(self.root)
        for path, digest in self.snapshots.items():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest

    def spawn(self, binary, args, name, cwd):
        child = super().spawn(binary, args, name, cwd)
        if name == "app":
            child.stdout = NativeOutput(child.stdout, self)
        return child

    def connection(self, downstream, identity):
        self.header_owner.first = True
        super().connection(downstream, identity)

    def headers(self, conn):
        original = super().headers(conn)
        if self.header_owner.first:
            self.header_owner.first = False
            headers = [line.split(b":", 1) for line in original.split(b"\r\n")[1:] if b":" in line]
            bearers = [value.strip() for name, value in headers if name.lower() == b"authorization"]
            assert bearers == [("Bearer " + TOKEN).encode("ascii")]
        return original

    def validate_exec(self, wire):
        method, params = wire.get("method"), wire.get("params")
        if method in shared.EXEC_ALLOWED:
            return
        self.record("skills_rpc_attempt", method=method, keys=sorted(params),
                    path=params.get("path"),
                    walk_options=params.get("options") if method == "fs/walk" else None,
                    sandbox_is_null=params.get("sandbox") is None,
                    cwd_is_owned=params.get("cwd") == (self.root / "executor-workspace").as_uri())
        self.assert_owned_files()
        root = self.skill_root.as_uri()
        if method == "fs/walk":
            assert params == {"path": root, "sandbox": None, "options": {
                "maxDepth": 6, "maxDirectories": 2000, "maxEntries": 20000,
                "followDirectorySymlinks": True}}
        elif method in {"fs/getMetadata", "fs/readFile"}:
            allowed = {root + "/.codex-plugin/plugin.json"}
            if method == "fs/getMetadata":
                allowed.update({root, root + "/.claude-plugin/plugin.json",
                                root + "/.cursor-plugin/plugin.json",
                                (self.root / "executor-workspace/.agents/skills").as_uri()})
            else:
                allowed.add(root + "/review/SKILL.md")
            assert set(params) == {"path", "sandbox"} and params["sandbox"] is None
            assert params["path"] in allowed
        elif method == "environmentConfig/read":
            assert params == {"cwd": (self.root / "executor-workspace").as_uri(),
                "configPaths": [["mcp_servers"]], "requirementsPaths": [["mcp_servers"]]}
        else:
            self.record("forbidden_exec_rpc", method=method)
            raise AssertionError("unapproved executor operation")

    def frames(self, source, target, client, identity):
        count = 0
        while not self.closed.is_set():
            prefix = self.read_exact(source, 2)
            deadline = shared.time.monotonic() + 5
            opcode, masked, size = prefix[0] & 15, bool(prefix[1] & 128), prefix[1] & 127
            assert prefix[0] & 128 and not prefix[0] & 112
            assert masked == client and opcode in (1, 2, 8, 9, 10)
            extension = b""
            if size in (126, 127):
                extension = self.read_exact(source, 2 if size == 126 else 8, deadline)
                size = struct.unpack("!H" if size == 126 else "!Q", extension)[0]
            assert size <= shared.MAX_FRAME and (opcode < 8 or size <= 125)
            mask = self.read_exact(source, 4, deadline) if masked else b""
            payload = self.read_exact(source, size, deadline)
            count += 1
            assert count <= 96, "owned exec-server frame count"
            if opcode in (1, 2):
                decoded = bytes(value ^ mask[index % 4] for index, value in enumerate(payload)) if masked else payload
                assert TOKEN.encode() not in decoded
                wire = json.loads(decoded)
                if client:
                    self.validate_exec(wire)
                    self.record("exec_rpc", method=wire.get("method"), connection=identity,
                                id=wire.get("id"), path=(wire.get("params") or {}).get("path"))
            target.sendall(prefix + extension + mask + payload)
            if opcode == 8:
                return

    def close(self):
        super().close()
        if self.snapshots:
            self.assert_owned_files()
            assert not self.provider.thread.is_alive()
            self.record("skills_resources_closed", files_unchanged=True, provider_workers_stopped=True,
                        model_requests=len(self.provider.requests))


def validate(wire, fixture):
    method, params = wire.get("method"), wire.get("params")
    assert method in {"initialize", "initialized", "environment/add", "environment/info",
                      "environment/status", "thread/start", "turn/start", "thread/loaded/list"}
    if method in {"initialize", "initialized"}:
        ORIGINAL_VALIDATE(wire, fixture)
    elif method == "environment/add":
        environment = params["environmentId"]
        assert environment in REQUIRED and environment not in fixture.registrations
        assert params == {"environmentId": environment, "execServerUrl": fixture.url,
            "authBearerToken": TOKEN, "connectTimeoutMs": 15_000,
            "skills": {"required": [REQUIRED[environment]]}}
        fixture.registrations.add(environment)
    elif method in {"environment/info", "environment/status"}:
        assert set(params) == {"environmentId"} and params["environmentId"] in fixture.registrations
    elif method == "thread/start":
        [selection] = params["environments"]
        environment = selection["environmentId"]
        assert environment in fixture.registrations and environment not in fixture.thread_environments
        assert params == {"model": "mock-model", "modelProvider": "fixture",
            "cwd": str(fixture.root / "workspace"), "sandbox": "read-only",
            "approvalPolicy": "on-request", "ephemeral": False,
            "config": {"features.plugins": True, "features.cwd_relative_turn_diffs": True},
            "environments": [{"environmentId": environment, "cwd": str(fixture.root / "executor-workspace")}],
            "selectedCapabilityRoots": [{"id": "owned-skills-root", "location": {
                "type": "environment", "environmentId": environment, "path": fixture.skill_root.as_uri()}}]}
        with fixture.state_lock:
            fixture.pending_threads[wire["id"]] = environment
            fixture.thread_environments.add(environment)
    elif method == "turn/start":
        with fixture.state_lock:
            thread = params["threadId"]
            environment = fixture.threads[thread]
            assert thread not in fixture.turn_threads
            assert params == {"threadId": thread, "input": [{"type": "text", "text": PROMPTS[environment]}]}
            fixture.turn_threads.add(thread)
    else:
        assert params == {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    parser.add_argument("--parent-userns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == shared.SHA256
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration present"
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"])
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork",
            "--kill-child=TERM", sys.executable, __file__, *sys.argv[1:], "--inside",
            "--parent-netns", os.readlink("/proc/self/ns/net"),
            "--parent-userns", os.readlink("/proc/self/ns/user")])
    shared.Fixture = Fixture
    shared.validate = validate
    shared.isolated(args)


if __name__ == "__main__":
    main()
