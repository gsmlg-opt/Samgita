"""Private real Secret Service and owned loopback OAuth dependencies.

Shares validation/configuration with the failure profile. Only native Codex
emits app-server replies; gdbus inspects the real GNOME daemon's metadata.
"""
import argparse
import base64
import hashlib
from html import escape
from http.client import HTTPConnection
import importlib.util
import os
from pathlib import Path
import re
import selectors
import shutil
import socket
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlencode, urlparse

sys.dont_write_bytecode = True

ACCESS = "OWNED_SYNTHETIC_GATEWAY_ACCESS"
REFRESH = "OWNED_SYNTHETIC_GATEWAY_REFRESH"


def require(condition, label):
    if not condition:
        raise AssertionError(label)


def load_base(path):
    require(hashlib.sha256(path.read_bytes()).hexdigest() ==
            "d547f4f45842d604484d00773d0d88df1d41507e4a4aa9fb305849a4052206be",
            "reviewed existing fixture snapshot changed")
    spec = importlib.util.spec_from_file_location("owned_gateway_base", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stop_owned(process, deadline=None):
    """Reap only the direct Popen child; never select a PID by process name."""
    if process is None:
        return
    if deadline is None:
        deadline = time.monotonic() + 0.75
    def remaining(cap):
        return max(0.001, min(cap, deadline - time.monotonic()))
    if process.poll() is None:
        process.terminate()
    try:
        process.wait(timeout=remaining(0.2))
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=remaining(0.1))
    require(time.monotonic() <= deadline, 'owned child cleanup exceeded shared deadline')


def privilege_proof():
    status = {}
    for line in Path('/proc/self/status').read_text().splitlines():
        key, _, value = line.partition(':')
        if key in {'CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb', 'NoNewPrivs'}:
            status[key] = value.strip()
    require(set(status) == {'CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb', 'NoNewPrivs'},
            'Linux privilege metadata unavailable')
    require(all(int(status[key], 16) == 0 for key in status if key.startswith('Cap')),
            'namespace capabilities must all be zero before services')
    require(status['NoNewPrivs'] == '1', 'no_new_privs required before services')
    return status


class PrivateStack:
    def __init__(self, args, base):
        self.args, self.base = args, base
        self.bus, self.keyring = None, None
        self.logs = []
        self.env = {
            "HOME": str(args.root / "home"), "CODEX_HOME": str(args.root / "codex"),
            "TMPDIR": str(args.root / "tmp"), "PATH": os.environ["PATH"],
            "NO_PROXY": "*", "no_proxy": "*", "CODEX_DISABLE_REMOTE_CONTROL": "1",
            "NO_COLOR": "1", "RUST_LOG": "off", "PYTHONDONTWRITEBYTECODE": "1",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "GSETTINGS_BACKEND": "memory",
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(args.root / "runtime/no-system-bus"),
            "GNOME_KEYRING_CONTROL": str(args.root / "control"),
            "XDG_RUNTIME_DIR": str(args.root / "runtime"),
            "XDG_DATA_HOME": str(args.root / "data"),
            "XDG_CONFIG_HOME": str(args.root / "config"),
            "XDG_CACHE_HOME": str(args.root / "cache"),
            "XDG_DATA_DIRS": str(args.root / "data-dirs"),
            "XDG_CONFIG_DIRS": str(args.root / "config-dirs"),
        }
        self.password = None

    def log(self, name):
        handle = (self.args.root / name).open("wb")
        self.logs.append(handle)
        return handle

    def start(self):
        root = self.args.root
        privilege_proof()
        version = subprocess.run([str(self.args.gnome_keyring_daemon), '--version'],
            env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=2, check=True)
        require(len(version.stdout) <= 4096 and len(version.stderr) <= 4096,
                'real keyring version metadata overflow')
        version_line = version.stdout.decode().splitlines()[0]
        require(re.fullmatch(r'gnome-keyring-daemon: [0-9][0-9A-Za-z.+~_-]*', version_line) is not None,
                'real keyring version metadata unavailable')
        self.daemon_version = version_line.partition(': ')[2]
        address = "unix:path=" + str(root / "runtime/bus")
        require(len(os.fsencode(root / "runtime/bus")) < 100, "owned Unix socket path too long")
        config = root / "bus.conf"
        config.write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>''' + escape(address) + '''</listen>
