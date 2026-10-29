#!/usr/bin/env python3
"""Streaming model-provider companion for the ordinary standalone consumer.

Reuse the source-pinned base fixture unchanged. This is a loopback Responses
provider for actual Codex, never an app-server emulator.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture, response_events


class StreamingFixture(ModelFixture):
    def write_response(self, handler, index, request):
        item = self.response_item(index, request)
        events = response_events(index, item)
        if item.get("type") == "message":
            # Match pinned core/tests/common/responses.rs helpers:
            # ev_message_item_added, ev_output_text_delta, ev_assistant_message.
            text = item["content"][0]["text"]
            split = len(text) // 2
            events[1:1] = [
                {"type": "response.output_item.added", "item": {
                    **item, "content": [{"type": "output_text", "text": ""}],
                }},
                *({"type": "response.output_text.delta", "delta": chunk}
                  for chunk in (text[:split], text[split:])),
            ]
        body = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
                       for event in events).encode()
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Content-Length", str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["dynamic_tool"], default="dynamic_tool")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = StreamingFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
