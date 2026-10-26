#!/usr/bin/env python3
"""Derive the pinned legacy dynamic-tool input contract, retaining official JSON.

Only thread/start's source-declared custom decoder is covered. This describes
accepted input, not native normalization or a caller's outgoing wire value.
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


def write(vendor):
    (vendor / SEMANTICS).write_text(encode(derive(vendor)))


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
