#!/usr/bin/env python3
"""Loopback Responses dependency for one actual native view_image execution.

The native Codex binary must read the image and emit/persist its own items.
This fixture emits no app-server frames and never reads the owned source PNG.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


class ImageViewFixture(ModelFixture):
    def __init__(self, workspace, requests_file, scenario="image_view"):
        super().__init__("assistant", workspace, requests_file)
        self.image_scenario = scenario
        # Preserve every provider request, including any unexpected extra turn.
        with self.requests_file.open("x", encoding="utf-8") as target:
            target.write("[]")

    def item(self, index):
        if index == 1:
            if self.image_scenario == "image_view_invalid":
                call_id = "owned-view-image-invalid-call-1"
                arguments = {"path": "owned-invalid-image.png"}
            elif self.image_scenario == "image_view_low_detail":
                call_id = "owned-view-image-low-detail-call-1"
                arguments = {"path": "owned-image.png", "detail": "low"}
            else:
                call_id = "owned-view-image-call-1"
                arguments = {"path": "owned-image.png"}
            return {
                "type": "function_call", "name": "view_image",
                "call_id": call_id,
                "arguments": json.dumps(arguments),
            }
        if index == 2:
            return {
                "type": "message", "role": "assistant", "id": "owned-view-image-answer",
                "content": [{"type": "output_text", "text": "Owned local image read finished"}],
            }
        raise AssertionError("Unexpected extra inference in owned image-view fixture")

    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        path.write_text(
            'cli_auth_credentials_store = "ephemeral"\n'
            'check_for_update_on_startup = false\nallow_login_shell = false\n'
            + path.read_text()
            + '\n[features]\nview_image = true\nunified_image_budget = false\n'
            'shell_snapshot = false\napps = false\n', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=[
        "image_view", "image_view_invalid", "image_view_low_detail"], required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = ImageViewFixture(args.workspace, args.requests_file, args.scenario).start()
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
