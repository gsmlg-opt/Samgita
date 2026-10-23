#!/usr/bin/env python3
"""Owned loopback Responses peer with explicit queue-test hold/release barriers.

Codex owns durable queues and turn dispatch. This peer only journals native turn
metadata and returns synthetic assistant messages. No app-server is emulated.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

from model_fixture import ModelFixture


class QueuedModelFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        super().__init__(scenario, workspace, requests_file)
        self.observations_file = Path(requests_file).with_name("queue-observations.json")
        self.observations = {}
        self.releases = {}
        self.closing = False
        self.persist()

    def persist(self):
        temporary = self.observations_file.with_suffix(".partial")
        temporary.write_text(json.dumps(self.observations))
        temporary.replace(self.observations_file)

    def release(self, index):
        with self.lock:
            self.releases.setdefault(index, threading.Event()).set()

    def write_response(self, handler, index, request):
        held = self.scenario == "hold_first" and index == 1
        with self.lock:
            release = self.releases.setdefault(index, threading.Event())
            self.observations[str(index)] = {
                "metadata": json.loads(handler.headers.get("x-codex-turn-metadata", "null")),
                "held": held,
                "released": False,
                "answered": False,
                "timedOut": False,
            }
            self.persist()

        if held and not release.wait(timeout=20):
            with self.lock:
                self.observations[str(index)]["timedOut"] = True
                self.persist()
            handler.send_error(500, "Synthetic queue hold was not explicitly released")
            return

        with self.lock:
            self.observations[str(index)]["released"] = held
            self.persist()
            if self.closing:
                return

        try:
            super().write_response(handler, index, request)
            with self.lock:
                self.observations[str(index)]["answered"] = True
                self.persist()
        except (BrokenPipeError, ConnectionResetError):
            # An interrupted native turn may close its owned HTTP request.
            pass

    def response_item(self, index, request):
        return {"type": "message", "role": "assistant", "id": f"queued-answer-{index}",
                "content": [{"type": "output_text", "text": f"Synthetic queue answer {index}"}]}

    def config(self, codex_home):
        super().config(codex_home)
        with Path(codex_home, "config.toml").open("a") as target:
            target.write("\n[features]\nshell_snapshot = false\n")

    def close(self):
        with self.lock:
            self.closing = True
            for release in self.releases.values():
                release.set()
        super().close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["auto", "hold_first"], default="auto")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = QueuedModelFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        for line in sys.stdin:
            fixture.release(json.loads(line)["release"])
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
