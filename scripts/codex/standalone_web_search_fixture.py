#!/usr/bin/env python3
"""Local Responses and alpha/search peers; stock Codex owns all native events.

The four web.run calls use inert URLs and deterministic search response data.
This fixture never emits app-server frames or creates native history.
"""
import json
from pathlib import Path

import model_fixture


PAGE = "https://standalone-web.synthetic.invalid/owned-page"
COMMANDS = [
    {"search_query": [{"q": "Owned standalone first λ"}, {"q": "Owned second"}]},
    {"open": [{"ref_id": PAGE, "lineno": 7}]},
    {"find": [{"ref_id": "owned-search-reference", "pattern": "Owned needle 🙂"}]},
    {"time": [{"utc_offset": "+00:00"}]},
]
RESULTS = [
    [{"type": "text_result", "ref_id": "owned-search-reference", "url": PAGE,
      "title": "Owned result λ", "future_field": {"enabled": True,
      "nested": [None, 7, {"label": "🙂"}]}},
     {"type": "owned_future_result", "opaque": [False, {"preserved": "α"}]}],
    [], None, None,
]


class StandaloneWebFixture(model_fixture.ModelFixture):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.search_requests = []
        self.search_journal = self.requests_file.with_name("search-requests.json")
        self.search_journal.write_text("[]")
        provider, base = self, self.server.RequestHandlerClass

        class Handler(base):
            def do_POST(self):
                if self.path != "/v1/alpha/search":
                    return super().do_POST()
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 1_048_576:
                    self.send_response(400)
                    self.end_headers()
                    return
                request = json.loads(self.rfile.read(size))
                with provider.lock:
                    index = len(provider.search_requests)
                    assert index < len(COMMANDS), "Unexpected additional search request"
                    assert request["commands"] == COMMANDS[index]
                    response = {"output": f"Owned standalone result {index + 1} λ"}
                    if index != 2:
                        response["results"] = RESULTS[index]
                    provider.search_requests.append({
                        "path": self.path, "body": request, "response": response,
                        "turn_metadata": self.headers.get("x-codex-turn-metadata"),
                    })
                    temporary = provider.search_journal.with_suffix(".partial")
                    temporary.write_text(json.dumps(provider.search_requests, ensure_ascii=False))
                    temporary.replace(provider.search_journal)
                body = json.dumps(response, ensure_ascii=False).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server.RequestHandlerClass = Handler

    def response_item(self, index, request):
        assert 1 <= index <= 5, "Unexpected additional standalone web inference"
        if index <= 4:
            return {"type": "function_call", "namespace": "web", "name": "run",
                    "call_id": f"owned-standalone-web-{index}",
                    "arguments": json.dumps(COMMANDS[index - 1], ensure_ascii=False)}
        return {"type": "message", "role": "assistant", "id": "owned-standalone-answer",
                "content": [{"type": "output_text", "text": "Owned standalone web finished"}]}

    def config(self, codex_home):
        super().config(codex_home)
        path = Path(codex_home, "config.toml")
        body = path.read_text().replace('web_search = "disabled"', 'web_search = "cached"')
        path.write_text(body + "supports_standalone_web_search = true\n")


model_fixture.ModelFixture = StandaloneWebFixture

if __name__ == "__main__":
    model_fixture.main()
