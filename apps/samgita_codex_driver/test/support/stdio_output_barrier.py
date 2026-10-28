#!/usr/bin/env python3
"""Exercise the real helper's output-reader ACK condition.

This is an owned functional helper reproduction, never evidence that an
unobserved scheduling window caused the original native qualification failure.
No helper source, cleanup signal, wait result or ACK byte is substituted.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import time

sys.dont_write_bytecode = True

HELPER_SHA = "34f63e30a21b040084a473c3c5ce9e175a43dce6691021ab3126d0d53dbce39f"
CHILD_LINE = b"owned finite output-drain marker\n"
CHILD_CODE = "import os;os.write(1,b'owned finite output-drain marker\\n')"
MAX_EVENTS = 24
MAX_JOURNAL = 16_384


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_helper(path):
    require(hashlib.sha256(path.read_bytes()).hexdigest() == HELPER_SHA,
            "expected real stdio helper SHA mismatch")


def worker(helper_path, scenario, journal_path, exit_mode):
    check_helper(helper_path)
    spec = importlib.util.spec_from_file_location("owned_real_stdio_helper", helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    events = []
    lock = threading.Lock()
    entered = threading.Event()
    release = threading.Event()

    def record(event, **fields):
        with lock:
            require(len(events) < MAX_EVENTS, "owned helper phase count bound")
            events.append({"event": event, **fields})
            encoded = json.dumps({"events": events}, sort_keys=True).encode()
            require(len(encoded) <= MAX_JOURNAL, "owned helper phase byte bound")
            temporary = journal_path.with_suffix(".pending")
            temporary.write_bytes(encoded)
            temporary.replace(journal_path)

    record("worker_started", pid=os.getpid(), scenario=scenario,
           exitMode=exit_mode, helperSha256=HELPER_SHA)
    real_thread = threading.Thread
    real_terminate = helper.terminate_child_group
    real_reap = helper.reap_descendants
    real_ack = helper.acknowledge_cleanup

    def observed_thread(*args, **kwargs):
        target = kwargs.get("target")
        if getattr(target, "__name__", None) != "copy_output":
            return real_thread(*args, **kwargs)

        def gated_output():
            record("output_barrier_entered")
            entered.set()
            if not release.wait(5.0):
                record("output_barrier_expired")
                return
            record("output_barrier_released")
            target()
            record("output_reader_finished")

        kwargs = {**kwargs, "target": gated_output}
        thread = real_thread(*args, **kwargs)
        real_start = thread.start
        real_join = thread.join

        def start():
            real_start()
            require(entered.wait(1.0), "owned output barrier entry deadline")

        def join(timeout=None):
            require(timeout == 1.0, "real output-join deadline changed")
            record("output_join_started", timeoutSeconds=timeout)
            if scenario == "released":
                record("output_release_requested")
                release.set()
            real_join(timeout=timeout)
            record("output_join_finished", readerAlive=thread.is_alive())

        thread.start = start
        thread.join = join
        return thread

    def observed_terminate(child):
        # Natural mode keeps input open; close mode keeps its child blocked on
        # input until the helper's original NUL control requests real cleanup.
        waitable = helper.child_exited(child)
        record("group_cleanup_started", childPid=child.pid, childWaitable=waitable)
        real_terminate(child)
        try:
            os.waitpid(child.pid, os.WNOHANG)
        except ChildProcessError:
            independently_reaped = True
        else:
            independently_reaped = False
        record("group_cleanup_finished", childPid=child.pid,
               returnCode=child.returncode, independentlyReaped=independently_reaped)
        require(waitable == (exit_mode == "natural"),
                "owned child exited through the wrong lifecycle path")
        expected_child_return = 0 if exit_mode == "natural" else -15
        require(child.returncode == expected_child_return and independently_reaped,
                "real child wait/reaping did not complete")

    def observed_reap():
        result = real_reap()
        record("descendants_reaped", result=result)
        return result

    def observed_ack():
        record("ack_write_started")
        real_ack()
        record("ack_write_finished")

    # Observers always call original cleanup functions. Only the output reader
    # has a scheduling barrier; the helper's signal/reap/join/ACK code is intact.
    helper.threading.Thread = observed_thread
    helper.terminate_child_group = observed_terminate
    helper.reap_descendants = observed_reap
    helper.acknowledge_cleanup = observed_ack
    child_code = CHILD_CODE
    if exit_mode == "close":
        ready_path = journal_path.with_suffix(".child-ready")
        ready_pending = str(ready_path) + ".pending"
        child_code = ("import os,sys\n"
                      "os.write(1," + repr(CHILD_LINE) + ")\n"
                      "with open(" + repr(ready_pending) + ", 'xb') as ready:\n"
                      "    ready.write(b'ready')\n"
                      "os.rename(" + repr(ready_pending) + "," + repr(str(ready_path)) + ")\n"
                      "sys.stdin.buffer.read()\n")
    sys.argv = [str(helper_path), sys.executable, "-B", "-c", child_code]
    try:
        result = helper.main()
        record("helper_returned", returnCode=result)
        return result
    except BaseException as error:
        record("worker_exception", kind=type(error).__name__)
        raise



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", required=True, type=Path)
    parser.add_argument("--scenario", required=True, choices=["held", "released"])
    parser.add_argument("--journal", required=True, type=Path)
    parser.add_argument("--exit-mode", required=True, choices=["natural", "close"])
    args = parser.parse_args()
    require(sys.platform.startswith("linux"), "owned /proc reaping proof requires Linux")
    helper = args.helper.resolve(strict=True)
    return worker(helper, args.scenario, args.journal, args.exit_mode)


if __name__ == "__main__":
    raise SystemExit(main())
