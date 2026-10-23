"""Own one explicitly requested child; forward its stdio and reap its process group.

This helper never reads ambient Codex configuration or logs child data. Its own
stdin disappearing (including an Erlang port owner crash) terminates the owned
group. stderr is drained and discarded in bounded chunks to prevent pipe stalls.
"""
import os
import select
import signal
import subprocess
import sys
import threading
import time


def acknowledge_cleanup():
    # Dedicated helper control, never a native JSONL message.
    os.write(sys.stdout.fileno(), b"\0")


def enable_subreaper():
    if sys.platform.startswith("linux"):
        import ctypes
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise OSError("Cannot establish owned descendant reaping")


def reap_descendants():
    deadline = time.monotonic() + 1.0
    while True:
        try:
            pid, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return True
        if pid == 0:
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.01)


def child_exited(child):
    if os.name == "posix":
        # Keep the group leader waitable until all group signals have finished.
        # Reaping here would allow its PID (and therefore PGID) to be reused.
        return os.waitid(os.P_PID, child.pid,
                         os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None
    return child.poll() is not None


def terminate_child_group(child):
    if os.name == "posix":
        os.killpg(child.pid, signal.SIGTERM)
        deadline = time.monotonic() + 1.0
        while not child_exited(child) and time.monotonic() < deadline:
            time.sleep(0.01)
        os.killpg(child.pid, signal.SIGKILL)
    elif child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            child.kill()
    child.wait()


def main():
    stopping = threading.Event()
    child = None

    def stop(*_args):
        # Only the main thread signals the group, before reaping its leader.
        # Late pipe/signal callbacks must never signal a reusable group ID.
        stopping.set()

    for name in ("SIGTERM", "SIGHUP", "SIGINT"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), stop)

    try:
        enable_subreaper()
        if os.name == "posix" and not all(
                hasattr(os, name) for name in ("waitid", "WNOWAIT")):
            raise OSError("Cannot retain owned process group identity")
        child = subprocess.Popen(
            sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=(os.name == "posix"),
            bufsize=0,
        )
    except (OSError, ValueError):
        acknowledge_cleanup()
        return 127

    def copy_input():
        try:
            pending = b""
            source, destination = sys.stdin.fileno(), child.stdin.fileno()
            os.set_blocking(source, False)
            os.set_blocking(destination, False)
            while not stopping.is_set():
                readable, writable, _ = select.select(
                    [source], [destination] if pending else [], [], 0.05)
                if readable:
                    data = os.read(source, 65536)
                    if not data or b"\0" in data:
                        break
                    pending += data
                    if len(pending) > 16_777_216:
                        break
                if writable:
                    try:
                        pending = pending[os.write(destination, pending[:65536]):]
                    except BlockingIOError:
                        pass
        except (OSError, ValueError):
            pass
        finally:
            stop()

    def copy_output():
        try:
            while True:
                data = os.read(child.stdout.fileno(), 65536)
                if not data:
                    break
                if b"\0" in data:
                    # Child output cannot impersonate the helper cleanup ACK.
                    stop()
                    break
                view = memoryview(data)
                while view:
                    count = os.write(sys.stdout.fileno(), view)
                    view = view[count:]
        except (OSError, ValueError):
            stop()

    def discard_stderr():
        try:
            while os.read(child.stderr.fileno(), 65536):
                pass
        except (OSError, ValueError):
            pass

    output_thread = threading.Thread(target=copy_output, daemon=True)
    output_thread.start()
    for target in (copy_input, discard_stderr):
        threading.Thread(target=target, daemon=True).start()

    try:
        while not child_exited(child) and not stopping.wait(0.05):
            pass
    finally:
        # Reap descendants even if the immediate child has already exited.
        stop()
        terminate_child_group(child)
        descendants_reaped = reap_descendants()
        output_thread.join(timeout=1.0)
        if descendants_reaped and not output_thread.is_alive():
            acknowledge_cleanup()
    return child.returncode if child.returncode >= 0 else 128 - child.returncode


if __name__ == "__main__":
    sys.exit(main())
