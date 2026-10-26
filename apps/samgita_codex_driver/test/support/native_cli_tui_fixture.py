#!/usr/bin/env python3
"""Test-only PTY relay, explicitly launched inside the existing Stdio owner.

Usage: python3 native_cli_tui_fixture.py /absolute/pinned/codex [exact args ...]
The caller supplies the isolated cwd/environment/configuration. This fixture
never reads configuration, answers terminal queries, submits prompts or quits.

Output JSONL: ready(pid, executable, argv, process identities), output(data in
base64), exit(status). Input JSONL: {"type":"input","data":"<base64 keys>"}.
Raw terminal bytes, including NUL, are always base64 encoded. Relay failures emit
an error(reason) when possible and exit nonzero; the unchanged outer owner then
cleans its process group. Such cleanup is never evidence of normal completion.
"""
import base64
import binascii
import errno
import fcntl
import json
import os
import select
import struct
import subprocess
import sys
import termios
import time


PTY_CHUNK_BYTES = 16_384
MAX_RAW_OUTPUT_BYTES = 8_388_608
MAX_OUTPUT_QUEUE_BYTES = 1_048_576
MAX_INPUT_LINE_BYTES = 16_384
MAX_INPUT_CHUNK_BYTES = 8_192
MAX_INPUT_QUEUE_BYTES = 65_536
MAX_ARGV_BYTES = 32_768
MAX_LIFETIME_SECONDS = 120.0
EXIT_DRAIN_SECONDS = 2.0
FAILURE_REPORT_SECONDS = 0.25
ROWS = 40
COLUMNS = 120
FAILURE_STATUS = 70


class RelayFailure(Exception):
    """A stable synthetic-fixture failure code, without native/error contents."""


