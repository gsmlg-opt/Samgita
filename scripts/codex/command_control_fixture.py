"""Owned local command children and exact recorded-child fallback cleanup.

This fixture never emits app-server messages. The real pinned Codex server
produces all protocol responses and notifications observed by the caller.
"""

import base64
import json
import os
import select
import signal
import sys
from pathlib import Path


def start_time(pid):
    return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def save(path, value):
    temporary = Path(str(path) + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    os.replace(temporary, path)


def cleanup(record_path):
    if not record_path.exists():
        return
    record = json.loads(record_path.read_text())
    pid = record["pid"]
    try:
        descriptor = os.pidfd_open(pid)
    except ProcessLookupError:
        return
    try:
        if select.select([descriptor], [], [], 0)[0]:
            return
        try:
            started = start_time(pid)
            arguments = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        except FileNotFoundError:
            return
        if (
            started != record["start"]
            or os.fsencode(record["script"]) not in arguments
            or os.fsencode(record["handle"]) not in arguments
        ):
            if select.select([descriptor], [], [], 0)[0]:
                return
            raise RuntimeError("Owned command cleanup identity changed")
        try:
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if not select.select([descriptor], [], [], 5.0)[0]:
            raise RuntimeError("Owned command cleanup deadline")
    finally:
        os.close(descriptor)


def child(mode, handle, record_path, result_path):
    # Cleanup failsafe only; neither test expects this exit code.
    signal.signal(signal.SIGALRM, lambda *_: os._exit(125))
    signal.alarm(20)
    record = {
        "pid": os.getpid(),
        "start": start_time(os.getpid()),
        "script": str(Path(__file__).resolve()),
        "handle": handle,
        "mode": mode,
        "cwd": os.getcwd(),
    }
    if mode == "pty":
        import tty

        tty.setraw(0)
        size = os.get_terminal_size(0)
        record.update(rows=size.lines, cols=size.columns)
    elif mode != "wait":
        raise ValueError("Unknown owned command mode")

    save(record_path, record)
    os.write(1, f"READY:{handle}\n".encode())

    if mode == "wait":
        # Explicit native termination is the only expected way to finish.
        os.read(0, 1)
        raise RuntimeError("Owned wait command ended without native termination")

    received = bytearray()
    while not received.endswith(b"\n"):
        chunk = os.read(0, 1)
        if not chunk:
            raise RuntimeError("Owned PTY stdin closed before the fixed line")
        received.extend(chunk)
        if len(received) > 1024:
            raise RuntimeError("Owned PTY input bound exceeded")
    size = os.get_terminal_size(0)
    result = {
        "handle": handle,
        "pid": os.getpid(),
        "rows": size.lines,
        "cols": size.columns,
        "inputBase64": base64.b64encode(received).decode("ascii"),
    }
    save(result_path, result)
    encoded = json.dumps(result, ensure_ascii=False, separators=(",", ":"))
    os.write(1, ("RESULT:" + encoded + "\n").encode())


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--cleanup":
        cleanup(Path(sys.argv[2]))
    elif len(sys.argv) == 5:
        child(sys.argv[1], sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]))
    else:
        raise ValueError("Expected owned mode/handle/record/result or --cleanup record")
