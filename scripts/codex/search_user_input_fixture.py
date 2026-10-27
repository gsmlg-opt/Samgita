#!/usr/bin/env python3
"""Three Responses items; stock Codex owns input, search, IDs and persistence.

Only model-provider items are synthesized; no app-server frames are emitted.
"""
import argparse
import json
from pathlib import Path

from model_fixture import ModelFixture


WARMUP = "OWNED_SEARCH_INPUT_WAIT λ"
QUESTION = "OWNED_SEARCH_INPUT_QUESTION"
CALL_ID = "owned-search-input-choice"
WARMUP_DONE = "Owned searchable warmup done"
CHOICE_DONE = "Owned ordinary choice One complete"
ANSWERS = {"answers": {"fixture": {"answers": ["One"]}}}
QUESTIONS = [{
    "id": "fixture", "header": "Fixture", "question": "Choose fixture input",
    "options": [{"label": "One", "description": "Fixture one"},
                {"label": "Two", "description": "Fixture two"}],
}]


class SearchUserInputFixture(ModelFixture):
    def response_item(self, index, request):
        texts = [part.get("text") for item in request.get("input", [])
                 if item.get("role") == "user"
                 for part in item.get("content", []) if isinstance(part, dict)]
        outputs = [item for item in request.get("input", [])
                   if item.get("type") == "function_call_output"]
        assert index in (1, 2, 3), "Unexpected additional model request"
        expected = WARMUP if index == 1 else QUESTION
        assert texts and texts[-1] == expected, "Unexpected ordinary user input"

        if index == 3:
            assert len(outputs) == 1, "Expected exactly one native tool answer"
            output = outputs[0]
            assert output.get("call_id") == CALL_ID, "Unexpected tool answer identity"
            assert isinstance(output.get("output"), str), "Expected serialized native answer"
            assert json.loads(output["output"]) == ANSWERS, "Unexpected native choice answer"
        else:
            assert not outputs, "Unexpected tool answer before the ordinary choice"

        if index == 2:
            return {"type": "function_call", "name": "request_user_input",
                    "call_id": CALL_ID, "arguments": json.dumps({"questions": QUESTIONS})}
        text = WARMUP_DONE if index == 1 else CHOICE_DONE
        return {"type": "message", "role": "assistant", "id": f"owned-search-input-{index}",
                "content": [{"type": "output_text", "text": text}]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["assistant"], default="assistant")
    parser.add_argument("--workspace")
    parser.add_argument("--codex-home")
    parser.add_argument("--requests-file", type=Path)
    args = parser.parse_args()
    fixture = SearchUserInputFixture(args.scenario, args.workspace, args.requests_file).start()
    try:
        if args.codex_home:
            fixture.config(args.codex_home)
        print(json.dumps({"url": fixture.url}), flush=True)
        # The caller owns the provider and closes stdin to stop it.
        try:
            input()
        except EOFError:
            pass
    finally:
        fixture.close()


if __name__ == "__main__":
    main()
