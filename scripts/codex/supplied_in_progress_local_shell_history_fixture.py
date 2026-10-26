#!/usr/bin/env python3
"""Explicit current in_progress data through the ordinary Responses decoder.

Reuse the incomplete fixture's complete journey/oracles with only this declared
status selected. No app-server frames, shell execution or legacy emission.
"""
import model_fixture as model
import supplied_local_shell_history_fixture as history


class SuppliedInProgressLocalShellHistoryFixture(history.SuppliedLocalShellHistoryFixture):
    shell_status = "in_progress"


def response_events(index, completed_item):
    return history.response_events(index, completed_item, status="in_progress")


if __name__ == "__main__":
    model.response_events = response_events
    model.ModelFixture = SuppliedInProgressLocalShellHistoryFixture
    model.main()