<auth>EXTERNAL</auth><policy context="default"><allow user="*"/>
<allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>
</policy></busconfig>
''')
        self.bus = subprocess.Popen([str(self.args.dbus_daemon), "--config-file=" + str(config),
            "--nofork", "--print-address=1", "--print-pid=1"], env=self.env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=self.log("bus-stderr.log"))
        # Do not block on readline if bus startup fails before producing output.
        selector = selectors.DefaultSelector()
        selector.register(self.bus.stdout, selectors.EVENT_READ)
        data, deadline = b"", time.monotonic() + 5
        try:
            while data.count(b"\n") < 2 and time.monotonic() < deadline:
                for key, _ in selector.select(max(0, deadline - time.monotonic())):
                    chunk = os.read(key.fileobj.fileno(), 4096)
                    require(bool(chunk), "private bus exited before readiness")
                    data += chunk
                    require(len(data) <= 4096, "private bus readiness overflow")
            lines = data.decode().splitlines()
            require(len(lines) == 2, "private bus readiness deadline")
            require(lines[0].split(",guid=", 1)[0] == address, "private bus address mismatch")
            require(lines[1] == str(self.bus.pid), "private nofork bus PID mismatch")
        finally:
            selector.close()
        self.env["DBUS_SESSION_BUS_ADDRESS"] = lines[0]
        self.password = base64.urlsafe_b64encode(os.urandom(32))
        self.keyring = subprocess.Popen([str(self.args.gnome_keyring_daemon), "--foreground",
            "--components=secrets", "--control-directory=" + str(root / "control"), "--unlock"],
            env=self.env, stdin=subprocess.PIPE, stdout=self.log("keyring-stdout.log"),
            stderr=self.log("keyring-stderr.log"), cwd=root)
        self.keyring.stdin.write(self.password)
        self.keyring.stdin.close()
        # Never record this password or a raw secret; only metadata is queried.
        deadline = time.monotonic() + 8
        last = None
        while time.monotonic() < deadline:
            require(self.keyring.poll() is None and self.bus.poll() is None,
                    "owned bus/keyring exited during preflight")
            try:
                owner = self.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus.GetNameOwner", "org.freedesktop.secrets")
                names = re.findall(r"'(:[0-9]+\.[0-9]+)'", owner)
                require(len(names) == 1, "real Secret Service owner missing")
                pid = self.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus.GetConnectionUnixProcessID", names[0])
                require(re.fullmatch(r"\(uint32 " + str(self.keyring.pid) + r",\)\s*", pid) is not None,
                        "Secret Service owner is not the owned foreground daemon")
                alias = self.call("org.freedesktop.secrets", "/org/freedesktop/secrets",
                    "org.freedesktop.Secret.Service.ReadAlias", "default")
                require(alias.strip() == "(objectpath '/org/freedesktop/secrets/collection/login',)",
                        "owned default alias is not login collection")
                locked = self.call("org.freedesktop.secrets", "/org/freedesktop/secrets/collection/login",
                    "org.freedesktop.DBus.Properties.Get", "org.freedesktop.Secret.Collection", "Locked")
                require(locked.strip() == "(<false>,)", "owned login collection is locked")
                return {"service_pid": self.keyring.pid, "bus_pid": self.bus.pid,
                        "real_secret_service": True, "login_unlocked": True,
                        "host_bus_inherited": False, "daemon_version": self.daemon_version,
                        "daemon_sha256": self.args.keyring_sha256}
            except (AssertionError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                last = type(error).__name__
                time.sleep(0.05)
        raise AssertionError("private real-keyring preflight deadline: " + str(last))

    def call(self, destination, path, method, *parameters):
        result = subprocess.run([str(self.args.gdbus), "call", "--address",
            self.env["DBUS_SESSION_BUS_ADDRESS"], "--dest", destination,
            "--object-path", path, "--method", method, *parameters], env=self.env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=2, check=True)
        require(len(result.stdout) <= 4096 and len(result.stderr) <= 4096, "gdbus metadata overflow")
        return result.stdout.decode()

    def native_item(self):
        account = "secrets|" + hashlib.sha256(os.fsencode(self.args.root / "codex")).hexdigest()[:16] + "|gateway-oauth"
        attributes = "{'service': 'codex', 'username': '" + account + "', 'target': 'default'}"
        result = self.call("org.freedesktop.secrets", "/org/freedesktop/secrets",
            "org.freedesktop.Secret.Service.SearchItems", attributes)
        match = re.fullmatch(r"\(\[objectpath '(/org/freedesktop/secrets/collection/login/[^']+)'\], @ao \[\]\)\s*", result)
        require(match is not None, "expected exactly one unlocked native keyring item")
        return match.group(1)

    def close(self, deadline=None):
        # Both Popen children are recorded before any preflight can fail.
        errors = []
        if deadline is None:
            deadline = time.monotonic() + 0.75
        for process in [self.keyring, self.bus]:
            try:
                stop_owned(process, deadline)
            except Exception as error:
                errors.append(type(error).__name__)
        self.password = None
        for handle in self.logs:
            handle.close()
        require(not errors, "owned stack cleanup incomplete: " + repr(errors))


def success_issuer(args, base, proof):
    fixture = base.Fixture(args, proof)
    handler = fixture.server.RequestHandlerClass

    def token(self):
        try:
            require(self.path == "/token", "unexpected token path")
            size = int(self.headers.get("Content-Length", "0"))
            require(0 < size <= 8192, "token form size")
            require(self.headers.get("Authorization") is None, "unexpected authorization")
            require(self.headers.get("ChatGPT-Account-ID") is None, "unexpected primary account")
            require(self.headers.get("Host") == f"127.0.0.1:{fixture.server.server_port}", "token host")
            require(self.headers.get_content_type() == "application/x-www-form-urlencoded", "token content type")
            form = parse_qs(self.rfile.read(size).decode(), keep_blank_values=True)
            require(set(form) == {"grant_type", "code", "client_id", "redirect_uri", "code_verifier"}, "token form keys")
            require(form["grant_type"] == ["authorization_code"] and form["code"] == ["owned-accepted-code"], "owned code grant")
            require(form["client_id"] == ["owned-gateway-client"] and form["redirect_uri"] == [fixture.redirect], "owned client and redirect")
            challenge = base64.urlsafe_b64encode(hashlib.sha256(form["code_verifier"][0].encode()).digest()).decode().rstrip("=")
            require(challenge == fixture.challenge, "native S256 PKCE mismatch")
            fixture.exchanges += 1
            require(fixture.exchanges == 1, "duplicate token exchange")
            fixture.record("token_exchange", pkce_verified=True, body_verified=True,
                           authorization_absent=True, host_verified=True, status=200)
            self.reply(200, {"access_token": ACCESS, "refresh_token": REFRESH,
                            "token_type": "Bearer", "expires_in": 3600})
        except Exception as error:
            fixture.record("fixture_error", stage="success-token", error_type=type(error).__name__)
            self.reply(400, {})

    handler.do_POST = token
    # Reuse exact native handoff validation, but keep callback under the profile's
    # control until the duplicate-login rejection has actually been observed.
    def observe(value):
        params = value.get("params", {})
        if value.get("method") == base.CHANGED and params.get("authUrl"):
            original = args.scenario
            try:
                args.scenario = "cancel"
                fixture.native_output(value)
            finally:
                args.scenario = original
            fixture.state = parse_qs(urlparse(params["authUrl"]).query)["state"][0]
        else:
            fixture.native_output(value)
    fixture.observe = observe

    def callback():
        parsed = urlparse(fixture.redirect)
        connection = HTTPConnection("127.0.0.1", parsed.port, timeout=5)
        try:
            connection.request("GET", parsed.path + "?" + urlencode({"state": fixture.state, "code": "owned-accepted-code"}))
            response = connection.getresponse()
            require(response.status == 200 and len(response.read(65537)) <= 65536, "native callback response")
            fixture.record("native_callback", status=200, state_from_native=True)
        finally:
            connection.close()
    fixture.callback = callback
    return fixture


def stop_issuer(issuer, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + 0.75
    issuer.closing.set()
    with issuer.lock:
        peers = list(issuer.peer_sockets)
    for peer in peers:
        try:
            peer.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
    issuer.server.shutdown()
    issuer.server.server_close()
    issuer.thread.join(timeout=max(0, min(0.1, deadline-time.monotonic())))
    require(not issuer.thread.is_alive(), "issuer server cleanup incomplete")
    with issuer.lock:
        workers = list(issuer.peer_threads)
    for worker in workers:
        worker.join(timeout=max(0, deadline - time.monotonic()))
    require(not any(worker.is_alive() for worker in workers), "issuer worker cleanup incomplete")
    require(time.monotonic() <= deadline, 'issuer cleanup exceeded shared deadline')


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--codex", required=True, type=Path)
    parser.add_argument("--base-fixture", required=True, type=Path)
    parser.add_argument("--gnome-keyring-daemon", type=Path, default=os.environ.get("GNOME_KEYRING_DAEMON"))
    parser.add_argument("--keyring-sha256", default=os.environ.get("GNOME_KEYRING_DAEMON_SHA256"))
    parser.add_argument("--dbus-daemon", required=True, type=Path)
    parser.add_argument("--gdbus", required=True, type=Path)
    parser.add_argument("--setpriv", required=True, type=Path)
    parser.add_argument("--inside", action="store_true")
    parser.add_argument("--unprivileged", action="store_true")
    parser.add_argument("--parent-netns")
    args = parser.parse_args()
    require(args.gnome_keyring_daemon is not None, "GNOME_KEYRING_DAEMON or explicit option required")
    require(not args.root.is_symlink(), "disposable root must not be a symlink")
    for name in ["root", "codex", "base_fixture", "gnome_keyring_daemon", "dbus_daemon", "gdbus", "setpriv"]:
        setattr(args, name, getattr(args, name).resolve(strict=True))
    require(args.root.is_dir() and not args.root.is_symlink(), "owned root required")
    for name in ["codex", "gnome_keyring_daemon", "dbus_daemon", "gdbus", "setpriv"]:
        require(getattr(args, name).is_file() and os.access(getattr(args, name), os.X_OK),
                "BLOCKED_ENV: explicit executable unavailable: " + name)
    # Parent must allocate this explicit root; never accept a populated directory.
    require(not any(args.root.iterdir()), "candidate requires an empty disposable root") if not args.inside else None
    base = load_base(args.base_fixture)
    require(hashlib.sha256(args.codex.read_bytes()).hexdigest() == base.SHA256, "immutable native binary hash")
    actual_keyring_sha = hashlib.sha256(args.gnome_keyring_daemon.read_bytes()).hexdigest()
    if args.keyring_sha256 is not None:
        require(re.fullmatch('[0-9a-f]{64}', args.keyring_sha256) is not None and
                actual_keyring_sha == args.keyring_sha256, 'explicit real daemon hash mismatch')
    args.keyring_sha256 = actual_keyring_sha
    for name in ["config.toml", "requirements.toml", "managed_config.toml"]:
        require(not Path("/etc/codex", name).exists(), "BLOCKED_ENV: system Codex config exists")
    argv = ["--root", str(args.root), "--codex", str(args.codex), "--base-fixture", str(args.base_fixture),
        "--gnome-keyring-daemon", str(args.gnome_keyring_daemon), "--keyring-sha256", args.keyring_sha256,
        "--dbus-daemon", str(args.dbus_daemon), "--gdbus", str(args.gdbus), "--setpriv", str(args.setpriv)]
    if not args.inside:
        require(sys.platform == "linux" and all(shutil.which(tool) for tool in ["unshare", "ip"]), "BLOCKED_ENV: namespace tools")
        # Make all relevant tool options explicit in child argv even when keyring
        # was originally supplied through the sole authorized environment knob.
        os.execvp("unshare", ["unshare", "--user", "--map-root-user", "--net", "--fork", "--kill-child=TERM",
            sys.executable, str(Path(sys.argv[0]).resolve()), *argv, "--inside", "--parent-netns", os.readlink("/proc/self/ns/net")])
    if not args.unprivileged:
        subprocess.run(["ip", "link", "set", "lo", "up"], check=True, timeout=5)
        # Setup lo while namespace capabilities exist, then irreversibly remove
        # them before any bus/keyring/native process. Do not attempt setgroups.
        os.execv(str(args.setpriv), [str(args.setpriv), '--bounding-set=-all', '--inh-caps=-all',
            '--ambient-caps=-all', '--securebits=+noroot,+noroot_locked', '--no-new-privs',
            sys.executable, '-I', str(Path(sys.argv[0]).resolve()), *argv,
            '--inside', '--unprivileged', '--parent-netns', args.parent_netns])
    args.privilege_proof = privilege_proof()
    return args, base
