"""Own one explicitly requested child; forward its stdio and reap its process group.

This helper never reads ambient Codex configuration or logs child data. Its own
stdin disappearing (including an Erlang port owner crash) terminates the owned
group. stderr is drained and discarded in bounded chunks to prevent pipe stalls.
"""
import os
import signal
import subprocess
import sys
import threading


def main():
    stopping = threading.Event()
    child = None

    def stop(*_args):
        stopping.set()
        if child is not None:
            try:
                if os.name == "posix":
                    os.killpg(child.pid, signal.SIGTERM)
                else:
                    child.terminate()
            except ProcessLookupError:
                pass

    for name in ("SIGTERM", "SIGHUP", "SIGINT"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), stop)

    try:
        child = subprocess.Popen(
            sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=(os.name == "posix"),
            bufsize=0,
        )
    except (OSError, ValueError):
        return 127

    def copy_input():
        try:
            while not stopping.is_set():
                data = os.read(sys.stdin.fileno(), 65536)
                if not data:
                    break
                view = memoryview(data)
                while view:
                    count = os.write(child.stdin.fileno(), view)
                    view = view[count:]
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
        while child.poll() is None and not stopping.wait(0.05):
            pass
    finally:
        # Reap descendants even if the immediate child has already exited.
        stop()
        try:
            child.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            pass
        if os.name == "posix":
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        elif child.poll() is None:
            child.kill()
        child.wait()
        output_thread.join(timeout=1.0)
    return child.returncode if child.returncode >= 0 else 128 - child.returncode


if __name__ == "__main__":
    sys.exit(main())
