#!/usr/bin/env python3
"""Generate/check the exhaustive pinned Codex schema inventory, without Mix.

--generate executes the hash-pinned official binary in an empty CODEX_HOME,
vendors stable and experimental schema bundles, and regenerates the manifest.
--check is offline: it checks all pinned artifacts and the generated inventory.
--require-verified additionally fails if any requirement lacks real evidence.
Progress fields survive regeneration; schema additions cannot inherit old evidence.
"""

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from fetch_pin import (ROOT, VERSION, COMMIT, TAG_OBJECT, ASSET, ARCHIVE_SHA256,
                       BINARY_SHA256, SOURCE_SHA256, CACHE, digest)

VENDOR = ROOT / "apps/samgita_protocol_codex/priv/upstream" / VERSION
MANIFEST = ROOT / "docs/codex-app-server/compatibility-manifest.json"
PROTOCOL = "codex-rs/app-server-protocol/src/protocol"
DIRECTIONS = {"ClientRequest": "client_request", "ServerRequest": "server_request",
              "ClientNotification": "client_notification", "ServerNotification": "server_notification"}
PROGRESS = {"state", "evidence", "limitations", "implementation_module", "tests", "transport_coverage"}
LIFECYCLE = {
    "initialization-order": "initialize response precedes initialized; other requests require initialization; repeated initialize rejects",
    "experimental-negotiation": "experimental methods and source-active gated fields/enum variants require capabilities.experimentalApi; false bools, null standard options and empty nonoptional collections are inactive; double options and custom deserializers follow pinned Rust semantics",
    "notification-opt-out": "respect initialize optOutNotificationMethods, preserve unknown notifications when received",
    "stdio-framing": "one JSON object per line; handle partial and coalesced reads; stderr is not protocol",
    "websocket-framing": "one JSON object per text message; ping/pong/close handled independently",
    "bidirectional-correlation": "request IDs are scoped by direction and connection; out-of-order responses settle once",
    "unknown-server-request": "explicit unsupported-method error; never approve or silently discard",
    "server-request-resolution": "serverRequest/resolved invalidates corresponding interaction; late responses cannot authorize a new one",
    "approval-decisions": "preserve every decision variant and edits; require explicit authorized handler",
    "bounded-buffering": "bound pending calls, frames, and notifications; explicit overflow and recovery gap; no silent critical drops",
    "deadline-uncertainty": "timeout/disconnect of mutation is uncertain; never resend as an automatic recovery action",
    "owned-process-exit": "reap only owned child resources; settle pending requests on exit; borrowed endpoints remain untouched",
    "disconnect-reconnect": "new connection initializes separately; no fabricated replay or upstream deduplication guarantees",
    "turn-interrupt": "turn/interrupt is explicit application cancellation; transport closure is not proof of turn cancellation",
    "item-lifecycle": "preserve full typed item lifecycle, identifiers, tool/approval associations and upstream ordering",
    "error-preservation": "retain JSONRPC error code/message/data and turn errors without rewriting semantics",
    "missing-null-default": "retain absent versus null versus explicit values; apply no undocumented driver defaults",
    "credential-isolation": "isolate CODEX_HOME and environment; do not emit credentials or complete sensitive params into logs",
    "capability-backend-success": "disabled/error evidence does not qualify enabled success paths; external prerequisites remain blocked",
    "samgita-authorization": "native operation access respects project membership, task fences and separately authorized human interactions",
    "task-acceptance-separation": "Codex execution completion does not accept a Samgita task",
}


