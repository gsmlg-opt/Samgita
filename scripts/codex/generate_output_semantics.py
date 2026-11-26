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
                    "v2/ThreadRealtimeItemCompletedNotification.json",
                    "v2/ThreadRealtimeListResponse.json", SCHEMA)


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
    expected_variants = {
        "RealtimeSessionStarted": [],
        "Frame": [("channels", "ThreadRealtimeFrameChannels")],
        "TranscriptSegment": [("role", "ThreadRealtimeTranscriptRole"), ("text", "String")],
        "BemItemPromoted": [("turn_id", "String"), ("item_id", "String"),
                            ("presentation", "ThreadRealtimeBemItemPresentation")],
        "RealtimeSessionClosed": [("outcome", "ThreadRealtimeSessionOutcome")],
        "TurnInputAccepted": [("handoff_id", "String"), ("turn_id", "String"),
                              ("mode", "ThreadRealtimeHandoffMode"), ("source_event_ids", "Vec<String>"),
                              ("input_item_id", "String"), ("input", "String")],
        "SessionInputSaved": [("reason", "ThreadRealtimeSessionInputReason"),
                              ("source_event_ids", "Vec<String>"), ("input_item_id", "String"),
                              ("input", "String")],
    }
    if not declaration:
        raise ValueError("Pinned realtime content serde naming changed")
    variants = list(re.finditer(r'    (\w+)(?: \{(.*?)\n    \})?,', declaration[1], re.S))
    if ([variant[1] for variant in variants] != list(expected_variants)
            or re.sub(r'    (\w+)(?: \{(.*?)\n    \})?,', '', declaration[1], flags=re.S).strip()):
        raise ValueError("Pinned realtime content variants changed")
    corrections = {}
    for variant in variants:
        name, body = variant[1], variant[2] or ""
        fields = expected_variants[name]
        expected = ' '.join(f'{field}: {kind},' for field, kind in fields)
        if ' '.join(body.split()) != expected:
            raise ValueError("Pinned realtime content fields changed: " + name)
        wire = name[0].lower() + name[1:]
        ts_fields = ' '.join(f'{camel(field)}: ' +
                             {"String": "string", "Vec<String>": "Array<string>"}.get(kind, kind) + ','
                             for field, kind in fields)
        ts_branch = ('{ "type": "' + wire + '", ' + ts_fields + ' }' if fields
                     else '{ "type": "' + wire + '" }')
        if ts_branch not in ts:
            raise ValueError("Rust/TypeScript realtime content disagreement: " + name)
        renames = {field: camel(field) for field, _ in fields if camel(field) != field}
        if renames:
            corrections[wire] = renames
    common = re.search(r'#\[serde\(rename_all = "camelCase"\)\]\s*#\[ts\([^\n]+\)\]\s*'
                       r'pub struct ThreadRealtimeItem \{(.*?)\n\}', rust, re.S)
    expected_common = '''pub id: String,
        pub realtime_session_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(type = "number", optional)]
        pub observed_at_ms: Option<i64>,
        #[serde(flatten)]
        pub content: ThreadRealtimeItemContent,'''
    if not common or ' '.join(re.sub(r'///[^\n]*', '', common[1]).split()) != ' '.join(expected_common.split()):
        raise ValueError("Pinned realtime flatten or observation-time declaration changed")
    ts_without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', ts, flags=re.S)
    if ('export type ThreadRealtimeItem = { id: string, realtimeSessionId: string, '
            'observedAtMs?: number, } & (' not in ' '.join(ts_without_comments.split())):
        raise ValueError("Rust/TypeScript realtime observation-time disagreement")
    reference = None
    hashes = {}
    for filename in REALTIME_SCHEMAS:
        document = json.loads((vendor / "experimental" / filename).read_text())
        definition = document["definitions"]["ThreadRealtimeItem"]
        properties = definition["properties"]
        if (set(properties) != {"id", "realtimeSessionId", "observedAtMs"}
                or properties["id"] != {"type": "string"}
                or properties["realtimeSessionId"] != {"type": "string"}
                or {key: value for key, value in properties["observedAtMs"].items() if key != "description"}
                    != {"format": "int64", "type": ["integer", "null"]}
                or set(definition["required"]) != {"id", "realtimeSessionId"}
                or len(definition["oneOf"]) != len(expected_variants)
                or reference is not None and reference != definition):
            raise ValueError("Official realtime common export structure changed: " + filename)
        for branch, (variant, fields) in zip(definition["oneOf"], expected_variants.items()):
            wire = variant[0].lower() + variant[1:]
            expected_properties = {"type": {"enum": [wire], "type": "string",
                                            "title": variant + "ThreadRealtimeItemType"}}
            for field, kind in fields:
                expected_properties[field] = {"String": {"type": "string"},
                    "Vec<String>": {"type": "array", "items": {"type": "string"}}}.get(
                        kind, {"$ref": "#/definitions/" + kind})
            if (branch["properties"] != expected_properties
                    or set(branch["required"]) != set(expected_properties)):
                raise ValueError("Official realtime content export structure changed: " + filename + ":" + wire)
        reference = definition
        hashes[filename] = digest(vendor / "experimental" / filename)
    return {
        "kind": "locally-derived-output-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_output_semantics.py",
        "source_sha256": {name: digest(vendor / name) for name in (REALTIME_RUST, REALTIME_TYPESCRIPT)},
        "schemas_sha256": hashes,
        "definition": "ThreadRealtimeItem",
        "renames": corrections,
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
