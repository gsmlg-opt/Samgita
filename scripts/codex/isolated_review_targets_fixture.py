#!/usr/bin/env python3
"""Owned Git targets plus fixed no-tool Responses around unmodified pinned Codex.

Proves target normalization, prompt routing and native lifecycle only. The fixed
model does not inspect diffs, execute tools, or establish review quality.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

from isolated_realtime_bem_fixture import Fixture as BemFixture, SHA, atomic, isolation
from isolated_review_delivery_fixture import ReviewProvider
from isolated_tool_interactions_fixture import configure
from model_fixture import ModelFixture


SCENARIOS = ["uncommitted", "base", "commit-title", "commit-omitted", "commit-null",
             "commit-blank", "blank-branch", "blank-sha"]
TITLE = "Owned commit λ🙂"


class OwnedRepository:
    def __init__(self, root):
        self.root, self.path = root, root / "workspace"
        self.environment = {key: os.environ[key] for key in
                            ["HOME", "CODEX_HOME", "TMPDIR", "PATH", "NO_COLOR"]}
        self.environment.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                                 "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0",
                                 "GIT_AUTHOR_NAME": "Owned fixture", "GIT_COMMITTER_NAME": "Owned fixture",
                                 "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                                 "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
                                 "GIT_AUTHOR_DATE": "2001-01-01T00:00:00+0000",
                                 "GIT_COMMITTER_DATE": "2001-01-01T00:00:00+0000"})
        self.hooks = root / "empty-hooks"
        self.hooks.mkdir()
        self.git("init", "--initial-branch=main", "--template=")
        for key, value in [("core.hooksPath", str(self.hooks)), ("commit.gpgSign", "false"),
                           ("tag.gpgSign", "false"), ("protocol.file.allow", "never")]:
            self.git("config", "--local", key, value)
        (self.path / "tracked.txt").write_bytes(b"owned root\n")
        (self.path / "staged.txt").write_bytes(b"owned initial index\n")
        self.git("add", "--", "tracked.txt", "staged.txt")
        self.git("commit", "-m", "Owned root")
        root_sha = self.git("rev-parse", "HEAD").strip()
        (self.path / "base.txt").write_bytes(b"owned base branch\n")
        self.git("add", "--", "base.txt")
        self.git("commit", "-m", "Owned base")
        base_sha = self.git("rev-parse", "HEAD").strip()
        self.git("checkout", "-b", "feature", root_sha)
        (self.path / "feature.txt").write_bytes(b"owned feature branch\n")
        self.git("add", "--", "feature.txt")
        self.git("commit", "-m", "Owned feature")
        head_sha = self.git("rev-parse", "HEAD").strip()
        assert len({root_sha, base_sha, head_sha}) == 3
        assert self.git("merge-base", "HEAD", "main").strip() == root_sha
        (self.path / "staged.txt").write_bytes(b"owned staged sentinel\n")
        self.git("add", "--", "staged.txt")
        (self.path / "tracked.txt").write_bytes(b"owned root\nowned unstaged sentinel\n")
        (self.path / "untracked.txt").write_bytes(b"owned untracked sentinel\n")
        assert self.git("remote", "-v") == ""
        self.initial = self.snapshot()
        assert "M  staged.txt\u0000" in self.initial["status"]
        assert " M tracked.txt\u0000" in self.initial["status"]
        assert "?? untracked.txt\u0000" in self.initial["status"]
        atomic(root / "git-fixture.json", {"rootSHA": root_sha, "baseSHA": base_sha,
                                          "headSHA": head_sha, "initial": self.initial})
        atomic(root / "git-verifications.json", [])
        self.verifications = []

    def git(self, *arguments):
        result = subprocess.run(["git", "-c", "core.hooksPath=" + str(self.hooks),
                                 "-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false",
                                 *arguments], cwd=self.path, env=self.environment,
                                check=True, timeout=5, capture_output=True)
        return result.stdout.decode()

    def snapshot(self):
        files = {}
        for path in sorted(self.path.iterdir()):
            if path.name != ".git":
                assert path.is_file() and not path.is_symlink(), "Unexpected workspace path"
                files[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        return {"head": self.git("rev-parse", "HEAD").strip(),
                "refs": self.git("for-each-ref", "--format=%(refname) %(objectname)"),
                "index": self.git("ls-files", "--stage", "-z"),
                "status": self.git("status", "--porcelain=v1", "-z", "--untracked-files=all"),
                "staged": self.git("diff", "--cached", "--binary", "--no-ext-diff", "--no-textconv"),
                "unstaged": self.git("diff", "--binary", "--no-ext-diff", "--no-textconv"),
                "remotes": self.git("remote", "-v"), "files": files}

    def verify(self):
        assert self.snapshot() == self.initial, "Owned repository changed during native review"
        assert list(self.hooks.iterdir()) == []
        self.verifications.append({"index": len(self.verifications) + 1, "unchanged": True})
        atomic(self.root / "git-verifications.json", self.verifications)


def expected_prompt(scenario, repository):
    facts = json.loads((repository.root / "git-fixture.json").read_text())
    if scenario == "uncommitted":
        return ("Review the current code changes (staged, unstaged, and untracked files) "
                "and provide prioritized findings.")
    if scenario == "base":
        sha = facts["rootSHA"]
        return ("Review the code changes against the base branch 'main'. The merge base commit "
                f"for this comparison is {sha}. Run `git diff {sha}` to inspect the changes "
                "relative to main. Provide prioritized, actionable findings.")
    assert scenario.startswith("commit-")
    title = f' ("{TITLE}")' if scenario == "commit-title" else ""
    return (f'Review the code changes introduced by commit {facts["baseSHA"]}{title}. '
            "Provide prioritized, actionable findings.")


class TargetProvider(ReviewProvider):
    def __init__(self, root, scenario, repository):
        super().__init__(root, "inline")
        self.target_scenario, self.repository = scenario, repository

    def write_response(self, handler, index, request):
        assert self.target_scenario not in {"blank-branch", "blank-sha"}, "Rejected target reached model"
        assert index == 1 and request["model"] == "mock-model", "Unexpected model request"
        assert not any(item.get("type") in {"function_call", "function_call_output"}
                       for item in request["input"]), "Unexpected tool execution"
        texts = [part["text"] for item in request["input"] if item.get("role") == "user"
                 for part in item.get("content", []) if part.get("type") == "input_text"]
        assert expected_prompt(self.target_scenario, self.repository) in texts, "Wrong core target prompt"
        self.repository.verify()
        self.record("review_pending", index=index)
        assert self.release.wait(timeout=10), "Explicit review release deadline"
        if self.closing.is_set():
            return
        self.record("response_released", index=index)
        ModelFixture.write_response(self, handler, index, request)


class Fixture(BemFixture):
    def __init__(self, args, proof):
        super().__init__(argparse.Namespace(root=args.root, codex=args.codex, scenario="markdown"), proof)
        try:
            self.provider.close()
            assert self.provider.requests == [] and self.native is None
            self.repository = OwnedRepository(self.root)
            self.provider = TargetProvider(self.root, args.scenario, self.repository).start()
            configure(self.root, self.provider)
            path = self.root / "codex" / "config.toml"
            config = path.read_text().replace("[features]\n",
                "[features]\nenable_request_compression = false\n")
            path.write_text(config + "\n[analytics]\nenabled = false\n")
            self.record("review_provider_ready", scenario=args.scenario, source_provider_requests=0,
                        request_auth="none", output="fixed_assistant_messages_only")

        except BaseException:
            self.close()
            raise

    def control(self, message):
        if message.get("op") in {"releaseReview", "verifyRepository"}:
            assert set(message) == {"id", "op"} and not self.closed
            assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
            if message["op"] == "releaseReview":
                assert not self.provider.release.is_set()
                assert sum(row["event"] == "review_pending" for row in self.provider.records) == 1
                self.provider.release.set()
            else:
                self.repository.verify()
            self.record("control_done", id=message["id"], op=message["op"])
        else:
            super().control(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=SCENARIOS)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA
    if not args.inside:
        assert sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip", "git"])
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
