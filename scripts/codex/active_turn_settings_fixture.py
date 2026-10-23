#!/usr/bin/env python3
"""Synthetic loopback Responses provider for native current-turn settings tests.

The real pinned Codex creates every app-server response/notification. This backend
only returns one fixed dynamic-tool call followed by assistant responses. It never
executes a command, authenticates an account or fabricates app-server messages.
"""
import argparse
import json
from pathlib import Path
import sys

from model_fixture import ModelFixture


class ActiveTurnSettingsFixture(ModelFixture):
    def __init__(self, scenario, workspace, requests_file):
        self.settings_scenario = scenario
        provider_scenario = "assistant" if scenario == "assistant" else "dynamic_tool"
        super().__init__(provider_scenario, workspace, requests_file)

    def config(self, codex_home):
        super().config(codex_home)
        catalog = Path(codex_home, "step-models.json")
        # A and B have identical tool/safety characteristics. Only the slug differs.
        # Explicit catalog support keeps reasoning/tier assertions about emitted
        # provider fields rather than defaults or silently filtered parameters.
        base_model = {
            "display_name": "Synthetic current-turn settings model",
            "default_reasoning_level": "low",
            "supported_reasoning_levels": [
                {"effort": "low", "description": "Synthetic low"},
                {"effort": "high", "description": "Synthetic high"},
                {"effort": "fixture-effort", "description": "Synthetic custom effort"},
            ],
            "shell_type": "unified_exec",
            "visibility": "list",
            "supported_in_api": True,
            "priority": 1,
            "service_tiers": [{"id": "priority", "name": "Synthetic priority",
                               "description": "Local provider fixture tier"}],
            "model_messages": {
                "instructions_template": "Synthetic local settings fixture instructions."
            },
            "supports_reasoning_summary_parameter": True,
            "support_verbosity": False,
            "truncation_policy": {"mode": "bytes", "limit": 10000},
            "experimental_supported_tools": [],
        }
        catalog.write_text(json.dumps({"models": [
            dict(base_model, slug="step-settings-a"),
            dict(base_model, slug="step-settings-b"),
        ]}))
        config = Path(codex_home, "config.toml")
        body = config.read_text().replace('model = "mock-model"', 'model = "step-settings-a"')
        enabled = "false" if self.settings_scenario == "feature_disabled" else "true"
        prefix = (f"model_catalog_json = {json.dumps(str(catalog))}\n"
                  'model_reasoning_effort = "low"\n'
                  'model_reasoning_summary = "concise"\n')
        config.write_text(prefix + body + "\n[features]\n"
                          f"step_model_switching = {enabled}\nfast_mode = true\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["active", "feature_disabled", "assistant"],
                        required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--requests-file", type=Path, required=True)
    args = parser.parse_args()
    fixture = ActiveTurnSettingsFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        # Caller owns the provider. Closing stdin terminates it without a runtime
        # controller or any externally accessible control endpoint.
        for _line in sys.stdin:
            break
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
