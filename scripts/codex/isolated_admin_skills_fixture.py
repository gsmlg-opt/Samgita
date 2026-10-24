#!/usr/bin/env python3
"""Owned Admin skill discovery through stock Codex's private /etc route.

Only this fresh user+mount+net namespace receives the owned etc bind. Never
create or write a host /etc path, run a skill, serve inference or inherit auth.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time
import traceback

# -I excludes the script directory; add only this resolved repository directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_realtime_bem_fixture import SHA, atomic, isolation
from isolated_user_shell_fixture import configure as configure_offline
from private_gateway_fixture import privilege_proof, stop_owned


SYSTEM = b"[skills.bundled]\nenabled = false\n"
SKILL = (b"---\nname: owned-admin-discovery\n"
         b"description: Owned synthetic admin discovery metadata.\n---\n\n"
         b"Inert owned catalog metadata only. No execution is requested.\n")
SKILL_SHA = "bb2b50bc56418c06bd450b1ef6d6ae48d202951f5a243a132cbe0a31ae0f1501"
RELATIVE_SKILL = "codex/skills/owned-admin-discovery/SKILL.md"
NAMES = ("user", "mnt", "net")


def namespaces(pid="self"):
    return {name: os.readlink(f"/proc/{pid}/ns/{name}") for name in NAMES}


def mount_rows():
    rows = []
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        parts = line.split()
        split = parts.index("-")
        rows.append({"id": int(parts[0]), "device": parts[2], "root": parts[3],
                     "target": parts[4], "flags": parts[5].split(","),
                     "propagation": parts[6:split]})
    return rows


def private_mounts():
    assert all(not flag.startswith(("shared:", "master:", "propagate_from:"))
               for row in mount_rows() for flag in row["propagation"]), (
                   "BLOCKED_ENV: recursive private mount propagation required")


def covering_mount(path):
    candidates = [row for row in mount_rows()
                  if path == Path(row["target"]) or Path(row["target"]) in path.parents]
    depth = max(len(Path(row["target"]).parts) for row in candidates)
    deepest = [row for row in candidates if len(Path(row["target"]).parts) == depth]
    assert len(deepest) == 1, "BLOCKED_ENV: ambiguous owned source filesystem mount"
    return deepest[0]


def source_tree(root):
    source = root / "etc"
    expected = {"codex/config.toml": SYSTEM, RELATIVE_SKILL: SKILL}
    expected_dirs = {"codex", "codex/skills", "codex/skills/owned-admin-discovery"}
    actual = set()
    assert source.is_dir() and not source.is_symlink()
    for path in source.rglob("*"):
        info = path.lstat()
        assert info.st_uid == os.geteuid() and not path.is_symlink()
        relative = path.relative_to(source).as_posix()
        actual.add(relative)
        if relative in expected_dirs:
            assert stat.S_ISDIR(info.st_mode)
        else:
            assert relative in expected and stat.S_ISREG(info.st_mode) and info.st_nlink == 1
            assert path.read_bytes() == expected[relative]
    assert actual == expected_dirs | set(expected)
    assert hashlib.sha256(SKILL).hexdigest() == SKILL_SHA
    return expected


def mount_proof(root, mount_id):
    expected = source_tree(root)
    private_mounts()
    rows = [row for row in mount_rows() if row["id"] == mount_id]
    assert len(rows) == 1 and rows[0]["target"] == "/etc"
    assert {"ro", "nodev", "nosuid", "noexec"} <= set(rows[0]["flags"])
    source, mounted = (root / "etc").stat(), Path("/etc").stat()
    assert (source.st_dev, source.st_ino) == (mounted.st_dev, mounted.st_ino)
    # Btrfs stat uses a subvolume device; mountinfo uses the filesystem device.
    # Compare filesystem identities in mountinfo and exact dev/inode via stat.
    source_mount = covering_mount(root / "etc")
    assert rows[0]["device"] == source_mount["device"]
    files = {}
    for relative, expected_bytes in expected.items():
        a, b = root / "etc" / relative, Path("/etc") / relative
        left, right = a.lstat(), b.lstat()
        assert stat.S_ISREG(right.st_mode) and right.st_nlink == 1
        assert (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)
        assert a.read_bytes() == b.read_bytes() == expected_bytes
        files[relative] = {"sha256": hashlib.sha256(expected_bytes).hexdigest(),
                           "bytes": len(expected_bytes), "device": right.st_dev,
                           "inode": right.st_ino}
    return {"mount": rows[0], "source_mount": source_mount,
            "source_stat_device": f"{os.major(source.st_dev)}:{os.minor(source.st_dev)}",
            "etc_device": mounted.st_dev, "etc_inode": mounted.st_ino,
            "files": files, "recursive_private": True}


def process_privileges(pid):
    values = {}
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in {"CapInh", "CapPrm", "CapEff", "CapBnd", "CapAmb", "NoNewPrivs"}:
            values[key] = value.strip()
    assert set(values) == {"CapInh", "CapPrm", "CapEff", "CapBnd", "CapAmb", "NoNewPrivs"}
    assert all(int(value, 16) == 0 for key, value in values.items() if key.startswith("Cap"))
    assert values["NoNewPrivs"] == "1"
    return values


class Fixture:
    def __init__(self, args, proof):
        self.root, self.binary, self.proof = args.root, args.codex, proof
        self.natives, self.records, self.lock = {}, [], threading.RLock()
        self.closed, self.stage = False, 0
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
        self.thread = threading.Thread(
            target=lambda: self.http.serve_forever(poll_interval=0.01), daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.http.server_port}"
        try:
            configure_offline(self.root, self)
            path = self.root / "codex/config.toml"
            body = path.read_text()
            assert "skills.bundled" not in body and body.count("[features]\n") == 1
            body = body.replace("[features]\n", "[features]\nhooks = false\n"
                "remote_models = false\nshell_tool = false\nunified_exec = false\n")
            path.write_text("check_for_update_on_startup = false\nallow_login_shell = false\n"
                            + body + "\n[analytics]\nenabled = false\n")
            self.config = path.read_bytes()
            self.catalog = (self.root / "codex/models.json").read_bytes()
            self.unchanged()
            self.record("fixture_ready", **proof, cache_preseeded=False,
                        inherited_host_credentials=False, model_responses_served=0)
        except BaseException:
            self.close()
            raise

    def record(self, event, **values):
        with self.lock:
            assert len(self.records) < 48, "owned Admin journal bound"
            self.records.append({"event": event, **values})
            atomic(self.root / "journal.json", self.records)

    def state(self):
        atomic(self.root / "state.json", {**self.proof, "controller_pid": os.getpid(),
            "namespace_owner_pid": os.getppid(),
            "native_pids": {name: process.pid for name, process in self.natives.items()},
            "ready": True})

    def unchanged(self):
        assert mount_proof(self.root, self.proof["mounted"]["mount"]["id"]) == self.proof["mounted"]
        assert namespaces() == self.proof["namespaces"]
        assert privilege_proof() == self.proof["privileges"]
        assert (self.root / "codex/config.toml").read_bytes() == self.config
        assert (self.root / "codex/models.json").read_bytes() == self.catalog
        for relative in ["codex/auth.json", "codex/skills/.system",
                         "home/.agents/skills", "workspace/.agents/skills", "workspace/.codex"]:
            assert not (self.root / relative).exists()
        assert not any(row["event"] == "forbidden_http" for row in self.records)

    def start(self, name):
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
        arguments = [str(self.binary), "app-server", "--listen", "unix://" + str(path)]
        with (self.root / f"native-{name}-stderr.log").open("wb") as stderr:
            process = subprocess.Popen(arguments, cwd=self.root / "workspace",
                env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=stderr)
        self.natives[name] = process
        self.state()
        self.record("native_started", name=name, pid=process.pid, arguments=arguments,
                    bundled_override=False)
        deadline = time.monotonic() + 5
        while not path.exists():
            assert process.poll() is None, "BLOCKED_ENV: owned Admin native exited"
            assert time.monotonic() < deadline, "BLOCKED_ENV: owned Admin startup deadline"
            time.sleep(0.01)
        assert namespaces(process.pid) == self.proof["namespaces"]
        assert process_privileges(process.pid) == self.proof["privileges"]
        self.record("native_ready", name=name, namespaces=namespaces(process.pid),
                    privileges=process_privileges(process.pid))

    def snapshot(self, name):
        self.unchanged()
        atomic(self.root / f"snapshot-{name}.json", {
            "mounted": self.proof["mounted"], "system_cache_absent": True,
            "auth_absent": True, "user_bundle_override": False, "cli_bundle_override": False})
        self.record("discovery_snapshot", name=name)

    def control(self, message):
        assert set(message) == {"id", "op"} and not self.closed
        assert isinstance(message["id"], str) and 0 < len(message["id"]) <= 80
        op = message["op"]
        if op == "snapshotInitial":
            assert self.stage == 0
            self.snapshot("initial")
            self.stage = 1
        elif op == "snapshotReloaded":
            assert self.stage == 1
            self.snapshot("reloaded")
            self.stage = 2
        elif op == "restart":
            assert self.stage == 2
            self.stop("initial")
            self.start("restarted")
            self.stage = 3
        elif op == "snapshotRestarted":
            assert self.stage == 3
            self.snapshot("restarted")
            self.stage = 4
        elif op == "close":
            assert self.stage == 4
            self.unchanged()
            self.close()
        else:
            raise AssertionError("unapproved owned control")
        self.record("control_done", id=message["id"], op=op)

    def stop(self, name, deadline=None):
        process = self.natives[name]
        stop_owned(process, deadline)
        self.record("native_stopped", name=name, pid=process.pid)

    def close(self):
        if not self.closed:
            self.closed = True
            deadline = time.monotonic() + 0.75
            failures = []
            try:
                for name, process in reversed(list(self.natives.items())):
                    if process.poll() is None:
                        try:
                            self.stop(name, deadline)
                        except BaseException as error:
                            failures.append(error)
                    else:
                        process.wait()
            finally:
                self.http.shutdown()
                self.http.server_close()
                self.thread.join(max(0.001, deadline - time.monotonic()))
                assert not self.thread.is_alive(), "owned reject-only cleanup deadline"
            if failures:
                raise failures[0]
            self.record("fixture_closed")


def run(args):
    assert not args.root.is_symlink()
    args.root, args.codex = args.root.resolve(strict=True), args.codex.resolve(strict=True)
    assert args.root.parent == Path("/tmp") and args.root.name.startswith("samgita-admin-skills-")
    assert hashlib.sha256(args.codex.read_bytes()).hexdigest() == SHA
    for name in ["home", "codex", "workspace", "tmp"]:
        assert (args.root / name).is_dir() and not (args.root / name).is_symlink()
    for key, relative in [("HOME", "home"), ("CODEX_HOME", "codex"), ("TMPDIR", "tmp")]:
        assert os.environ[key] == str(args.root / relative)
    assert Path("/etc").is_dir() and not Path("/etc").is_symlink()
    argv = ["--root", str(args.root), "--codex", str(args.codex)]
    if not args.inside:
        assert sys.platform == "linux" and os.geteuid() != 0, "BLOCKED_ENV: unprivileged Linux caller"
        assert set(path.name for path in args.root.iterdir()) == {"home", "codex", "workspace", "tmp"}
        assert args.root.stat().st_uid == os.geteuid()
        for path in args.root.iterdir():
            assert path.stat().st_uid == os.geteuid() and not any(path.iterdir())
        for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
            assert not Path("/etc/codex", name).exists(), "BLOCKED_ENV: host Codex configuration"
        tools = {name: shutil.which(name) for name in ["unshare", "ip", "mount", "setpriv"]}
        assert all(tools.values()), "BLOCKED_ENV: namespace/mount/privilege tools"
        parent = {"namespaces": namespaces(), "caller_uid": os.geteuid(),
                  "etc_device": Path("/etc").stat().st_dev, "etc_inode": Path("/etc").stat().st_ino}
        atomic(args.root / "parent-proof.json", parent)
        os.execv(tools["unshare"], [tools["unshare"], "--user", "--map-root-user",
            "--mount", "--net", "--fork", "--kill-child=TERM", sys.executable, "-I",
            str(Path(__file__).resolve()), *argv, "--inside"])
    parent = json.loads((args.root / "parent-proof.json").read_text())
    assert namespaces() != parent["namespaces"]
    assert all(namespaces()[name] != parent["namespaces"][name] for name in NAMES)
    assert os.geteuid() == 0, "BLOCKED_ENV: mapped private root required"
    assert [list(map(int, line.split())) for line in Path("/proc/self/uid_map").read_text().splitlines()] == [
        [0, parent["caller_uid"], 1]]
    if not args.unprivileged:
        subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
        network = isolation(parent["namespaces"]["net"])
        source = args.root / "etc"
        assert not source.exists()
        (source / "codex/skills/owned-admin-discovery").mkdir(parents=True)
        (source / "codex/config.toml").write_bytes(SYSTEM)
        (source / RELATIVE_SKILL).write_bytes(SKILL)
        source_tree(args.root)
        subprocess.run(["mount", "--make-rprivate", "/"], check=True, timeout=5)
        private_mounts()
        before_ids = {row["id"] for row in mount_rows()}
        # Bind the entire owned tree onto the EXISTING target. No /etc mkdir/write.
        subprocess.run(["mount", "--bind", str(source), "/etc"], check=True, timeout=5)
        subprocess.run(["mount", "-o", "remount,bind,ro,nodev,nosuid,noexec", "/etc"],
                       check=True, timeout=5)
        covering = [row for row in mount_rows() if row["target"] == "/etc" and row["id"] not in before_ids]
        assert len(covering) == 1, "BLOCKED_ENV: owned covering /etc mount"
        proof = {"parent_namespaces": parent["namespaces"], "namespaces": namespaces(),
                 **network, "mounted": mount_proof(args.root, covering[0]["id"]),
                 "caller_uid": parent["caller_uid"], "binary_sha256": SHA}
        atomic(args.root / "setup-proof.json", proof)
        setpriv = shutil.which("setpriv")
        assert setpriv, "BLOCKED_ENV: setpriv after private /etc"
        os.execv(setpriv, [setpriv, "--bounding-set=-all", "--inh-caps=-all",
            "--ambient-caps=-all", "--securebits=+noroot,+noroot_locked", "--no-new-privs",
            sys.executable, "-I", str(Path(__file__).resolve()), *argv, "--inside", "--unprivileged"])
    proof = json.loads((args.root / "setup-proof.json").read_text())
    assert namespaces() == proof["namespaces"]
    assert mount_proof(args.root, proof["mounted"]["mount"]["id"]) == proof["mounted"]
    proof["privileges"] = privilege_proof()
    fixture = None

    def terminate(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    try:
        fixture = Fixture(args, proof)
        fixture.start("initial")
        for line in sys.stdin:
            assert len(line.encode()) <= 1024
            fixture.control(json.loads(line))
            if fixture.closed:
                break
    except BaseException as error:
        if fixture is not None and not isinstance(error, SystemExit):
            fixture.record("fixture_error", error_type=type(error).__name__)
        raise
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if fixture is not None:
            fixture.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--unprivileged", action="store_true")
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        atomic(args.root / "startup-failure.json",
               {"status": "BLOCKED_ENV", "stage": "owned Admin namespace fixture",
                "error_type": type(error).__name__,
                "frames": [{"file": Path(frame.filename).name, "line": frame.lineno,
                            "function": frame.name}
                           for frame in traceback.extract_tb(error.__traceback__)]})
        raise


if __name__ == "__main__":
    main()
