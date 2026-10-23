"""The local Responses fixture must distinguish compaction from ordinary turns."""
import json
from pathlib import Path
import tempfile
import unittest
from urllib.request import Request, urlopen

from model_fixture import ModelFixture


class CompactionFixtureTest(unittest.TestCase):
    def test_existing_item_overrides_keep_their_single_index_contract(self):
        class ExistingFixture(ModelFixture):
            def item(self, index):
                return {"type": "message", "id": f"existing-{index}"}

        fixture = ExistingFixture()
        try:
            self.assertEqual(fixture.response_item(2, {"input": []}),
                             {"type": "message", "id": "existing-2"})
        finally:
            fixture.server.server_close()

    def test_real_http_route_uses_trigger_instead_of_request_count(self):
        with tempfile.TemporaryDirectory(prefix="samgita-compact-provider-") as root:
            captured = Path(root) / "requests.json"
            fixture = ModelFixture("compaction", requests_file=captured).start()
            try:
                bodies = [
                    {"input": [{"type": "compaction_trigger"}]},
                    {"input": [{"type": "message", "content": []}]},
                    {"input": [{"type": "compaction_trigger"}]},
                ]
                for body, expected in zip(bodies, ["compaction", "message", "compaction"]):
                    request = Request(fixture.url + "/v1/responses",
                                      data=json.dumps(body).encode(),
                                      headers={"Content-Type": "application/json"})
                    with urlopen(request, timeout=5) as response:
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.headers["Content-Type"], "text/event-stream")
                        events = [json.loads(line.removeprefix("data: "))
                                  for line in response.read().decode().splitlines()
                                  if line.startswith("data: ")]
                    items = [event["item"] for event in events
                             if event["type"] == "response.output_item.done"]
                    self.assertEqual(len(items), 1)
                    self.assertEqual(items[0]["type"], expected)
                    if expected == "compaction":
                        self.assertEqual(items[0]["encrypted_content"],
                                         "SYNTHETIC_COMPACTION_CHECKPOINT")
                self.assertEqual(json.loads(captured.read_text()), bodies)
            finally:
                fixture.close()


if __name__ == "__main__":
    unittest.main()
