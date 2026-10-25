#!/usr/bin/env python3
"""Responses tool call only; stock Codex runs clock.sleep and creates history.

Exactly one requested millisecond uses the native system clock. This peer never
emits app-server frames or writes native history.
"""
import re

import model_fixture


CALL = "owned-sleep-item"
ARGUMENTS = '{"duration_ms":1}'


class SleepItemFixture(model_fixture.ModelFixture):
    def response_item(self, index, request):
        if not 1 <= index <= 2:
            raise AssertionError("Unexpected additional sleep-item inference")
        outputs = [item for item in request["input"]
                   if item.get("type") == "function_call_output"]
        if index == 1:
            assert outputs == []
            return {"type": "function_call", "namespace": "clock", "name": "sleep",
                    "call_id": CALL, "arguments": ARGUMENTS}
        assert len(outputs) == 1 and outputs[0]["call_id"] == CALL
        assert re.fullmatch(r"Wall time: [0-9]+\.[0-9]{4} seconds\nSleep completed\.",
                            outputs[0]["output"])
        return super().response_item(index, request)


model_fixture.ModelFixture = SleepItemFixture

if __name__ == "__main__":
    model_fixture.main()
