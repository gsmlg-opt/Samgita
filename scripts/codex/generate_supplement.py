#!/usr/bin/env python3
"""Recover deliberately unexported contracts without changing official JSON.

The official JSON exporter omits three v1 requests/results and two internal
notification variants. This limited, fail-closed converter uses the executable's
generated TypeScript for structure, pinned Rust serde declarations for omission
semantics, and unchanged official JSON for shared types. It is not an official
JSON export or a general TypeScript/Rust schema compiler.
"""

import copy
import json
from pathlib import Path
import re

TYPES = (
    "GetConversationSummaryParams", "GetConversationSummaryResponse",
    "GitDiffToRemoteParams", "GitDiffToRemoteResponse", "GetAuthStatusParams",
    "GetAuthStatusResponse", "ConversationSummary", "ConversationGitInfo",
)
ALIASES = ("GitSha", "ThreadId", "AuthMode", "SessionSource")
REQUESTS = {
    "getConversationSummary": "GetConversationSummary",
    "gitDiffToRemote": "GitDiffToRemote", "getAuthStatus": "GetAuthStatus",
}
NOTIFICATIONS = {
    "rawResponseItem/completed": "RawResponseItemCompletedNotification",
    "rawResponse/completed": "RawResponseCompletedNotification",
}


def encode(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def split_union(text):
    depth, start, pieces = 0, 0, []
    for index, char in enumerate(text):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char == "|" and depth == 0:
            pieces.append(text[start:index].strip())
            start = index + 1
    if depth:
        raise ValueError("Unbalanced supplemental TypeScript")
    return pieces + [text[start:].strip()]


def parse_type(text):
    choices = split_union(text)
    if len(choices) > 1:
        # Rust untagged enums accept overlapping objects (first match wins).
        return {"anyOf": [parse_type(choice) for choice in choices]}
    if text in {"string", "boolean", "null"}:
        return {"type": text}
    if text.startswith("{") and text.endswith("}"):
        fields = re.findall(r'(\w+):\s*([^,{}]+),', text[1:-1])
        remainder = re.sub(r'\w+:\s*[^,{}]+,', '', text[1:-1]).strip()
        if remainder or not fields or len({name for name, _ in fields}) != len(fields):
            raise ValueError(f"Unsupported supplemental object: {text}")
        return {"type": "object", "properties": {name: parse_type(value.strip())
                for name, value in fields}, "required": [name for name, _ in fields]}
    if re.fullmatch(r'[A-Z]\w*', text):
        return {"$ref": "#/definitions/" + text}
    raise ValueError(f"Unsupported supplemental TypeScript type: {text}")


def declaration(path, name):
    text = path.read_text()
    matches = re.findall(r'export type ' + re.escape(name) + r' = ([\s\S]+?);', text)
    if len(matches) != 1:
        raise ValueError(f"Expected one exact upstream TypeScript declaration: {name}")
    return parse_type(matches[0].strip())


def serde_presence(schema, rust, name):
    if name == "GetConversationSummaryParams":
        # Verify the only supported enum, including both explicit field names.
        pattern = (r'#\[serde\(untagged\)\]\s*pub enum GetConversationSummaryParams\s*\{\s*'
                   r'RolloutPath\s*\{\s*#\[serde\(rename = "rolloutPath"\)\]\s*rollout_path: PathBuf,\s*\},\s*'
                   r'ThreadId\s*\{\s*#\[serde\(rename = "conversationId"\)\]\s*conversation_id: ThreadId,\s*\},\s*\}')
        if not re.search(pattern, rust):
            raise ValueError("Unsupported pinned untagged summary params declaration")
        expected = parse_type("{ rolloutPath: string, } | { conversationId: ThreadId, }")
        if schema != expected:
            raise ValueError("Rust/TypeScript untagged summary params disagreement")
        return schema
    match = re.search(r'#\[serde\(rename_all = "(camelCase|snake_case)"\)\]\s*pub struct '
                      + re.escape(name) + r'\s*\{([^}]+)\}', rust)
    if not match:
        raise ValueError(f"Unsupported pinned Rust supplemental declaration: {name}")
    naming, body = match.groups()
    fields = re.findall(r'pub (\w+): (Option<\w+>|\w+),', body)
    if re.sub(r'pub \w+: (?:Option<\w+>|\w+),', '', body).strip():
        raise ValueError(f"Unsupported serde attributes/type/default: {name}")
    expected, required = set(), []
    for field, kind in fields:
        wire = field if naming == "snake_case" else re.sub(r'_(\w)', lambda m: m[1].upper(), field)
        expected.add(wire)
        optional = kind.startswith("Option<")
        inner = kind[7:-1] if optional else kind
        scalar = {"PathBuf": "string", "String": "string", "bool": "boolean"}.get(inner, inner)
        expected_type = parse_type(scalar + " | null" if optional else scalar)
        if schema.get("properties", {}).get(wire) != expected_type:
            raise ValueError(f"Rust/TypeScript field type disagreement: {name}.{wire}")
        if not optional:
            required.append(wire)
    if expected != set(schema.get("properties", {})):
        raise ValueError(f"Rust/TypeScript field disagreement: {name}")
    schema["required"] = required
    return schema


def generate(vendor):
    ts = vendor / "source/supplemental-typescript"
    rust = (vendor / "source/v1.rs").read_text()
    export = (vendor / "source/export.rs").read_text()
    for constant, expected in (("V1_CLIENT_REQUEST_METHODS", set(REQUESTS)),
                               ("EXCLUDED_SERVER_NOTIFICATION_METHODS_FOR_JSON", set(NOTIFICATIONS))):
        match = re.search(r'const ' + constant + r':[^=]+=\s*&?\s*\[([^;]+)\];', export)
        if not match or set(re.findall(r'"([^\"]+)"', match[1])) != expected:
            raise ValueError(f"Pinned export exclusion list changed: {constant}")
    documents = {str(path.relative_to(vendor / "experimental")): json.loads(path.read_text())
                 for path in sorted((vendor / "experimental").rglob("*.json"))}
    definitions = {name: serde_presence(declaration(ts / (name + ".ts"), name), rust, name)
                   for name in TYPES}
    definitions["GitSha"] = declaration(ts / "GitSha.ts", "GitSha")

    def ensure_reference(name):
        if name in definitions:
            return
        candidates = [(doc, doc["definitions"][name]) for path, doc in documents.items()
                      if not path.startswith("codex_app_server_protocol.")
                      and name in doc.get("definitions", {})]
        if not candidates or len({encode(value) for _, value in candidates}) != 1:
            raise ValueError(f"Missing or ambiguous official definition: {name}")
        doc, schema = candidates[0]
        definitions[name] = copy.deepcopy(schema)
        for nested in references(schema):
            ensure_reference(nested)

    for name in list(definitions):
        for reference in references(definitions[name]):
            ensure_reference(reference)

    def document(title, schema):
        return {"$schema": "http://json-schema.org/draft-07/schema#",
                "$comment": "Samgita-derived supplement; not an official JSON export. See source/supplemental-origin.json.",
                "title": title, **schema, "definitions": copy.deepcopy(definitions)}

    ensure_reference("RequestId")
    variants = [{"type": "object", "title": variant + "Request",
                 "properties": {"id": {"$ref": "#/definitions/RequestId"},
                                "method": {"type": "string", "enum": [wire]},
                                "params": {"$ref": "#/definitions/" + variant + "Params"}},
                 "required": ["id", "method", "params"]}
                for wire, variant in REQUESTS.items()]
    result = {"ClientRequest.json": document("SupplementalClientRequest", {"oneOf": variants})}
    for name in TYPES:
        result["v1/" + name + ".json"] = document(name, definitions[name])

    variants = []
    for wire, name in NOTIFICATIONS.items():
        doc = documents["v2/" + name + ".json"]
        for nested, schema in doc.get("definitions", {}).items():
            if nested in definitions and definitions[nested] != schema:
                raise ValueError("Supplemental official definition collision: " + nested)
            definitions[nested] = copy.deepcopy(schema)
        definitions[name] = {k: v for k, v in doc.items() if k not in {"$schema", "title", "definitions"}}
        variants.append({"type": "object", "title": name,
                         "properties": {"method": {"type": "string", "enum": [wire]},
                                        "params": {"$ref": "#/definitions/" + name}},
                         "required": ["method", "params"]})
    result["ServerNotification.json"] = document("SupplementalServerNotification", {"oneOf": variants,
        "properties": documents["ServerNotification.json"]["properties"]})
    return result


def references(schema):
    if isinstance(schema, dict):
        if "$ref" in schema:
            ref = schema["$ref"]
            if not ref.startswith("#/definitions/"):
                raise ValueError("Nonlocal supplemental reference: " + ref)
            yield ref.removeprefix("#/definitions/")
        for value in schema.values():
            yield from references(value)
    elif isinstance(schema, list):
        for value in schema:
            yield from references(value)


def write(vendor):
    for relative, schema in generate(vendor).items():
        target = vendor / "supplemental" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(encode(schema))


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
