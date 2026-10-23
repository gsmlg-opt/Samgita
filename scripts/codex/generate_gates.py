#!/usr/bin/env python3
"""Extract pinned Rust experimental field presence semantics, not schema guesses."""

import json
from pathlib import Path
import re
import shutil

from fetch_pin import CACHE, COMMIT, digest
from inventory import PROTOCOL, VENDOR, encode


def camel(name):
    first, *tail = name.split("_")
    return first + "".join(part[:1].upper() + part[1:] for part in tail)


def field_type(text, start):
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        depth += char in "<([{"
        depth -= char in ">)]}"
        if char == "," and depth == 0:
            return text[start:index].strip()
    raise ValueError("Unterminated Rust field")


def body_end(text, start):
    depth, quoted, escaped = 1, False, False
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        else:
            depth += char == "{"
            depth -= char == "}"
            if depth == 0:
                return index
    raise ValueError("Unterminated Rust declaration")


def extract(source):
    types = {}
    for path in sorted((source / PROTOCOL).rglob("*.rs")):
        original = path.read_text()
        # The pinned protocol declarations use ordinary line/block comments.
        text = re.sub(r"/\*.*?\*/|//[^\n]*", lambda match: "\n" * match.group().count("\n"), original, flags=re.S)
        for declaration in re.finditer(r"(?m)^pub (struct|enum) (\w+)[^{;\n]*\{", text):
            kind, name = declaration.groups()
            body = text[declaration.end():body_end(text, declaration.end())]
            fields = {}
            variants = []
            for annotation in re.finditer(r'#\[experimental\((nested|"[^"]+")\)\]', body):
                value = annotation.group(1)
                remaining = body[annotation.end():]
                reason = None if value == "nested" else json.loads(value)
                if kind == "struct":
                    match = re.search(r"pub\s+(\w+)\s*:\s*", remaining)
                    if not match:
                        raise ValueError(f"Cannot bind experimental field: {path}:{name}")
                    rust_name = match.group(1)
                    rust_type = field_type(remaining, match.end())
                    attrs = remaining[:match.start()]
                    rename = re.search(r'#\[serde\(rename\s*=\s*"([^"]+)"', attrs)
                    field = rename.group(1) if rename else camel(rust_name)
                    compact = re.sub(r"\s+", "", rust_type)
                    if value == "nested":
                        presence = "nested"
                    elif "deserialize_double_option" in attrs:
                        presence = "present"
                    elif "deserialize_empty_path_as_none" in attrs:
                        presence = "non_null_nonempty_string"
                    elif compact.startswith("Option<"):
                        presence = "non_null"
                    elif compact.startswith(("Vec<", "HashMap<", "BTreeMap<")):
                        presence = "nonempty_collection"
                    elif compact == "bool":
                        presence = "true"
                    else:
                        presence = "present"
                    fields[field] = {"presence": presence, "reason": reason,
                                     "rust_type": rust_type,
                                     "source_path": str(path.relative_to(source))}
                else:
                    rest = re.sub(r"#\[.*?\]\s*", "", remaining, flags=re.S)
                    match = re.match(r"\s*(\w+)", rest)
                    if not match:
                        raise ValueError(f"Cannot bind experimental variant: {path}:{name}")
                    variant = match.group(1)
                    variant_attrs = remaining[:remaining.find(variant)]
                    rename = re.search(r'#\[serde\(rename\s*=\s*"([^"]+)"', variant_attrs)
                    prefix = text[max(0, declaration.start()-450):declaration.start()]
                    tag = re.findall(r'#\[serde\(tag\s*=\s*"([^"]+)"', prefix)
                    variants.append({"variant": variant, "reason": reason,
                                     "wire_name": rename.group(1) if rename else variant[:1].lower() + variant[1:],
                                     "tag": tag[-1] if tag else None})
            if fields or variants:
                types[name] = {"fields": fields, "variants": variants}
    return {"upstream_commit": COMMIT,
            "derive_source": "source/experimental-api-macros.rs", "types": types}


def generate(source):
    result = extract(source)
    (VENDOR / "source/experimental-semantics.json").write_text(encode(result))
    shutil.copyfile(source / "codex-rs/codex-experimental-api-macros/src/lib.rs",
                    VENDOR / "source/experimental-api-macros.rs")
    provenance_path = VENDOR / "provenance.json"
    provenance = json.loads(provenance_path.read_text())
    for relative in ("source/experimental-semantics.json", "source/experimental-api-macros.rs"):
        provenance["files_sha256"][relative] = digest(VENDOR / relative)
    provenance_path.write_text(encode(provenance))
    print(f"Extracted {sum(len(t['fields']) for t in result['types'].values())} fields and "
          f"{sum(len(t['variants']) for t in result['types'].values())} enum variants")


if __name__ == "__main__":
    generate(CACHE / f"codex-{COMMIT}")
