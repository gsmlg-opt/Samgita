"""Passive Linux observer for one genuine, owned native rollout file.

The line protocol has ready/arm/drain/stop barriers. It never reads or writes
rollout contents, and every window must start with an empty inotify queue.
"""

import argparse
import ctypes
import errno
import json
import os
import stat
import struct
import sys


IN_ACCESS = 0x00000001
IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_CLOSE_NOWRITE = 0x00000010
IN_OPEN = 0x00000020
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_UNMOUNT = 0x00002000
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
EXPECTED = IN_ACCESS | IN_CLOSE_NOWRITE | IN_OPEN
WATCH = EXPECTED | IN_MODIFY | IN_CLOSE_WRITE | IN_DELETE_SELF | IN_MOVE_SELF
HEADER = struct.Struct("iIII")


def emit(message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def observe(path):
    if sys.platform != "linux" or not stat.S_ISREG(os.lstat(path).st_mode):
        raise RuntimeError("observer requires a regular Linux fixture rollout")
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    try:
        wd = libc.inotify_add_watch(fd, os.fsencode(path), WATCH)
        if wd < 0:
            raise OSError(ctypes.get_errno(), "inotify_add_watch failed")

        def drain():
            events = []
            total = 0
            while True:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EAGAIN:
                        return events
                    raise
                if not data:
                    raise RuntimeError("unexpected empty inotify read")
                total += len(data)
                if total > 65536:
                    raise RuntimeError("observer byte bound exceeded")
                offset = 0
                while offset < len(data):
                    event_wd, mask, cookie, length = HEADER.unpack_from(data, offset)
                    offset += HEADER.size + length
                    if mask & (IN_Q_OVERFLOW | IN_UNMOUNT | IN_IGNORED):
                        raise RuntimeError("inotify queue/watch lost")
                    if event_wd != wd or mask & ~EXPECTED or cookie or length:
                        raise RuntimeError("unexpected rollout event")
                    events.append(mask)
                    if len(events) > 256:
                        raise RuntimeError("observer event bound exceeded")

        emit({"status": "ready", "pid": os.getpid(), "path": path})
        armed = False
        sequence = 0
        for line in sys.stdin:
            if len(line) > 256:
                raise RuntimeError("observer command bound exceeded")
            command = json.loads(line)
            if command == {"command": "arm"} and not armed:
                if drain():
                    raise RuntimeError("rollout access outside a request window")
                armed = True
                sequence += 1
                emit({"status": "armed", "sequence": sequence})
            elif command == {"command": "drain"} and armed:
                events = drain()
                armed = False
                emit({"status": "drained", "sequence": sequence, "events": events})
            elif command == {"command": "stop"} and not armed:
                if drain():
                    raise RuntimeError("rollout access outside a request window")
                emit({"status": "stopped", "sequence": sequence})
                return
            else:
                raise RuntimeError("invalid observer lifecycle command")
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    args = parser.parse_args()
    try:
        observe(args.path)
    except (OSError, RuntimeError, ValueError, struct.error) as error:
        emit({"status": "error", "message": str(error)})
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
