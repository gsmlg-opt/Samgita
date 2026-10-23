#!/usr/bin/env python3
"""Derive bounded pinned output export corrections; never rewrite official JSON.

This is deliberately limited to two serializer/exporter disagreements. Rust
serde supplies field naming, the executable's TypeScript export independently
confirms it, and the official JSON supplies all types and constraints.
"""

import hashlib
import json
import re

from fetch_pin import COMMIT, digest
from generate_gates import camel
from inventory import encode

SCHEMA = "v2/ThreadTimelineListResponse.json"
SEMANTICS = "source/output-semantics.json"
RUST = "source/thread.rs"
TYPESCRIPT = "source/output-typescript/ThreadTimelineEntry.ts"
REALTIME_RUST = "source/realtime.rs"
REALTIME_TYPESCRIPT = "source/output-typescript/ThreadRealtimeItem.ts"
REALTIME_SEMANTICS = "source/realtime-output-semantics.json"
REALTIME_SCHEMAS = ("ServerNotification.json", "v2/ThreadRealtimeItemStartedNotification.json",
                    "v2/ThreadRealtimeItemCompletedNotification.json", SCHEMA)


def derive(vendor):
    rust = (vendor / RUST).read_text()
    ts = (vendor / TYPESCRIPT).read_text()
    annotation = (r'#\[serde\(\s*tag = "type",\s*rename_all = "camelCase",\s*'
                  r'rename_all_fields = "camelCase"\s*\)\]\s*'
                  r'#\[ts\([^\n]+\)\]\s*pub enum ThreadTimelineEntry \{(.*?)\n\}')
    declaration = re.search(annotation, rust, re.S)
    if not declaration:
        raise ValueError("Pinned ThreadTimelineEntry serde naming changed")
    document = json.loads((vendor / "experimental" / SCHEMA).read_text())
    branches = document["definitions"]["ThreadTimelineEntry"]["oneOf"]
    corrections = {}
    for variant in ("TurnStarted", "TurnCompleted"):
        body = re.search(r'    ' + variant + r' \{(.*?)\n    \},', declaration[1], re.S)
        if not body or "serde" in body[1] or "schemars" in body[1]:
            raise ValueError("Unsupported timeline boundary field override: " + variant)
        fields = re.findall(r'\b(\w+): (String|u64|Option<i64>|TurnStatus|Option<TurnError>),', body[1])
        remainder = re.sub(r'#\[ts\([^\n]+\)\]|\b\w+: (?:String|u64|Option<i64>|TurnStatus|Option<TurnError>),', '', body[1])
        if remainder.strip() or len(fields) != len(dict(fields)):
            raise ValueError("Unsupported timeline boundary declaration: " + variant)
        wire = variant[0].lower() + variant[1:]
        choices = [branch for branch in branches if branch["properties"]["type"]["enum"] == [wire]]
        if len(choices) != 1 or set(choices[0]["properties"]) != {"type", *(name for name, _ in fields)}:
            raise ValueError("Official timeline export structure changed: " + variant)
        expected = []
        for name, kind in fields:
            native = camel(name)
            typescript = {"String": "string", "u64": "number", "Option<i64>": "number | null",
                          "TurnStatus": "TurnStatus", "Option<TurnError>": "TurnError | null"}[kind]
            expected.append(f"{native}: {typescript},")
            if native != name and f'#[ts(rename = "{native}"' not in body[1]:
                raise ValueError("Missing matching timeline TypeScript rename: " + name)
        ts_branch = '{ "type": "' + wire + '", ' + ' '.join(expected) + ' }'
        if ts_branch not in ts:
            raise ValueError("Rust/TypeScript timeline disagreement: " + variant)
        corrections[wire] = {name: camel(name) for name, _ in fields if camel(name) != name}
    return {
        "kind": "locally-derived-output-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_output_semantics.py",
        "source_sha256": {name: digest(vendor / name) for name in (RUST, TYPESCRIPT)},
        "schema": SCHEMA,
        "official_schema_sha256": digest(vendor / "experimental" / SCHEMA),
        "definition": "ThreadTimelineEntry",
        "renames": corrections,
        "semantics": "Only output contract property/required names change; values, types, bounds, nullability, unions and original exports remain unchanged.",
    }


