"""Offline pin/inventory checks; these do not claim behavioral compatibility."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import generate_supplement
import generate_output_semantics
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
        actual["entries"][0].update(schema_sha256="same", native_output_sha256="before")
        expected["entries"][0].update(schema_sha256="same", native_output_sha256="after")
        self.assertEqual(inventory.merge_progress(expected, actual)["entries"][0]["state"], "missing")

    def test_offline_inventory_and_pin_check(self):
        result = subprocess.run([sys.executable, str(Path(inventory.__file__)), "--check"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_manifest_counts_every_pinned_wire_direction_and_result(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        entries = manifest["entries"]
        for filename, direction in inventory.DIRECTIONS.items():
            documents = inventory.schema_documents("experimental")
            paths = [filename + ".json", "supplemental/" + filename + ".json"]
            expected = {inventory.method_name(variant) for path in paths if path in documents
                        for variant in documents[path]["oneOf"]}
            actual = {entry["wire_name"] for entry in entries if entry["direction"] == direction}
            self.assertEqual(actual, expected)
        by_id = {entry["id"]: entry for entry in entries}
        for row in entries:
            if row["direction"] in {"client_response", "server_response"}:
                self.assertIn(row["request"], by_id)
                self.assertTrue(inventory.schema_file("experimental", row["schema"]).exists())

    def test_notification_source_parser_consumes_custom_and_bare_variants(self):
        source = (inventory.VENDOR / "source/common.rs").read_text()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / inventory.PROTOCOL / "common.rs"
            path.parent.mkdir(parents=True)
            path.write_text(source)
            notifications = inventory.source_notifications(root, "server_notification_definitions")
            self.assertEqual(len(notifications), 87)
            self.assertEqual(notifications["account/login/completed"]["variant"], "AccountLoginCompleted")
            self.assertEqual(inventory.source_notifications(root, "client_notification_definitions"),
                             {"initialized": {"variant": "Initialized", "params_rust": None}})
            for invalid in ("Future(v2::Future),", 'Future => "rawResponse/completed" (v2::Future),'):
                path.write_text(source.replace("server_notification_definitions! {",
                                               "server_notification_definitions! {\n" + invalid))
                with self.assertRaisesRegex(ValueError, "pinned notification declaration"):
                    inventory.source_notifications(root, "server_notification_definitions")

    def test_supplement_preserves_rust_optional_and_untagged_semantics(self):
        documents = generate_supplement.generate(inventory.VENDOR)
        auth = documents["v1/GetAuthStatusParams.json"]
        self.assertEqual(auth["required"], [])
        self.assertEqual(auth["properties"]["includeToken"],
                         {"anyOf": [{"type": "boolean"}, {"type": "null"}]})
        summary = documents["v1/GetConversationSummaryParams.json"]
        self.assertIn("anyOf", summary)
        self.assertNotIn("oneOf", summary)
        self.assertEqual(documents["v1/GitDiffToRemoteParams.json"]["required"], ["cwd"])
        self.assertEqual(documents["v1/ConversationGitInfo.json"]["required"], [])

    def test_supplement_refuses_unknown_constructs_and_rust_type_disagreement(self):
        for unsupported in ("Array<string>", "{ field?: string, }", "{ field: string, field: string, }"):
            with self.assertRaises(ValueError):
                generate_supplement.parse_type(unsupported)
        schema = generate_supplement.declaration(
            inventory.VENDOR / "source/supplemental-typescript/GetAuthStatusParams.ts", "GetAuthStatusParams")
        rust = (inventory.VENDOR / "source/v1.rs").read_text()
        for mutated in (rust.replace("pub include_token: Option<bool>", "pub include_token: bool"),
                        rust.replace("pub include_token:", '#[serde(default)]\n    pub include_token:')):
            with self.assertRaises(ValueError):
                generate_supplement.serde_presence(schema, mutated, "GetAuthStatusParams")

    def test_output_semantics_preserve_original_schema_and_rename_only_pinned_boundaries(self):
        semantics = generate_output_semantics.derive(inventory.VENDOR)
        path = inventory.VENDOR / "experimental" / generate_output_semantics.SCHEMA
        original_bytes = path.read_bytes()
        original = json.loads(original_bytes)
        corrected = generate_output_semantics.corrected(original, semantics)
        original_branches = original["definitions"]["ThreadTimelineEntry"]["oneOf"]
        branches = corrected["definitions"]["ThreadTimelineEntry"]["oneOf"]
        self.assertEqual(branches[:2], original_branches[:2])
        self.assertEqual(semantics["renames"]["turnStarted"],
                         {"turn_id": "turnId", "started_at": "startedAt"})
        self.assertEqual(semantics["renames"]["turnCompleted"],
                         {"turn_id": "turnId", "started_at": "startedAt",
                          "completed_at": "completedAt", "duration_ms": "durationMs"})
        for before, after in zip(original_branches[2:], branches[2:]):
            renames = semantics["renames"][before["properties"]["type"]["enum"][0]]
            self.assertEqual(after["properties"],
                             {renames.get(key, key): value for key, value in before["properties"].items()})
            self.assertEqual(after["required"], [renames.get(key, key) for key in before["required"]])
            self.assertEqual({k: v for k, v in before.items() if k not in {"properties", "required"}},
                             {k: v for k, v in after.items() if k not in {"properties", "required"}})
        self.assertEqual(path.read_bytes(), original_bytes)

    def test_output_semantics_refuse_unknown_serde_export_and_typescript_changes(self):
        files = (generate_output_semantics.RUST, generate_output_semantics.TYPESCRIPT,
                 "experimental/" + generate_output_semantics.SCHEMA)
        for relative, old, new in (
                (generate_output_semantics.RUST, 'rename_all_fields = "camelCase"', 'rename_all_fields = "snake_case"'),
                (generate_output_semantics.TYPESCRIPT, "turnId: string, startedAt:", "turn_id: string, startedAt:"),
                ("experimental/" + generate_output_semantics.SCHEMA, '"turn_id":', '"renamed_turn_id":')):
            with tempfile.TemporaryDirectory(prefix="codex-output-semantics-") as temporary:
                root = Path(temporary)
                for name in files:
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    text = (inventory.VENDOR / name).read_text()
                    if name == relative:
                        self.assertIn(old, text)
                        text = text.replace(old, new)
                    target.write_text(text)
                with self.assertRaises(ValueError):
                    generate_output_semantics.derive(root)

    def test_native_timeline_contract_metadata_retains_exported_field_identity(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        result = next(row for row in manifest["entries"] if row["id"] == "server_response:thread/timeline/list")
        self.assertEqual(result["output_semantics"], generate_output_semantics.SEMANTICS)
        self.assertEqual(len(result["native_output_sha256"]), 64)
        corrected = [row for row in manifest["schema_contracts"] if "native_wire_name" in row
                     and "/definitions/ThreadTimelineEntry/" in row["pointer"]]
        self.assertEqual(len(corrected), 6)
        for row in corrected:
            self.assertEqual(row["output_semantics"], generate_output_semantics.SEMANTICS)
            self.assertTrue(row["pointer"].endswith("/" + row["wire_name"]))
            self.assertNotEqual(row["wire_name"], row["native_wire_name"])

    def test_native_realtime_contract_metadata_retains_exported_field_identity(self):
        manifest = json.loads(inventory.MANIFEST.read_text())
        for identity in ("server_response:thread/timeline/list",
                         "server_notification:thread/realtime/item/started",
                         "server_notification:thread/realtime/item/completed"):
            row = next(row for row in manifest["entries"] if row["id"] == identity)
            self.assertIn("native_output_sha256", row)
        rows = [row for row in manifest["schema_contracts"]
                if "/definitions/ThreadRealtimeItem/" in row["pointer"]
                and row["wire_name"] in {"turn_id", "item_id"}]
        self.assertEqual(len(rows), 4)
        for row in rows:
            self.assertEqual(row.get("native_wire_name"), generate_output_semantics.camel(row["wire_name"]))

    def test_realtime_correction_preserves_exports_and_all_other_contract_constraints(self):
        semantics = generate_output_semantics.derive_realtime(inventory.VENDOR)
        for filename in generate_output_semantics.REALTIME_SCHEMAS:
            path = inventory.VENDOR / "experimental" / filename
            original_bytes = path.read_bytes()
            original = json.loads(original_bytes)
            corrected = generate_output_semantics.corrected(original, semantics)
            restored = json.loads(json.dumps(corrected))
            branch = restored["definitions"]["ThreadRealtimeItem"]["oneOf"][2]
            reverse = {"turnId": "turn_id", "itemId": "item_id"}
            branch["properties"] = {reverse.get(k, k): v for k, v in branch["properties"].items()}
            branch["required"] = [reverse.get(k, k) for k in branch["required"]]
            self.assertEqual(restored, original)
            self.assertEqual(path.read_bytes(), original_bytes)

    def test_realtime_derivation_refuses_source_typescript_and_export_drift(self):
        files = (generate_output_semantics.REALTIME_RUST, generate_output_semantics.REALTIME_TYPESCRIPT,
                 *("experimental/" + name for name in generate_output_semantics.REALTIME_SCHEMAS))
        for relative, old, new in (
                (files[0], 'rename_all_fields = "camelCase"', 'rename_all_fields = "snake_case"'),
                (files[0], 'turn_id: String,', '#[serde(rename = "other")] turn_id: String,'),
                (files[0], '#[serde(flatten)]', '#[serde(default)]'),
                (files[1], 'turnId: string,', 'turn_id: string,'),
                (files[2], '"item_id":', '"other_item_id":')):
            with tempfile.TemporaryDirectory(prefix="codex-realtime-semantics-") as temporary:
                root = Path(temporary)
                for name in files:
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    text = (inventory.VENDOR / name).read_text()
                    if name == relative:
                        self.assertIn(old, text)
                        text = text.replace(old, new)
                    target.write_text(text)
                with self.assertRaises(ValueError):
                    generate_output_semantics.derive_realtime(root)

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

    def test_initialized_notification_has_no_server_readiness_prerequisite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / inventory.PROTOCOL / "common.rs"
            path.parent.mkdir(parents=True)
            path.write_text((inventory.VENDOR / "source/common.rs").read_text())
            rows = {row["id"]: row for row in inventory.inventory(root)["entries"]}
        self.assertEqual(rows["client_notification:initialized"]["prerequisites"], [])
        self.assertEqual(rows["client_request:initialize"]["prerequisites"], [])
        self.assertEqual(rows["client_request:thread/list"]["prerequisites"], ["initialized"])


if __name__ == "__main__":
    unittest.main()