def encode(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def fresh(identifier, direction, wire, module):
    return {"id": identifier, "direction": direction, "wire_name": wire,
            "state": "missing", "implementation_module": module,
            "transport_coverage": [], "evidence": [], "limitations": [],
            "tests": {"planned": ["schema-contract", "deterministic-fault", "real-pinned-binary"], "verified": []}}


def method_name(variant):
    return variant["properties"]["method"]["enum"][0]


def source_requests(source, macro):
    text = (source / PROTOCOL / "common.rs").read_text()
    start = text.index(macro + "! {") + len(macro + "! {")
    end = text.index("\n}", start)
    block = text[start:end]
    result = {}
    pattern = r'(\w+)\s*(?:=>\s*"([^"]+)")?\s*\{\s*params:\s*(.*?),\s*(?:inspect_params:\s*(true),\s*)?(?:serialization:\s*(.*?),\s*)?(?:manual_payload_conversion:\s*\w+,\s*)?response:\s*(\S+),\s*\}'
    for match in re.finditer(pattern, block, re.S):
        variant, wire, params, inspect, serial, response = match.groups()
        wire = wire or variant[0].lower() + variant[1:]
        result[wire] = {"variant": variant, "params_rust": params,
                        "response_rust": response, "serialization_scope": serial,
                        "inspect_params_for_experimental_fields": bool(inspect),
                        "legacy": "v1::" in params and wire != "initialize",
                        "source_line": text[:start + match.start()].count("\n") + 1}
    declared = re.findall(r'^\s*(\w+)\s*(?:=>\s*"[^"]+")?\s*\{', block, re.M)
    if set(declared) != {row["variant"] for row in result.values()} or len(declared) != len(result):
        raise ValueError(f"Unparsed pinned request declaration: {macro}")
    return result


def source_notifications(source, macro):
    text = (source / PROTOCOL / "common.rs").read_text()
    start = text.index(macro + "! {") + len(macro + "! {")
    block = text[start:text.index("\n}", start)]
    # This macro accepts ordinary Rust enum variants as well as arrow syntax.
    # Consume the whole declaration block so a new form cannot silently vanish.
    block = re.sub(r'^\s*//[^\n]*', '', block, flags=re.M)
    block = re.sub(r'#\[experimental\("[^"\n]+"\)\]', '', block)
    arrow = r'(\w+)\s*=>\s*"([^"\n]+)"\s*\(([\w:]+)\),'
    renamed = (r'#\[serde\(rename = "([^"\n]+)"\)\]\s*'
               r'#\[ts\(rename = "\1"\)\]\s*'
               r'#\[strum\(serialize = "\1"\)\]\s*(\w+)\(([\w:]+)\),')
    bare = r'(\w+),'
    result = {}
    while block.strip():
        block = block.lstrip()
        match = re.match(arrow, block)
        custom = re.match(renamed, block)
        unit = re.match(bare, block)
        if match:
            variant, wire, params = match.groups()
        elif custom:
            match = custom
            wire, variant, params = custom.groups()
        elif unit:
            match = unit
            variant = unit[1]
            wire, params = variant[0].lower() + variant[1:], None
        else:
            raise ValueError(f"Unparsed pinned notification declaration: {macro}")
        if wire in result or variant in {row["variant"] for row in result.values()}:
            raise ValueError(f"Duplicate pinned notification declaration: {macro}")
        result[wire] = {"variant": variant, "params_rust": params}
        block = block[match.end():]
    return result


def schema_documents(profile):
    documents = {str(p.relative_to(VENDOR / profile)): json.loads(p.read_text())
                 for p in sorted((VENDOR / profile).rglob("*.json"))}
    documents.update({"supplemental/" + str(p.relative_to(VENDOR / "supplemental")): json.loads(p.read_text())
                      for p in sorted((VENDOR / "supplemental").rglob("*.json"))})
    return documents


def schema_file(profile, filename):
    return VENDOR / filename if filename.startswith("supplemental/") else VENDOR / profile / filename


def source_notification_gates(source):
    """Runtime enum gates, absent from both generated notification profiles."""
    text = (source / PROTOCOL / "common.rs").read_text()
    marker = "server_notification_definitions! {"
    start = text.index(marker) + len(marker)
    block = text[start:text.index("\n}", start)]
    pattern = r'#\[experimental\("([^"\n]+)"\)\]\s+(\w+)\s*=>\s*"([^"\n]+)"\s*\('
    matches = list(re.finditer(pattern, block))
    if len(matches) != len(re.findall(r'#\[experimental\(', block)):
        raise ValueError("Unparsed pinned server notification experimental annotation")
    return {match[3]: {"variant": match[2], "experimental_reason": match[1],
                       "source_line": text[:start + match.start()].count("\n") + 1}
            for match in matches}


def schema_path_for_type(type_name, schemas):
    name = type_name.split("::")[-1]
    candidates = sorted(p for p, schema in schemas.items() if schema.get("title") == name)
    if not candidates:
        raise ValueError(f"No generated result schema for {type_name}")
    namespace = "v2/" if "v2::" in type_name else "v1/" if "v1::" in type_name else ""
    return next((p for p in candidates if p.startswith(namespace)), candidates[0])


def pointer_token(text):
    return str(text).replace("~", "~0").replace("/", "~1")


def matching_variant(choice, older):
    if choice in older:
        return choice
    if isinstance(choice, dict):
        for prior in older:
            if not isinstance(prior, dict):
                continue
            if choice.get("title") and choice.get("title") == prior.get("title"):
                return prior
            if choice.get("$ref") and choice.get("$ref") == prior.get("$ref"):
                return prior
            for tag in ("type", "method", "kind"):
                discriminator = choice.get("properties", {}).get(tag, {}).get("enum")
                if discriminator and discriminator == prior.get("properties", {}).get(tag, {}).get("enum"):
                    return prior
    return None


def schema_contracts(full, stable, filename):
    """Record every field and schema alternative, including nested definitions.

    Stable comparison follows the same schema pointer; nullability/defaults and
    optionality are explicit. $ref targets remain lossless in vendored schemas.
    """
    contracts = []
    def walk(node, previous, pointer):
        if not isinstance(node, dict):
            return
        for name, field in sorted(node.get("properties", {}).items()):
            path = pointer + "/properties/" + pointer_token(name)
            prior = previous.get("properties", {}).get(name) if isinstance(previous, dict) else None
            constraints = field if isinstance(field, dict) else {}
            types = constraints.get("type", [])
            nullable = types == "null" or (isinstance(types, list) and "null" in types)
            nullable |= any(isinstance(x, dict) and x.get("type") == "null" for key in ("oneOf", "anyOf") for x in constraints.get(key, []))
            item = fresh(f"schema:{filename}#{path}", "schema_field", name, "SamgitaProtocolCodex.Schema")
            item.update(schema=filename, pointer=path, required=name in node.get("required", []),
                        nullable=nullable, has_default="default" in constraints,
                        default=constraints.get("default"), experimental=prior is None,
                        schema_sha256=hashlib.sha256(encode(field).encode()).hexdigest())
            contracts.append(item)
        for key in ("oneOf", "anyOf", "allOf", "enum"):
            alternatives = node.get(key, [])
            for index, choice in enumerate(alternatives):
                path = pointer + "/" + key + "/" + str(index)
                older = previous.get(key, []) if isinstance(previous, dict) else []
                item = fresh(f"schema:{filename}#{path}", "schema_variant", key, "SamgitaProtocolCodex.Schema")
                item.update(schema=filename, pointer=path, experimental=matching_variant(choice, older) is None,
                            schema_sha256=hashlib.sha256(encode(choice).encode()).hexdigest())
                contracts.append(item)
        for key, child in node.items():
            if key in ("description", "default", "enum", "examples"):
                continue
            old = previous.get(key) if isinstance(previous, dict) else None
            if isinstance(child, dict):
                if key in ("properties", "definitions", "$defs", "patternProperties"):
                    for name, value in child.items():
                        walk(value, old.get(name) if isinstance(old, dict) else None,
                             pointer + "/" + key + "/" + pointer_token(name))
                else:
                    walk(child, old, pointer + "/" + key)
            elif isinstance(child, list):
                for index, value in enumerate(child):
                    prior = matching_variant(value, old) if key in ("oneOf", "anyOf", "allOf") and isinstance(old, list) else old[index] if isinstance(old, list) and index < len(old) else None
                    walk(value, prior,
                         pointer + "/" + key + "/" + str(index))
    walk(full, stable, "")
    return contracts


def inventory(source):
    experimental = schema_documents("experimental")
    stable = schema_documents("stable")
    from generate_output_semantics import applies, corrections, native_contract
    output_corrections = corrections(VENDOR)
    entries = []
    notification_gates = source_notification_gates(source)
    for filename, direction in DIRECTIONS.items():
        paths = [filename + ".json"]
        if "supplemental/" + filename + ".json" in experimental:
            paths.append("supplemental/" + filename + ".json")
        annotations = source_requests(source, "client_request_definitions" if direction == "client_request" else "server_request_definitions") if direction.endswith("request") else {}
        declared = annotations if direction.endswith("request") else source_notifications(source, "client_notification_definitions" if direction == "client_notification" else "server_notification_definitions")
        actual = [method_name(v) for path in paths for v in experimental[path]["oneOf"]]
        if len(actual) != len(set(actual)) or set(actual) != set(declared):
            raise ValueError(f"Source/export+supplement disagreement in {direction}: missing={sorted(set(declared)-set(actual))}, extra={sorted(set(actual)-set(declared))}")
        if filename in {"ClientRequest", "ServerNotification"}:
            ts = (VENDOR / "source/supplemental-typescript" / (filename + ".ts")).read_text()
            ts_methods = re.findall(r'"method": "([^\"]+)"', ts)
            if len(ts_methods) != len(set(ts_methods)) or set(ts_methods) != set(declared):
                raise ValueError("Source/official TypeScript disagreement: " + filename)
        for path in paths:
          document = experimental[path]
          old_methods = {method_name(v) for v in stable[path]["oneOf"]}
          for variant in document["oneOf"]:
            wire = method_name(variant)
            experimental_gate = (wire in notification_gates if direction == "server_notification"
                                 else wire not in old_methods)
            # ServerRequest consumes experimental annotations for schema exports,
            # but has no ExperimentalApi derive or outbound method gate. Retain
            # its annotation status without claiming a runtime capability need.
            capabilities = ["experimentalApi"] if experimental_gate and direction != "server_request" else []
            item = fresh(direction + ":" + wire, direction, wire,
                         "SamgitaProtocolCodex.Schema" if direction.endswith("request") else "SamgitaCodexDriver.Session")
            item.update(schema=path, schema_pointer="/oneOf/" + str(document["oneOf"].index(variant)),
                        schema_sha256=digest(schema_file("experimental", path)),
                        experimental=experimental_gate, legacy=False,
                        capabilities=capabilities,
                        # The unit notification is logging-only on the pinned
                        # server, including before initialize. It is not its
                        # own readiness prerequisite.
                        prerequisites=[] if wire in {"initialize", "initialized"} else ["initialized"],
                        params=variant.get("properties", {}).get("params"),
                        params_required="params" in variant.get("required", []),
                        source=(notification_gates.get(wire) if direction == "server_notification"
                                else annotations.get(wire)), schema_version=VERSION)
            if direction == "server_notification" and wire in {"thread/realtime/item/started", "thread/realtime/item/completed"}:
                corrected = native_contract(document, path, output_corrections)
                item.update(output_semantics=output_corrections[1][0],
                            native_output_sha256=hashlib.sha256(encode(corrected).encode()).hexdigest())
            if direction.endswith("request"):
                if wire not in annotations:
                    raise ValueError(f"Missing source response mapping: {wire}")
                item["legacy"] = annotations[wire]["legacy"]
                result_schema = schema_path_for_type(annotations[wire]["response_rust"], experimental)
                item["result_schema"] = result_schema
                response_direction = "server_response" if direction == "client_request" else "client_response"
                result = fresh(response_direction + ":" + wire, response_direction, wire, "SamgitaProtocolCodex.Schema")
                result.update(schema=result_schema, request=item["id"], experimental=item["experimental"],
                              schema_sha256=digest(schema_file("experimental", result_schema)),
                              legacy=item["legacy"], schema_version=VERSION,
                              error_schema="JSONRPCError.json", capabilities=item["capabilities"],
                              prerequisites=item["prerequisites"])
                applicable = [relative for relative, semantics in output_corrections if applies(semantics, result_schema)]
                if applicable:
                    corrected = native_contract(experimental[result_schema], result_schema, output_corrections)
                    result.update(output_semantics=applicable[0],
                                  native_output_sha256=hashlib.sha256(encode(corrected).encode()).hexdigest())
                    if len(applicable) > 1:
                        result["additional_output_semantics"] = applicable[1:]
                entries.append(result)
            entries.append(item)
    for name in ("JSONRPCError", "JSONRPCErrorError", "JSONRPCResponse", "JSONRPCMessage"):
        if name + ".json" in experimental:
            item = fresh("envelope:" + name, "response_error_envelope", name, "SamgitaProtocolCodex.Wire")
            item.update(schema=name + ".json", schema_version=VERSION,
                        schema_sha256=digest(VENDOR / "experimental" / (name + ".json")))
            entries.append(item)
    for name, behavior in LIFECYCLE.items():
        item = fresh("lifecycle:" + name, "lifecycle_rule", name, "SamgitaCodexDriver.Session")
        item.update(required_behavior=behavior, schema_version=VERSION,
                    schema_sha256=hashlib.sha256(behavior.encode()).hexdigest())
        entries.append(item)
    # Canonical per-type schemas avoid counting repeated bundled definitions as
    # distinct requirements. Bundle-only anonymous definitions remain inventoried.
    contracts = []
    seen_nested = set()
    for filename, schema in experimental.items():
        if filename.startswith("codex_app_server_protocol."):
            continue
        local = {k: v for k, v in schema.items() if k != "definitions"}
        old = {k: v for k, v in stable.get(filename, {}).items() if k != "definitions"}
        contracts.extend(schema_contracts(local, old, filename))
        for name, definition in schema.get("definitions", {}).items():
            if not any(value.get("title") == name for value in experimental.values()):
                # No standalone file exists for many nested types. Inventory
                # each distinct contract once, retaining its exact schema pointer.
                previous = stable.get(filename, {}).get("definitions", {}).get(name)
                identity = encode([name, definition, previous])
                if identity in seen_nested:
                    continue
                seen_nested.add(identity)
                pointer = "/definitions/" + pointer_token(name)
                nested = schema_contracts(definition, previous, filename)
                for row in nested:
                    row["pointer"] = pointer + row["pointer"]
                    row["id"] = f"schema:{filename}#{row['pointer']}"
                contracts.extend(nested)
    for relative, semantics in output_corrections:
        for filename, document in experimental.items():
            if not applies(semantics, filename):
                continue
            branches = document["definitions"][semantics["definition"]]["oneOf"]
            for index, branch in enumerate(branches):
                renames = semantics["renames"].get(branch["properties"]["type"]["enum"][0], {})
                for row in contracts:
                    prefix = f"/definitions/{semantics['definition']}/oneOf/{index}/properties/"
                    if row["schema"] == filename and row["pointer"].startswith(prefix):
                        field = row["pointer"].removeprefix(prefix)
                        if field in renames:
                            row.update(native_wire_name=renames[field], output_semantics=relative)
    return {"manifest_version": 1, "upstream_version": VERSION, "source_commit": COMMIT,
            "entries": sorted(entries, key=lambda row: row["id"]),
            "schema_contracts": sorted(contracts, key=lambda row: row["id"])}


def annotations(source):
    records = []
    for path in sorted((source / PROTOCOL).rglob("*.rs")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if "#[experimental" in line or "#[serde(default" in line:
                records.append({"source_path": str(path.relative_to(source)), "line": index + 1,
                                "annotation": line.strip(),
                                "context": lines[max(0, index-2):index+5]})
    return records


def generate(source):
    binary = CACHE / ASSET.removesuffix(".tar.gz")
    if digest(binary) != BINARY_SHA256:
        raise SystemExit("Run fetch_pin.py first; binary does not match immutable pin")
    with tempfile.TemporaryDirectory(prefix="samgita-codex-schema-") as directory:
        home = Path(directory) / "home"
        home.mkdir()
        environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "CODEX_HOME": str(home), "HOME": str(home)}
        for profile in ("stable", "experimental"):
            output = Path(directory) / profile
            command = [str(binary), "app-server", "generate-json-schema", "--out", str(output)]
            if profile == "experimental":
                command.append("--experimental")
            subprocess.run(command, env=environment, check=True, timeout=60)
            destination = VENDOR / profile
            destination.mkdir(parents=True, exist_ok=True)
            for path in output.rglob("*.json"):
                target = destination / path.relative_to(output)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        from generate_supplement import TYPES, ALIASES
        ts_output = Path(directory) / "typescript"
        subprocess.run([str(binary), "app-server", "generate-ts", "--experimental", "--out", str(ts_output)],
                       env=environment, check=True, timeout=60)
        ts_destination = VENDOR / "source/supplemental-typescript"
        ts_destination.mkdir(parents=True, exist_ok=True)
        for name in (*TYPES, *ALIASES, "ClientRequest", "ServerNotification"):
            shutil.copyfile(ts_output / (name + ".ts"), ts_destination / (name + ".ts"))
        output_ts = VENDOR / "source/output-typescript"
        output_ts.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ts_output / "v2/ThreadTimelineEntry.ts", output_ts / "ThreadTimelineEntry.ts")
        shutil.copyfile(ts_output / "v2/ThreadRealtimeItem.ts", output_ts / "ThreadRealtimeItem.ts")
    (VENDOR / "source").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / PROTOCOL / "common.rs", VENDOR / "source/common.rs")
    for name in ("v1.rs", "export.rs"):
        origin = source / PROTOCOL / name if name == "v1.rs" else source / "codex-rs/app-server-protocol/src/export.rs"
        shutil.copyfile(origin, VENDOR / "source" / name)
    shutil.copyfile(source / PROTOCOL / "v2/thread.rs", VENDOR / "source/thread.rs")
    shutil.copyfile(source / "codex-rs/protocol/src/dynamic_tools.rs", VENDOR / "source/dynamic-tools.rs")
    shutil.copyfile(source / "codex-rs/protocol/src/models.rs", VENDOR / "source/models.rs")
    shutil.copyfile(source / "codex-rs/protocol/src/config_types.rs", VENDOR / "source/config_types.rs")
    shutil.copyfile(source / PROTOCOL / "v2/realtime.rs", VENDOR / "source/realtime.rs")
    from generate_input_semantics import verify_decoder_lock, write as write_input_semantics
    verify_decoder_lock(source / "codex-rs/Cargo.lock")
    write_input_semantics(VENDOR)
    from generate_output_semantics import write as write_output_semantics
    write_output_semantics(VENDOR)
    (VENDOR / "source/supplemental-origin.json").write_text(encode({
        "kind": "locally-derived-not-official-json-export",
        "generator": "scripts/codex/generate_supplement.py",
        "typescript_command": "codex app-server generate-ts --experimental --out typescript",
        "omitted_client_methods": sorted(__import__("generate_supplement").REQUESTS),
        "omitted_server_notifications": sorted(__import__("generate_supplement").NOTIFICATIONS),
        "semantics": "TypeScript supplies structure; pinned v1.rs serde declarations supply optional-field omission and untagged union semantics; existing official JSON supplies shared definitions and notification payloads.",
        "limits": "Converter supports only the pinned omitted declarations, fails on unknown syntax/serde attributes/defaults, and establishes no runtime behavior. Original generated JSON files remain unchanged."
    }))
    from generate_supplement import write
    write(VENDOR)
    for name in ("LICENSE", "NOTICE"):
        shutil.copyfile(source / name, VENDOR / name)
    (VENDOR / "source/gate-annotations.json").write_text(encode(annotations(source)))
    from generate_gates import extract
    (VENDOR / "source/experimental-semantics.json").write_text(encode(extract(source)))
    shutil.copyfile(source / "codex-rs/codex-experimental-api-macros/src/lib.rs",
                    VENDOR / "source/experimental-api-macros.rs")
    hashes = {str(path.relative_to(VENDOR)): digest(path) for path in sorted(VENDOR.rglob("*")) if path.is_file() and path.name != "provenance.json"}
    provenance = {"repository": "https://github.com/openai/codex", "version": VERSION,
                  "tag": "rust-v" + VERSION, "tag_object": TAG_OBJECT, "commit": COMMIT,
                  "source_archive_sha256": SOURCE_SHA256, "release_asset": ASSET,
                  "source_archive_url": f"https://codeload.github.com/openai/codex/tar.gz/{COMMIT}",
                  "release_asset_url": f"https://github.com/openai/codex/releases/download/rust-v{VERSION}/{ASSET}",
                  "artifact_digest_authority": f"https://api.github.com/repos/openai/codex/releases/tags/rust-v{VERSION}",
                  "build_platform": "x86_64-unknown-linux-musl",
                  "release_asset_sha256": ARCHIVE_SHA256, "binary_sha256": BINARY_SHA256,
                  "binary_version_output": "codex-cli " + VERSION,
                  "schema_generation_commands": ["codex app-server generate-json-schema --out stable", "codex app-server generate-json-schema --experimental --out experimental", "codex app-server generate-ts --experimental --out typescript", "python3 scripts/codex/generate_supplement.py", "python3 scripts/codex/generate_input_semantics.py"],
                  "reproduce": ["python3 scripts/codex/fetch_pin.py", "python3 scripts/codex/inventory.py --generate", "python3 scripts/codex/inventory.py --check"],
                  "files_sha256": hashes}
    (VENDOR / "provenance.json").write_text(encode(provenance))


