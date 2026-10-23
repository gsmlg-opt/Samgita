#!/usr/bin/env python3
"""Derive the pinned timeline export correction; never rewrite official JSON.

This is deliberately limited to one serializer/exporter disagreement. Rust
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


def write(vendor):
    value = derive(vendor)
    (vendor / SEMANTICS).write_text(encode(value))


def contract_hash(document, semantics):
    return hashlib.sha256(encode(corrected(document, semantics)).encode()).hexdigest()


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
