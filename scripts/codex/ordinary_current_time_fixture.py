#!/usr/bin/env python3
"""Loopback final-answer provider for real native external-clock requests.

The stock app-server emits currentTime/read. This fixture emits only Responses
backend data, with no tools, MCP peer or application protocol messages.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class OrdinaryClockFixture(ModelFixture):
    def __init__(self, workspace, requests_file):
        super().__init__("assistant", workspace, requests_file)

    def item(self, index):
        assert index == 1, "Exactly one ordinary clock provider request"
        return {"type": "message", "role": "assistant", "id": "ordinary-clock-done",
                "content": [{"type": "output_text", "text": "Owned external time read"}]}

    def config(self, codex_home):
        Path(codex_home, "config.toml").write_text(f'''model = "mock-model"
model_provider = "fixture"
web_search = "disabled"
check_for_update_on_startup = false
allow_login_shell = false
chatgpt_base_url = "{self.url}"
openai_base_url = "{self.url}/v1"
[model_providers.fixture]
name = "Owned ordinary external clock fixture"
base_url = "{self.url}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
[features]
shell_snapshot = false
remote_plugin = false
apps = false
memories = false
[features.current_time_reminder]
enabled = true
reminder_interval_seconds = 1
clock_source = "external"
[memories]
generate_memories = false
use_memories = false
[analytics]
enabled = false
[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--requests-file", required=True)
    parser.add_argument("--scenario")
    args = parser.parse_args()
    fixture = OrdinaryClockFixture(args.workspace, args.requests_file).start()
    fixture.config(args.codex_home)
    print(json.dumps({"url": fixture.url}), flush=True)
    try:
        input()
    except EOFError:
        pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
