#!/usr/bin/env python3
"""Native bundled-skill discovery with an owned shared cache and no inference.

Only the immutable binary writes skills/.system. Cache controls read and hash
native-created files; no fixture skill is installed, invoked or edited.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time

from isolated_realtime_bem_fixture import SHA, atomic, isolation
from isolated_user_shell_fixture import configure as configure_offline
from private_gateway_fixture import stop_owned


SKILL_SHA = "07079efd0dc76f05fade424e5dfb048dce1de2df7626e1a4f56292a4f3f92228"


def traceback_chain(error):
    frame = error.__traceback__
    while frame is not None:
        yield frame
        frame = frame.tb_next


class Fixture:
    def __init__(self, args, proof):
        self.root, self.binary, self.proof = args.root, args.codex, proof
        self.natives, self.records, self.lock = {}, [], threading.RLock()
        self.closed, self.stage, self.cache = False, 0, None
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(0.1)

            def log_message(self, *_args):
                pass

            def reject(self):
                fixture.record("forbidden_http", method=self.command, path=self.path)
                self.send_response(403)
                self.send_header("Content-Length", "0")
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True

            do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = reject

        self.http = HTTPServer(("127.0.0.1", 0), Handler)
        self.http.timeout = 0.1
        self.thread = threading.Thread(
            target=lambda: self.http.serve_forever(poll_interval=0.01), daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.http.server_port}"
        try:
            # Reuse the established offline catalog/config helper, without
            # starting a model provider or serving any model response.
            configure_offline(self.root, self)
            path = self.root / "codex/config.toml"
            body = path.read_text()
            assert body.count("[features]\n") == 1
            body = body.replace("[features]\n", "[features]\nhooks = false\n"
                "remote_models = false\nshell_tool = false\nunified_exec = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                            + body + "\n[analytics]\nenabled = false\n")
            self.config = path.read_bytes()
            self.catalog = (self.root / "codex/models.json").read_bytes()
            assert not (self.root / "codex/skills/.system").exists()
            assert not (self.root / "codex/auth.json").exists()
            self.record("fixture_ready", **proof, cache_preseeded=False,
                        inherited_host_credentials=False, model_responses_served=0)
        except BaseException:
            self.close()
            raise

    def record(self, event, **values):
        with self.lock:
            assert len(self.records) < 48, "owned system-skill journal bound"
            self.records.append({"event": event, **values})
            atomic(self.root / "journal.json", self.records)

    def state(self):
        atomic(self.root / "state.json", {**self.proof, "controller_pid": os.getpid(),
            "namespace_owner_pid": os.getppid(),
            "native_pids": {name: process.pid for name, process in self.natives.items()},
            "ready": True})

    def unchanged(self):
        assert (self.root / "codex/config.toml").read_bytes() == self.config
        assert (self.root / "codex/models.json").read_bytes() == self.catalog
        assert not (self.root / "codex/auth.json").exists()
        assert not any(row["event"] == "forbidden_http" for row in self.records)

    def start(self, name, bundled):
        assert name not in self.natives and not self.closed
        self.unchanged()
        path = self.root / f"native-{name}.sock"
        assert not path.exists()
        environment = {
            "HOME": str(self.root / "home"), "CODEX_HOME": str(self.root / "codex"),
            "TMPDIR": str(self.root / "tmp"), "PATH": "/usr/bin:/bin",
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "CODEX_EXEC_SERVER_URL": "none", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
        }
        override = "skills.bundled.enabled=" + ("true" if bundled else "false")
        arguments = [str(self.binary), "-c", override, "app-server",
                     "--listen", "unix://" + str(path)]
        with (self.root / f"native-{name}-stderr.log").open("wb") as stderr:
            process = subprocess.Popen(arguments, cwd=self.root / "workspace",
                env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=stderr)
        self.natives[name] = process
        self.state()
        self.record("native_started", name=name, pid=process.pid, bundled_override=override)
        deadline = time.monotonic() + 5
        while not path.exists():
            assert process.poll() is None, "owned system-skill startup exited"
            assert time.monotonic() < deadline, "owned system-skill startup deadline"
            time.sleep(0.01)
        assert os.readlink(f"/proc/{process.pid}/ns/net") == self.proof["namespace"]
        self.record("native_ready", name=name)

    def snapshot(self, name):
        self.unchanged()
        cache = self.root / "codex/skills/.system"
        assert cache.is_dir() and not cache.is_symlink()
        files, total = {}, 0
        for path in sorted(cache.rglob("*")):
            assert not path.is_symlink(), "unexpected symlink in owned System cache"
            assert path.is_dir() or path.is_file(), "unexpected System cache entry type"
            if path.is_file():
                size = path.stat().st_size
                total += size
                assert size <= 1_048_576 and total <= 4_194_304 and len(files) < 128
                files[path.relative_to(cache).as_posix()] = {
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": size}
        assert files["review-agent/SKILL.md"]["sha256"] == SKILL_SHA
        assert ".codex-system-skills.marker" in files
        if self.cache is None:
            self.cache = files
        else:
            assert files == self.cache, "owned System cache changed across disabled/reload control"
        atomic(self.root / f"cache-{name}.json", files)
        self.record("cache_snapshot", name=name, files=len(files), bytes=total)

    def control(self, message):
        assert set(message) == {"id", "op"} and not self.closed
        assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
        op = message["op"]
        if op == "snapshotEnabled":
            assert self.stage == 0
            self.snapshot("enabled")
            self.stage = 1
        elif op == "startDisabled":
            assert self.stage == 1 and self.natives["enabled"].poll() is None
            self.start("disabled", False)
            self.stage = 2
        elif op == "snapshotDisabled":
            assert self.stage == 2
            self.snapshot("disabled")
            self.stage = 3
        elif op == "snapshotReloaded":
            assert self.stage == 3 and self.natives["enabled"].poll() is None
            self.snapshot("reloaded")
            self.stage = 4
        elif op == "close":
            assert self.stage == 4
            self.unchanged()
            self.close()
        else:
            raise AssertionError("unapproved owned control")
        self.record("control_done", id=message["id"], op=op)

    def close(self):
        if not self.closed:
            self.closed = True
            deadline = time.monotonic() + 0.75
            failures = []
            try:
                for name, process in reversed(list(self.natives.items())):
                    try:
                        stop_owned(process, deadline)
                        self.record("native_stopped", name=name, pid=process.pid)
                    except BaseException as error:
                        failures.append(error)
            finally:
                self.http.shutdown()
                self.http.server_close()
                self.thread.join(max(0.001, deadline - time.monotonic()))
                assert not self.thread.is_alive(), "owned reject-only HTTP cleanup deadline"
            if failures:
                raise failures[0]
            self.record("fixture_closed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA
    for name in ["home", "codex", "workspace", "tmp"]:
        path = args.root / name
        assert path.is_dir() and not path.is_symlink()
        assert not any(path.iterdir()), "owned system-skill root must start empty"
    assert os.environ["HOME"] == str(args.root / "home")
    assert os.environ["CODEX_HOME"] == str(args.root / "codex")
    assert os.environ["TMPDIR"] == str(args.root / "tmp")
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host system configuration"
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
        fixture.start("enabled", True)
        for line in sys.stdin:
            assert len(line.encode()) <= 1024
            fixture.control(json.loads(line))
    except BaseException as error:
        if fixture is not None and not isinstance(error, SystemExit):
            fixture.record("fixture_error", stage="controller",
                           error_type=type(error).__name__,
                           source_lines=[frame.tb_lineno for frame in traceback_chain(error)])
        raise
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


if __name__ == "__main__":
    main()