def merge_progress(expected, actual):
    for section in ("entries", "schema_contracts"):
        old = {row["id"]: row for row in actual.get(section, [])}
        for row in expected[section]:
            previous = old.get(row["id"], {})
            if (row.get("schema_sha256") == previous.get("schema_sha256")
                    and row.get("native_output_sha256") == previous.get("native_output_sha256")
                    and row.get("native_wire_name") == previous.get("native_wire_name")):
                row.update({key: previous[key] for key in PROGRESS if key in previous})
                if row["implementation_module"] in {"SamgitaProtocolCodex.Native", "SamgitaProtocolCodex.Native.Schema", "SamgitaProtocolCodex.Session"}:
                    row["implementation_module"] = "SamgitaCodexDriver.Session" if row["direction"] in {"lifecycle_rule", "client_notification", "server_notification"} else "SamgitaProtocolCodex.Wire" if row["direction"] == "response_error_envelope" else "SamgitaProtocolCodex.Schema"
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--require-verified", action="store_true")
    args = parser.parse_args()
    source = CACHE / f"codex-{COMMIT}"
    if args.generate:
        generate(source)
    # Offline checks need only the vendored macro source, never the source cache.
    with tempfile.TemporaryDirectory(prefix="codex-source-check-") as temp:
        source_root = Path(temp)
        (source_root / PROTOCOL).mkdir(parents=True)
        shutil.copyfile(VENDOR / "source/common.rs", source_root / PROTOCOL / "common.rs")
        expected = inventory(source_root)
    actual = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    expected = merge_progress(expected, actual)
    if args.check or args.require_verified:
        from generate_input_semantics import corrections as input_corrections
        for relative, semantics in input_corrections(VENDOR):
            if (VENDOR / relative).read_text() != encode(semantics):
                raise SystemExit("Source-derived input semantics changed: " + relative)
        from generate_output_semantics import corrections
        for relative, semantics in corrections(VENDOR):
            if (VENDOR / relative).read_text() != encode(semantics):
                raise SystemExit("Source-derived output semantics changed: " + relative)
        from generate_supplement import generate as supplemental_contracts
        for relative, schema in supplemental_contracts(VENDOR).items():
            if (VENDOR / "supplemental" / relative).read_text() != encode(schema):
                raise SystemExit("Source-derived supplemental contract changed: " + relative)
        provenance = json.loads((VENDOR / "provenance.json").read_text())
        actual_paths = {str(path.relative_to(VENDOR)) for path in VENDOR.rglob("*")
                        if path.is_file() and path.name != "provenance.json"}
        if actual_paths != set(provenance["files_sha256"]):
            raise SystemExit("Pinned artifact set changed")
        for relative, sha in provenance["files_sha256"].items():
            if digest(VENDOR / relative) != sha:
                raise SystemExit(f"Pinned artifact changed: {relative}")
        if actual != expected:
            raise SystemExit("Compatibility manifest differs from the complete generated inventory; run --generate")
    else:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(encode(expected))
    for section in ("entries", "schema_contracts"):
        counts = collections.Counter(row["state"] for row in expected[section])
        print(f"{section}: {len(expected[section])}; {dict(counts)}")
        ids = [row["id"] for row in expected[section]]
        if len(ids) != len(set(ids)):
            raise SystemExit(f"Duplicate IDs in {section}")
        for row in expected[section]:
            if row["state"] not in {"missing", "implemented", "verified", "blocked"}:
                raise SystemExit(f"Unknown state: {row['id']}")
            if row["state"] == "verified" and (not row["evidence"] or not row["tests"]["verified"]):
                raise SystemExit(f"Verified entry lacks evidence: {row['id']}")
        if args.require_verified and any(row["state"] != "verified" for row in expected[section]):
            raise SystemExit(f"Full-compatibility gate failed: unverified requirements remain in {section}")


if __name__ == "__main__":
    main()