def corrected(document, semantics):
    # Used for generated evidence metadata, not for transforming protocol values.
    document = json.loads(json.dumps(document))
    branches = document["definitions"][semantics["definition"]]["oneOf"]
    for branch in branches:
        renames = semantics["renames"].get(branch["properties"]["type"]["enum"][0], {})
        branch["properties"] = {renames.get(name, name): field for name, field in branch["properties"].items()}
        branch["required"] = [renames.get(name, name) for name in branch["required"]]
    return document


def derive_realtime(vendor):
    rust = (vendor / REALTIME_RUST).read_text()
    ts = (vendor / REALTIME_TYPESCRIPT).read_text()
    declaration = re.search(
        r'#\[serde\(\s*tag = "type",\s*rename_all = "camelCase",\s*'
        r'rename_all_fields = "camelCase"\s*\)\]\s*'
        r'#\[ts\([^\n]+\)\]\s*pub enum ThreadRealtimeItemContent \{(.*?)\n\}', rust, re.S)
    expected = 'turn_id: String, item_id: String, presentation: ThreadRealtimeBemItemPresentation,'
    body = re.search(r'    BemItemPromoted \{(.*?)\n    \},', declaration[1], re.S) if declaration else None
    if not body or ' '.join(body[1].split()) != expected:
        raise ValueError("Pinned realtime promotion serde declaration changed")
    if not re.search(r'#\[serde\(rename_all = "camelCase"\)\]\s*#\[ts\([^\n]+\)\]\s*'
                     r'pub struct ThreadRealtimeItem \{\s*pub id: String,\s*'
                     r'pub realtime_session_id: String,\s*#\[serde\(flatten\)\]\s*'
                     r'pub content: ThreadRealtimeItemContent,\s*\}', rust):
        raise ValueError("Pinned realtime flatten declaration changed")
    if '{ "type": "bemItemPromoted", turnId: string, itemId: string, presentation: ThreadRealtimeBemItemPresentation, }' not in ts:
        raise ValueError("Rust/TypeScript realtime promotion disagreement")
    reference = None
    hashes = {}
    for filename in REALTIME_SCHEMAS:
        document = json.loads((vendor / "experimental" / filename).read_text())
        definition = document["definitions"]["ThreadRealtimeItem"]
        choices = [branch for branch in definition["oneOf"]
                   if branch["properties"]["type"]["enum"] == ["bemItemPromoted"]]
        expected_properties = {"type": {"enum": ["bemItemPromoted"], "type": "string",
                                        "title": "BemItemPromotedThreadRealtimeItemType"},
                               "turn_id": {"type": "string"}, "item_id": {"type": "string"},
                               "presentation": {"$ref": "#/definitions/ThreadRealtimeBemItemPresentation"}}
        if (len(choices) != 1 or choices[0]["properties"] != expected_properties
                or set(choices[0]["required"]) != set(expected_properties)
                or reference is not None and reference != definition):
            raise ValueError("Official realtime export structure changed: " + filename)
        reference = definition
        hashes[filename] = digest(vendor / "experimental" / filename)
    return {
        "kind": "locally-derived-output-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_output_semantics.py",
        "source_sha256": {name: digest(vendor / name) for name in (REALTIME_RUST, REALTIME_TYPESCRIPT)},
        "schemas_sha256": hashes,
        "definition": "ThreadRealtimeItem",
        "renames": {"bemItemPromoted": {"turn_id": "turnId", "item_id": "itemId"}},
        "semantics": "Only output contract property/required names change; values, types, bounds, nullability, unions and original exports remain unchanged.",
    }


def corrections(vendor):
    return ((SEMANTICS, derive(vendor)), (REALTIME_SEMANTICS, derive_realtime(vendor)))


def applies(semantics, filename):
    return filename == semantics.get("schema") or filename in semantics.get("schemas_sha256", {})


def native_contract(document, filename, descriptors):
    for _, semantics in descriptors:
        if applies(semantics, filename):
            document = corrected(document, semantics)
    return document


def write(vendor):
    for relative, value in corrections(vendor):
        (vendor / relative).write_text(encode(value))


def contract_hash(document, semantics):
    return hashlib.sha256(encode(corrected(document, semantics)).encode()).hexdigest()


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
