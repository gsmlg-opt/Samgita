#!/usr/bin/env python3
"""Own real services; Session connects directly to stock-native UDS.

Stdin is strictly fixture control, never app-server traffic. No app-server reply
is generated, proxied or rewritten here. A copied native owner handoff is used
only to validate and drive the actual native loopback callback.
"""
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from private_gateway_fixture import (ACCESS, REFRESH, PrivateStack, arguments,
    require, stop_issuer, stop_owned, success_issuer)

DIRECTORIES = ["home", "codex", "workspace", "tmp", "runtime", "control", "data", "config", "cache", "data-dirs", "config-dirs"]


def main():
    args, base = arguments()
    os.umask(0o077)
    os.chmod(args.root, 0o700)
    for name in DIRECTORIES:
        (args.root / name).mkdir(mode=0o700)
    proof = base.isolation(args.parent_netns)
    proof['privileges'] = args.privilege_proof
    args.scenario = 'success'
    stack, issuer, native = PrivateStack(args, base), None, None
    socket_path = args.root / 'native.sock'
    physical_socket = Path('/tmp').resolve() / f'codex-daemon-{os.geteuid()}' / hashlib.sha256(
        os.fsencode(socket_path)).hexdigest()
    state = {'namespace': proof, 'controller_pid': os.getpid(),
             'namespace_owner_pid': os.getppid(), 'native_pids': [], 'ready': False,
             'generation': 0, 'callbacks': 0, 'snapshots': [], 'cleanup_complete': False}

    def persist():
        base.write_json(args.root / 'state.json', state)

    def stop_native(deadline=None):
        nonlocal native
        state['ready'] = False
        persist()
        if native is not None:
            stop_owned(native, deadline)
            native = None
            for path in [socket_path, physical_socket, physical_socket.with_suffix('.lock')]:
                require(not os.path.lexists(path), 'native socket cleanup incomplete')

    def start_native():
        nonlocal native
        require(native is None, 'native already started')
        require(not os.path.lexists(socket_path), 'old native rendezvous remains')
        generation = state['generation'] + 1
        native = subprocess.Popen([str(args.codex), 'app-server', '--listen', 'unix://' + str(socket_path)],
            env=stack.env, cwd=args.root / 'workspace', stdin=subprocess.DEVNULL,
            stdout=stack.log(f'native-{generation}-stdout.log'),
            stderr=stack.log(f'native-{generation}-stderr.log'))
        state['native_pids'].append(native.pid)
        state['generation'] = generation
        persist()
        deadline = time.monotonic() + 5
        while not socket_path.exists():
            require(native.poll() is None, 'stock native UDS exited during startup')
            require(time.monotonic() < deadline, 'stock native UDS startup deadline')
            time.sleep(0.01)
        # The pinned transport publishes a rendezvous symlink after binding its
        # deterministic private physical socket (upstream unix_socket.rs94-119).
        require(socket_path.is_symlink() and os.readlink(socket_path) == str(physical_socket),
                'native rendezvous does not identify the owned socket')
        metadata = physical_socket.stat()
        require(stat.S_ISSOCK(metadata.st_mode) and metadata.st_uid == os.geteuid()
                and stat.S_IMODE(metadata.st_mode) == 0o600, 'native physical UDS metadata')
        state['ready'] = True
        persist()

    def snapshot():
        path = args.root / 'codex/secrets/gateway_oauth.age'
        require(path.is_file() and path.stat().st_size > 0, 'native ciphertext absent')
        data = path.read_bytes()
        require(all(secret.encode() not in data for secret in [ACCESS, REFRESH]), 'native ciphertext contains plaintext token')
        value = {'ciphertext_sha256': hashlib.sha256(data).hexdigest(),
                 'keyring_item': stack.native_item(), 'generation': state['generation'],
                 'token_exchanges': issuer.exchanges, 'handoffs': issuer.handoffs}
        require(value['token_exchanges'] == 1 and value['handoffs'] == 1, 'unexpected authorization replay')
        state['snapshots'].append(value)
        require(len(state['snapshots']) <= 3, 'snapshot operation bound')
        persist()

    def control(value):
        require(isinstance(value, dict), 'controller object required')
        operation = value.get('operation')
        if operation == 'callback':
            require(set(value) == {'operation', 'native_frame'} and state['callbacks'] == 0,
                    'callback control shape or duplicate')
            frame = value['native_frame']
            require(set(frame).issubset({'method', 'params', 'jsonrpc', 'emittedAtMs'})
                    and frame.get('method') == base.CHANGED,
                    'copied native handoff shape')
            require(type(frame.get('emittedAtMs')) is int and frame['emittedAtMs'] > 0,
                    'native handoff emission timestamp required')
            require(isinstance(frame.get('params', {}).get('authUrl'), str), 'copied native handoff URL required')
            # This exact frame was observed by Session on native UDS. It is not
            # emitted as an app-server message by the controller.
            issuer.observe(frame)
            issuer.callback()
            state['callbacks'] = 1
            persist()
        elif operation == 'snapshot':
            require(set(value) == {'operation'}, 'snapshot control shape')
            snapshot()
        elif operation == 'restart':
            require(set(value) == {'operation'} and state['generation'] == 1 and len(state['snapshots']) == 1,
                    'restart control preconditions')
            stop_native()
            start_native()
        elif operation == 'close':
            require(set(value) == {'operation'}, 'close control shape')
            return False
        else:
            raise AssertionError('unapproved fixture control operation')
        return True

    def terminate(_signum, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    cleanup_errors = []
    persist()
    try:
        issuer = success_issuer(args, base, proof)
        issuer.thread.start()
        base.configure(args, f'http://127.0.0.1:{issuer.server.server_port}')
        state['keyring'] = stack.start()
        persist()
        start_native()
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin.buffer, selectors.EVENT_READ)
        buffer, count, deadline, closing = b'', 0, time.monotonic() + 45, False
        try:
            while True:
                require(native.poll() is None and stack.keyring.poll() is None and stack.bus.poll() is None,
                        'owned native/service exited unexpectedly')
                require(time.monotonic() < deadline, 'controller overall deadline')
                if not selector.select(min(0.05, max(0, deadline-time.monotonic()))):
                    continue
                chunk = os.read(sys.stdin.fileno(), base.MAX_WIRE + 1)
                if not chunk:
                    require(not buffer, 'partial fixture control at EOF')
                    break
                buffer += chunk
                require(len(buffer) <= base.MAX_WIRE, 'fixture control size bound')
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    count += 1
                    require(count <= 6, 'fixture control operation count')
                    if not control(json.loads(line)):
                        require(not buffer, 'control after close')
                        closing = True
                        break
                if closing:
                    break
        finally:
            selector.close()
    except Exception as error:
        message = str(error)
        secrets = [ACCESS, REFRESH, base.CANARY]
        if stack.password is not None:
            secrets.append(stack.password.decode())
        for secret in secrets:
            message = message.replace(secret, '[redacted]')
        state['failure'] = {'type': type(error).__name__, 'message': message[:512]}
        persist()
        raise
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_deadline = time.monotonic() + 0.65
        state['keyring_pids'] = [process.pid for process in [stack.keyring, stack.bus] if process is not None]
        try:
            stop_native(cleanup_deadline)
        except Exception as error:
            cleanup_errors.append('native:' + type(error).__name__)
        if issuer is not None:
            try:
                stop_issuer(issuer, cleanup_deadline)
            except Exception as error:
                cleanup_errors.append('issuer:' + type(error).__name__)
        try:
            stack.close(cleanup_deadline)
        except Exception as error:
            cleanup_errors.append('stack:' + type(error).__name__)
        state['cleanup_errors'] = cleanup_errors
        persist()
        require(not cleanup_errors, 'owned cleanup incomplete')
        if issuer is not None:
            require(not any(event['event'] in {'fixture_error', 'unexpected_http', 'peer_closed'}
                            for event in issuer.journal['events']), 'issuer diagnostics failed')
        for path in args.root.glob('*.log'):
            require(path.stat().st_size <= 1048576, 'owned diagnostic size bound')
            data = path.read_bytes()
            require(all(secret.encode() not in data for secret in [ACCESS, REFRESH, base.CANARY]),
                    'owned diagnostic secret scan failed')
        for name in DIRECTORIES:
            path = args.root / name
            # GNOME removes its caller-supplied control directory on shutdown.
            if name == 'control' and not os.path.lexists(path):
                continue
            require(path.is_dir() and not path.is_symlink(), 'owned cleanup directory changed')
            shutil.rmtree(path)
        if socket_path.exists():
            require(stat.S_ISSOCK(socket_path.lstat().st_mode), 'owned UDS replaced at cleanup')
            socket_path.unlink()
        (args.root / 'bus.conf').unlink(missing_ok=True)
        require(time.monotonic() <= cleanup_deadline, 'controller cleanup exceeded shared budget')
        state['cleanup_complete'] = True
        state['secret_scan_passed'] = True
        persist()


if __name__ == '__main__':
    main()