def record(value):
    return (json.dumps(value, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def enqueue(pending, value):
    encoded = record(value)
    if len(pending) + len(encoded) > MAX_OUTPUT_QUEUE_BYTES:
        raise RelayFailure("output_queue_limit")
    pending.extend(encoded)


def keyboard(line):
    if len(line) > MAX_INPUT_LINE_BYTES:
        raise RelayFailure("input_line_limit")
    try:
        value = json.loads(line)
        if (not isinstance(value, dict) or set(value) != {"type", "data"}
                or value["type"] != "input" or not isinstance(value["data"], str)):
            raise RelayFailure("invalid_input_record")
        decoded = base64.b64decode(value["data"], validate=True)
    except (ValueError, UnicodeError, binascii.Error):
        raise RelayFailure("invalid_input_record") from None
    if not decoded or len(decoded) > MAX_INPUT_CHUNK_BYTES:
        raise RelayFailure("input_chunk_limit")
    return decoded


def flush_failure(pending, reason):
    # Finish any partially written JSONL record before the explicit error record.
    # If the consumer is gone/stalled, nonzero relay exit remains authoritative.
    try:
        enqueue(pending, {"type": "error", "reason": reason})
        deadline = time.monotonic() + FAILURE_REPORT_SECONDS
        while pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            _, writable, _ = select.select([], [1], [], remaining)
            if writable:
                try:
                    count = os.write(1, pending[:PTY_CHUNK_BYTES])
                except BlockingIOError:
                    continue
                if count <= 0:
                    return
                del pending[:count]
    except (OSError, RelayFailure):
        pass


def run(child, master, argv, relay_pid, relay_pgid, relay_sid, pending):
    native_pgid = os.getpgid(child.pid)
    native_sid = os.getsid(child.pid)
    if native_pgid != relay_pgid or native_sid != relay_sid:
        raise RelayFailure("native_owner_identity_mismatch")
    enqueue(pending, {
        "type": "ready", "pid": child.pid, "executable": argv[0], "argv": argv,
        "pgid": native_pgid, "sid": native_sid,
        "relay_pid": relay_pid, "relay_pgid": relay_pgid, "relay_sid": relay_sid,
    })
    keys = bytearray()
    incoming = bytearray()
    total_output = 0
    terminal_eof = False
    exit_queued = False
    exit_deadline = None
    deadline = time.monotonic() + MAX_LIFETIME_SECONDS
    while True:
        now = time.monotonic()
        if now >= deadline:
            raise RelayFailure("lifetime_limit")
        status = child.poll()
        if status is not None:
            if exit_deadline is None:
                exit_deadline = now + EXIT_DRAIN_SECONDS
            if keys or incoming:
                raise RelayFailure("native_exit_with_pending_input")
            if terminal_eof and not exit_queued:
                enqueue(pending, {"type": "exit", "status": status})
                exit_queued = True
            if exit_queued and not pending:
                # poll() reaped this native child; outer owner retains relay PGID.
                return status if status >= 0 else 128 - status
            if now >= exit_deadline:
                raise RelayFailure("exit_drain_limit")

        readable_fds = [] if status is not None else [0]
        if not terminal_eof:
            readable_fds.append(master)
        writable_fds = [1] if pending else []
        if keys and not terminal_eof:
            writable_fds.append(master)
        wait = min(0.1, deadline - now)
        if exit_deadline is not None:
            wait = min(wait, max(0.0, exit_deadline - now))
        readable, writable, _ = select.select(readable_fds, writable_fds, [], wait)
        if master in readable:
            try:
                data = os.read(master, PTY_CHUNK_BYTES)
            except BlockingIOError:
                data = None
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                # Linux PTY masters report EIO after every slave has closed.
                data = b""
            if data == b"":
                terminal_eof = True
            elif data:
                total_output += len(data)
                if total_output > MAX_RAW_OUTPUT_BYTES:
                    raise RelayFailure("raw_output_limit")
                enqueue(pending, {
                    "type": "output", "data": base64.b64encode(data).decode("ascii"),
                })
        if 0 in readable:
            data = os.read(0, 4_096)
            if not data:
                raise RelayFailure("control_eof_before_native_exit")
            incoming.extend(data)
            while b"\n" in incoming:
                line, _, rest = incoming.partition(b"\n")
                incoming = bytearray(rest)
                decoded = keyboard(line)
                if terminal_eof:
                    raise RelayFailure("input_after_terminal_eof")
                if len(keys) + len(decoded) > MAX_INPUT_QUEUE_BYTES:
                    raise RelayFailure("input_queue_limit")
                keys.extend(decoded)
            if len(incoming) > MAX_INPUT_LINE_BYTES:
                raise RelayFailure("input_line_limit")
        if master in writable:
            try:
                count = os.write(master, keys[:MAX_INPUT_CHUNK_BYTES])
            except BlockingIOError:
                count = 0
            del keys[:count]
        if 1 in writable:
            try:
                count = os.write(1, pending[:PTY_CHUNK_BYTES])
            except BlockingIOError:
                count = 0
            del pending[:count]


def main():
    pending = bytearray()
    master = None
    slave = None
    child = None
    try:
        if os.name != "posix":
            raise RelayFailure("unix_required")
        argv = sys.argv[1:]
        if (not argv or not os.path.isabs(argv[0])
                or sum(len(arg.encode()) + 1 for arg in argv) > MAX_ARGV_BYTES):
            raise RelayFailure("invalid_native_argv")
        relay_pid = os.getpid()
        relay_pgid = os.getpgrp()
        relay_sid = os.getsid(0)
        if relay_pid != relay_pgid or relay_pid != relay_sid:
            raise RelayFailure("existing_owner_session_required")
        os.set_blocking(1, False)
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))
        # Popen inherits the existing owner-created relay session/group. No
        # preexec_fn, setsid, process_group, pty.fork or controlling-tty request.
        child = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave,
                                 close_fds=True, bufsize=0)
        os.close(slave)
        slave = None
        os.set_blocking(master, False)
        os.set_blocking(0, False)
        return run(child, master, argv, relay_pid, relay_pgid, relay_sid, pending)
    except RelayFailure as error:
        flush_failure(pending, str(error))
        return FAILURE_STATUS
    except Exception:
        # Native paths/data and Python exception details never enter control logs.
        flush_failure(pending, "relay_io_failure")
        return FAILURE_STATUS
    finally:
        for descriptor in (slave, master):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
        if child is not None:
            # Reap an already-exited child. A live child on exceptional shutdown
            # remains inside the unchanged outer owner's group/subreaper cleanup.
            child.poll()


if __name__ == "__main__":
    sys.exit(main())
