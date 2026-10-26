#!/usr/bin/env python3
"""Derive bounded pinned input corrections, retaining official JSON.

Cover thread/start's custom dynamic-tool decoder and thread/resume's compaction
input alias. These describe accepted input, never outgoing-value normalization.
"""

import json
import re

from fetch_pin import COMMIT, digest
from generate_gates import camel
from inventory import encode

SEMANTICS = "source/input-semantics.json"
RUST = "source/dynamic-tools.rs"
THREAD = "source/thread.rs"
SOURCES = {
    RUST: "d73d51aa0cd0e6318d6fc1faa890a3524301af0c3ba2b2dc0d071728b2caa402",
    THREAD: "8c10510bb88990aa0f0105e7a85c0bb7859db7232be29f84a6c66693600ef502",
}
SCHEMAS = ("ClientRequest.json", "v2/ThreadStartParams.json")
RESPONSE_SEMANTICS = "source/response-item-input-semantics.json"
MODELS = "source/models.rs"
MODELS_SHA256 = "df9a3da250376d86203a8a1219b2e4b5353a62274d094bb36998560433bd58eb"
RESPONSE_SCHEMAS = ("ClientRequest.json", "v2/ThreadResumeParams.json")


def derive(vendor):
    for name, expected in SOURCES.items():
        if digest(vendor / name) != expected:
            raise ValueError("Pinned dynamic-tool decoder or field declaration changed: " + name)
    rust = (vendor / RUST).read_text()
    declaration = re.search(
        r'#\[derive\(Deserialize\)\]\s*#\[serde\(rename_all = "camelCase"\)\]\s*'
        r'struct LegacyDynamicToolSpec \{\n(.*?)\n\}', rust, re.S)
    if not declaration:
        raise ValueError("Missing native legacy dynamic-tool declaration")
    fields = re.findall(r'    (\w+): (String|JsonValue|Option<String>|Option<bool>),', declaration[1])
    if ("\n".join(f"    {name}: {kind}," for name, kind in fields) != declaration[1]
            or len(fields) != 6 or len(dict(fields)) != 6):
        raise ValueError("Unsupported legacy dynamic-tool fields or serde annotations")
    types = {
        "String": {"type": "string"},
        "JsonValue": True,
        "Option<String>": {"type": ["string", "null"]},
        "Option<bool>": {"type": ["boolean", "null"]},
    }
    legacy = {
        "type": "object",
        "required": [camel(name) for name, kind in fields if not kind.startswith("Option<")],
        "properties": {"type": False, **{camel(name): types[kind] for name, kind in fields}},
    }
    hashes = {}
    for name in SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        definition = document["definitions"]["ThreadStartParams"] if name == SCHEMAS[0] else document
        if definition["properties"]["dynamicTools"] != {
                "default": None, "items": {"$ref": "#/definitions/DynamicToolSpec"},
                "type": ["array", "null"]}:
            raise ValueError("Official dynamicTools field contract changed: " + name)
        hashes[name] = digest(path)
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "method": "thread/start",
        "definition": "ThreadStartParams",
        "field": "dynamicTools",
        "semantics": "The pinned field custom deserializer accepts homogeneous legacy flat declarations as well as canonical tagged declarations. Validate the original values without normalization. Namespace grouping, default exposure and flag precedence belong to the native decoder. A separate list-level check mirrors native canonical/legacy format consistency, including nested tool signatures.",
        "source_sha256": SOURCES,
        "schemas_sha256": hashes,
        "legacy_schema": legacy,
    }


def derive_response_item(vendor):
    sources = {MODELS: MODELS_SHA256, THREAD: SOURCES[THREAD]}
    for name, expected in sources.items():
        if digest(vendor / name) != expected:
            raise ValueError("Pinned supplied-history decoder or variant changed: " + name)
    rust = (vendor / MODELS).read_text()
    if '#[serde(tag = "type", rename_all = "snake_case")]\npub enum ResponseItem {' not in rust:
        raise ValueError("Pinned ResponseItem tagging changed")
    aliases = re.findall(r'#\[serde\(alias = "([^"\n]+)"\)\]\s*Compaction \{', rust)
    if aliases != ["compaction_summary"]:
        raise ValueError("Pinned compaction input alias changed")
    hashes = {}
    for name in RESPONSE_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        branches = document["definitions"]["ResponseItem"]["oneOf"]
        compaction = [branch for branch in branches if branch["title"] == "CompactionResponseItem"]
        if len(compaction) != 1 or compaction[0]["properties"]["type"]["enum"] != ["compaction"]:
            raise ValueError("Official canonical compaction contract changed: " + name)
        hashes[name] = digest(path)
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "method": "thread/resume",
        "definition": "ResponseItem",
        "canonical_tag": "compaction",
        "input_aliases": aliases,
        "source_sha256": sources,
        "schemas_sha256": hashes,
        "semantics": "Accept the pinned serde input alias only on the canonical Compaction input branch, retaining every original property/type constraint. Never rewrite the caller's tag or change output contracts; native decoding, serialization and history persistence own canonicalization.",
    }


def corrections(vendor):
    return ((SEMANTICS, derive(vendor)), (RESPONSE_SEMANTICS, derive_response_item(vendor)))


def write(vendor):
    for relative, value in corrections(vendor):
        (vendor / relative).write_text(encode(value))


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
