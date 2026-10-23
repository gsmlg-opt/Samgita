#!/usr/bin/env python3
"""Generate synthetic schema examples, never claimed as Codex behavior evidence."""

import json
import math
from pathlib import Path
import re

from inventory import MANIFEST, ROOT, encode, schema_documents

OUT = ROOT / "apps/samgita_protocol_codex/test/fixtures/native/contracts.json"


def pointer(document, path):
    current = document
    for token in path.lstrip("/").split("/") if path else []:
        key = token.replace("~1", "/").replace("~0", "~")
        current = current[int(key)] if isinstance(current, list) else current[key]
    return current


def sample(schema, root, depth=0):
    if depth > 64:
        raise ValueError("Recursive required schema has no bounded synthetic sample")
    if schema is True:
        return None
    if schema is False:
        raise ValueError("Uninhabited false schema")
    if "$ref" in schema:
        return sample(pointer(root, schema["$ref"][1:]), root, depth + 1)
    if "enum" in schema:
        return schema["enum"][0]
    kind = schema.get("type")
    if isinstance(kind, list):
        kind = "null" if "null" in kind else kind[0]
    if kind == "null":
        return None
    if kind == "boolean":
        return False
    if kind == "string":
        return "fixture" + "x" * max(0, schema.get("minLength", 0) - 7)
    if kind in ("integer", "number"):
        return max(0, math.ceil(schema.get("minimum", 0)))
    if kind == "array":
        return [sample(schema.get("items", True), root, depth + 1) for _ in range(schema.get("minItems", 0))]
    result = {name: sample(schema["properties"][name], root, depth + 1)
              for name in schema.get("required", []) if name in schema.get("properties", {})}
    object_seen = False
    for keyword in ("oneOf", "anyOf", "allOf"):
        if keyword not in schema:
            continue
        choices = schema[keyword] if keyword == "allOf" else schema[keyword][:1]
        for choice in choices:
            child = sample(choice, root, depth + 1)
            if isinstance(child, dict):
                object_seen = True
                result.update(child)
            elif not result:
                return child
    return result if kind == "object" or "properties" in schema or result or object_seen else None


def main():
    manifest = json.loads(MANIFEST.read_text())
    documents = schema_documents("experimental")
    fixtures = []
    for row in manifest["entries"]:
        if row["direction"] not in {"client_request", "server_request", "server_notification", "client_notification", "server_response", "client_response"}:
            continue
        document = documents[row["schema"]]
        schema = pointer(document, row.get("schema_pointer", ""))
        fixtures.append({"id": row["id"], "direction": row["direction"], "method": row["wire_name"],
                         "value": sample(schema, document)})
    contracts = []
    for row in manifest["schema_contracts"]:
        document = documents[row["schema"]]
        path = row["pointer"]
        schema = pointer(document, path)
        if re.search(r"/enum/\d+$", path):
            value = schema
            path = re.sub(r"/enum/\d+$", "", path)
        else:
            value = sample(schema, document) if schema is not False else None
        contracts.append({"id": row["id"], "schema": row["schema"], "pointer": path,
                          "value": value, "valid": schema is not False})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(encode({"upstream_version": "0.163.0", "evidence_kind": "synthetic-schema-only",
                          "messages": fixtures, "contracts": contracts}))
    print(f"Generated {len(fixtures)} message examples and {len(contracts)} field/variant examples")


if __name__ == "__main__":
    main()
