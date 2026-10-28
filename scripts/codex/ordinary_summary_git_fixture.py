#!/usr/bin/env python3
"""Owned scratch-Git facts/config only; never an app-server or model emulator."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
MAX_LINE = 16_384
ORIGIN = "https://example.invalid/owned-summary.git"
UNBORN_ORIGIN = "https://example.invalid/owned-unborn.git"
BASELINE = "original\n"
CHANGED = "changed λ\n"
UNTRACKED = "untracked 🙂\n"


class Fixture:
    def __init__(self, root, git):
        self.root = root.resolve(strict=True)
        self.git = git.resolve(strict=True)
        assert self.root.name.startswith("samgita-ordinary-summary-git-")
        self.deadline = time.monotonic() + 15
        self.commands = []
        self.dirty = False
        self.env = {
            "HOME": str(self.root / "home"), "PATH": str(self.git.parent) + ":/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C.UTF-8",
            "GIT_AUTHOR_NAME": "Owned summary fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Owned summary fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
            "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
        }

    def run(self, repo, *args, allowed=(0,)):
        assert repo.parent == self.root and repo.name in ("named", "detached", "unborn")
        assert len(self.commands) < 48
        remaining = self.deadline - time.monotonic()
        assert remaining > 0, "Owned scratch-Git total deadline"
        command = [str(self.git), "-c", "core.hooksPath=/dev/null",
                   "-c", "commit.gpgsign=false", "-c", "core.fsmonitor=false", *args]
        completed = subprocess.run(command, cwd=repo, env=self.env, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=min(2, remaining), check=False)
        assert len(completed.stdout) <= MAX_LINE and len(completed.stderr) <= MAX_LINE
        assert completed.returncode in allowed, "Owned scratch-Git command failed"
        self.commands.append({"repo": repo.name, "args": list(args),
                              "status": completed.returncode})
        return completed.stdout.decode("utf-8").strip(), completed.returncode

    def init(self, name, committed):
        repo = self.root / name
        repo.mkdir()
        self.run(repo, "init", "--initial-branch=main", "--object-format=sha1")
        if committed:
            (repo / "tracked.txt").write_text(BASELINE, encoding="utf-8")
            self.run(repo, "add", "tracked.txt")
            self.run(repo, "commit", "-m", "Owned local baseline")
        return repo

    def prepare(self):
        named = self.init("named", True)
        detached = self.init("detached", True)
        unborn = self.init("unborn", False)
        base, _ = self.run(named, "rev-parse", "HEAD")
        detached_base, _ = self.run(detached, "rev-parse", "HEAD")
        assert base == detached_base and len(base) == 40
        self.run(named, "remote", "add", "origin", ORIGIN)
        self.run(named, "update-ref", "refs/remotes/origin/main", base)
        self.run(named, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        self.run(detached, "checkout", "--detach", detached_base)
        self.run(unborn, "remote", "add", "origin", UNBORN_ORIGIN)
        self.configure()
        return self.facts()

    def facts(self):
        named, detached, unborn = [self.root / key for key in ("named", "detached", "unborn")]
        base, _ = self.run(named, "rev-parse", "HEAD")
        named_branch, _ = self.run(named, "symbolic-ref", "--short", "HEAD")
        named_origin, _ = self.run(named, "remote", "get-url", "origin")
        detached_sha, _ = self.run(detached, "rev-parse", "HEAD")
        _, detached_status = self.run(detached, "symbolic-ref", "--quiet", "HEAD", allowed=(1,))
        detached_remotes, _ = self.run(detached, "remote")
        _, unborn_status = self.run(unborn, "rev-parse", "--verify", "HEAD", allowed=(128,))
        unborn_origin, _ = self.run(unborn, "remote", "get-url", "origin")
        assert named_branch == "main" and named_origin == ORIGIN
        assert detached_status == 1 and detached_remotes == ""
        assert unborn_status == 128 and unborn_origin == UNBORN_ORIGIN
        assert (detached / "tracked.txt").read_text(encoding="utf-8") == BASELINE
        expected = CHANGED if self.dirty else BASELINE
        assert (named / "tracked.txt").read_text(encoding="utf-8") == expected
        assert (named / "new.txt").exists() == self.dirty
        if self.dirty:
            assert (named / "new.txt").read_text(encoding="utf-8") == UNTRACKED
        return {
            "named": {"cwd": str(named), "sha": base, "branch": "main", "origin_url": ORIGIN},
            "detached": {"cwd": str(detached), "sha": detached_sha, "branch": None, "origin_url": None},
            "unborn": {"cwd": str(unborn), "sha": None, "branch": None, "origin_url": UNBORN_ORIGIN},
            "dirty": self.dirty, "commands": self.commands,
        }

    def change(self):
        assert not self.dirty
        self.deadline = time.monotonic() + 5
        (self.root / "named" / "tracked.txt").write_text(CHANGED, encoding="utf-8")
        (self.root / "named" / "new.txt").write_text(UNTRACKED, encoding="utf-8")
        self.dirty = True
        return {"dirty": True, "tracked": CHANGED, "untracked": UNTRACKED}

    def configure(self):
        codex = self.root / "codex"
        catalog = codex / "models.json"
        catalog.write_text(json.dumps({"models": [{
            "slug": "mock-model", "display_name": "Owned no-turn history fixture",
            "supported_reasoning_levels": [], "shell_type": "unified_exec", "visibility": "list",
            "supported_in_api": True, "priority": 1,
            "model_messages": {"instructions_template": "No turn is submitted by this fixture."},
            "support_verbosity": False, "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }]}), encoding="utf-8")
        (codex / "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
model_catalog_json = {json.dumps(str(catalog))}
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
[features]
local_thread_store_compression = false
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
name = "Owned no-turn history fixture"
base_url = "http://127.0.0.1:9/v1"
wire_api = "responses"
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''' + "".join(
            f'\n[projects.{json.dumps(str(self.root / name))}]\ntrust_level = "trusted"\n'
            for name in ("named", "detached", "unborn")
        ), encoding="utf-8")


def emit(value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    assert len(encoded.encode("utf-8")) <= MAX_LINE
    print(encoded, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--git", type=Path, required=True)
    args = parser.parse_args()
    fixture = Fixture(args.root, args.git)
    emit({"pid": os.getpid(), "facts": fixture.prepare()})
    for sequence in range(1, 4):
        line = sys.stdin.buffer.readline(MAX_LINE + 1)
        if not line:
            return
        assert len(line) <= MAX_LINE and line.endswith(b"\n")
        request = json.loads(line)
        assert request == {"op": "dirty"} or request == {"op": "verify"}
        if request["op"] == "dirty":
            result = fixture.change()
        else:
            fixture.deadline = time.monotonic() + 10
            result = fixture.facts()
        emit({"sequence": sequence, "result": result})
    assert not sys.stdin.buffer.readline(1), "Owned helper request count exceeded"


if __name__ == "__main__":
    main()
