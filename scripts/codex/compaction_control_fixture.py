#!/usr/bin/env python3
"""Controlled loopback Responses provider for pinned real Codex compaction.

This is not an app-server emulator. Only requests containing compaction_trigger
are held or faulted. Every request is journaled by ModelFixture before the gate.
Owned stdin explicitly releases held output; stdout reports observed barriers.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

from model_fixture import ModelFixture, response_events


LATE_CHECKPOINT = "SYNTHETIC_CANCELLED_COMPACTION_CHECKPOINT"
FAILED_CHECKPOINT = "SYNTHETIC_FAILED_COMPACTION_CHECKPOINT"
FINAL_CHECKPOINT = "SYNTHETIC_RETRIED_COMPACTION_CHECKPOINT"


class CompactionControlFixture(ModelFixture):
    def __init__(self, scenario, *args, **kwargs):
        super().__init__("assistant", *args, **kwargs)
        self.control_scenario = scenario
        self.release = threading.Event()
        self.compaction_count = 0
        self.control_lock = threading.Lock()
        self.output_lock = threading.Lock()

    def notice(self, event, **fields):
        with self.output_lock:
            print(json.dumps({"event": event, **fields}), flush=True)

    @staticmethod
    def write_events(handler, events):
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        handler.wfile.flush()

    def write_response(self, handler, index, request):
        if not any(item.get("type") == "compaction_trigger"
                   for item in request.get("input", [])):
            return super().write_response(handler, index, request)

        with self.control_lock:
            self.compaction_count += 1
            attempt = self.compaction_count

        if self.control_scenario == "hold":
            self.notice("compaction_held", index=index, attempt=attempt)
            if not self.release.wait(timeout=20):
                self.notice("gate_expired", index=index)
                handler.send_error(504, "Synthetic compaction release deadline")
                return
            events = response_events(index, {"type": "compaction",
                                            "encrypted_content": LATE_CHECKPOINT})
            try:
                self.write_events(handler, events)
                outcome = "written"
            except (BrokenPipeError, ConnectionResetError):
                outcome = "peer_closed"
            self.notice("late_output_released", index=index, outcome=outcome)
            return

        if attempt == 1:
            body = b"Synthetic first compact open failed"
            handler.send_response(500)
            handler.send_header("Content-Length", str(len(body)))
            handler.end_headers()
            handler.wfile.write(body)
        else:
            checkpoint = FAILED_CHECKPOINT if attempt == 2 else FINAL_CHECKPOINT
            events = response_events(index, {"type": "compaction",
                                            "encrypted_content": checkpoint})
            # A provisional checkpoint without response.completed is not usable.
            self.write_events(handler, events[:-1] if attempt == 2 else events)
        self.notice("compaction_attempt", index=index, attempt=attempt)

    def config(self, codex_home):
        super().config(codex_home)
        config = Path(codex_home, "config.toml")
        config.write_text(config.read_text().replace("stream_max_retries = 0",
                                                     "stream_max_retries = 2") +
                          "\n[model_providers.fixture.capabilities]\n"
                          'remote_compaction = "v2"\n')

    def close(self):
        self.release.set()
        super().close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["hold", "retry"], required=True)
    parser.add_argument("--workspace")
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path)
    args = parser.parse_args()
    fixture = CompactionControlFixture(args.scenario, args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        for line in sys.stdin:
            command = json.loads(line)
            if command == {"release": True}:
                fixture.release.set()
            elif command == {"stop": True}:
                break
            else:
                raise ValueError("Unknown synthetic compaction control command")
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
