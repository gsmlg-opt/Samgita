"""Offline pin/inventory checks; these do not claim behavioral compatibility."""

import json
from pathlib import Path
import subprocess
import sys
import unittest

import inventory


class InventoryTest(unittest.TestCase):
    def test_boolean_field_schema_is_preserved(self):
        rows = inventory.schema_contracts({"properties": {"opaque": True, "forbidden": False}}, None, "sample.json")
        self.assertEqual({row["wire_name"] for row in rows}, {"opaque", "forbidden"})
        self.assertTrue(all(row["experimental"] for row in rows))

    def test_union_field_gates_survive_stable_variant_removal(self):
        stable_variant = {"title": "Known", "properties": {"value": {"type": "string"}}}
        full_variant = {"title": "Known", "properties": {"value": {"type": "string"}, "preview": {"type": "boolean"}}}
        full = {"oneOf": [{"title": "Preview", "type": "null"}, full_variant]}
        stable = {"oneOf": [stable_variant]}
        rows = {row["pointer"]: row for row in inventory.schema_contracts(full, stable, "sample.json")}
        self.assertTrue(rows["/oneOf/0"]["experimental"])
        self.assertFalse(rows["/oneOf/1"]["experimental"])
        self.assertFalse(rows["/oneOf/1/properties/value"]["experimental"])
        self.assertTrue(rows["/oneOf/1/properties/preview"]["experimental"])

    def test_missing_null_and_explicit_default_are_separate(self):
        rows = inventory.schema_contracts({"properties": {"optional": {"type": "string"},
                 "nullable": {"type": ["string", "null"]}, "defaulted": {"type": "boolean", "default": False}},
                 "required": ["nullable"]}, {}, "sample.json")
        fields = {row["wire_name"]: row for row in rows}
        self.assertFalse(fields["optional"]["required"])
        self.assertFalse(fields["optional"]["nullable"])
        self.assertFalse(fields["optional"]["has_default"])
        self.assertTrue(fields["nullable"]["required"])
        self.assertTrue(fields["nullable"]["nullable"])
        self.assertTrue(fields["defaulted"]["has_default"])
        self.assertIs(fields["defaulted"]["default"], False)

    def test_changed_contract_cannot_retain_verified_evidence(self):
        actual = {"entries": [{"id": "x", "schema_sha256": "before", "state": "verified", "evidence": ["old"]}], "schema_contracts": []}
        expected = {"entries": [{"id": "x", "schema_sha256": "after", "state": "missing"}], "schema_contracts": []}
        self.assertEqual(inventory.merge_progress(expected, actual)["entries"][0]["state"], "missing")

    def test_offline_inventory_and_pin_check(self):
        result = subprocess.run([sys.executable, str(Path(inventory.__file__)), "--check"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_manifest_counts_every_pinned_wire_direction_and_result(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        entries = manifest["entries"]
        for filename, direction in inventory.DIRECTIONS.items():
            schema = json.loads((inventory.VENDOR / "experimental" / (filename + ".json")).read_text())
            expected = {inventory.method_name(variant) for variant in schema["oneOf"]}
            actual = {entry["wire_name"] for entry in entries if entry["direction"] == direction}
            self.assertEqual(actual, expected)
        by_id = {entry["id"]: entry for entry in entries}
        for row in entries:
            if row["direction"] in {"client_response", "server_response"}:
                self.assertIn(row["request"], by_id)
                self.assertTrue((inventory.VENDOR / "experimental" / row["schema"]).exists())

    def test_unfinished_requirements_fail_full_compatibility_gate(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        if any(row["state"] != "verified" for section in ("entries", "schema_contracts") for row in manifest[section]):
            result = subprocess.run([sys.executable, str(Path(inventory.__file__)), "--require-verified"], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unverified requirements remain", result.stderr)

    def test_notification_runtime_gates_do_not_come_from_schema_membership(self):
        profiles = []
        for profile in ("stable", "experimental"):
            schema = json.loads((inventory.VENDOR / profile / "ServerNotification.json").read_text())
            profiles.append({inventory.method_name(variant) for variant in schema["oneOf"]})
        self.assertEqual(profiles[0], profiles[1])
        self.assertEqual(len(profiles[0]), 85)

        manifest = json.loads(inventory.MANIFEST.read_text())
        notifications = {row["wire_name"]: row for row in manifest["entries"]
                         if row["direction"] == "server_notification"}
        self.assertEqual(sum(row["experimental"] for row in notifications.values()), 24)
        source_lines = (inventory.VENDOR / "source/common.rs").read_text().splitlines()
        for row in notifications.values():
            if row["experimental"]:
                self.assertEqual(row["capabilities"], ["experimentalApi"])
                self.assertEqual(source_lines[row["source"]["source_line"] - 1].strip(),
                                 '#[experimental("' + row["source"]["experimental_reason"] + '")]')
            else:
                self.assertEqual(row["capabilities"], [])
        for method in ("thread/settings/updated", "process/outputDelta", "thread/realtime/started"):
            self.assertTrue(notifications[method]["experimental"])
        for method in ("item/plan/delta", "remoteControl/status/changed"):
            self.assertFalse(notifications[method]["experimental"])

    def test_server_request_export_status_does_not_require_runtime_capability(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        by_id = {row["id"]: row for row in manifest["entries"]}
        for direction in ("server_request", "client_response"):
            self.assertTrue(by_id[direction + ":currentTime/read"]["experimental"])
            for row in manifest["entries"]:
                if row["direction"] == direction:
                    self.assertEqual(row["capabilities"], [])


if __name__ == "__main__":
    unittest.main()
