#!/usr/bin/env python3
"""Derive bounded pinned input corrections, retaining official JSON.

Cover custom dynamic-tool decoding and source-pinned input representations.
These describe accepted input, never outgoing-value normalization.
"""

import hashlib
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
COLLABORATION_SEMANTICS = "source/collaboration-input-semantics.json"
CONFIG_TYPES = "source/config_types.rs"
CONFIG_TYPES_SHA256 = "ce9b26223db7cc4b5cf474e571e4509e8cc52536e159510f153f94de0fcd37e8"
COLLABORATION_METHODS = ("thread/settings/update", "turn/start")
COLLABORATION_SCHEMAS = ("ClientRequest.json", "v2/ThreadSettingsUpdateParams.json", "v2/TurnStartParams.json")
MULTI_AGENT_SEMANTICS = "source/multi-agent-input-semantics.json"
MULTI_AGENT_METHODS = ("thread/settings/update", "thread/start", "turn/start")
MULTI_AGENT_SCHEMAS = (*COLLABORATION_SCHEMAS, "v2/ThreadStartParams.json")
SUMMARY_SEMANTICS = "source/reasoning-summary-input-semantics.json"
SUMMARY_METHODS = ("thread/settings/update", "turn/settings/update", "turn/start")
SUMMARY_SCHEMAS = (*COLLABORATION_SCHEMAS, "v2/TurnSettingsUpdateParams.json")
PERSONALITY_SEMANTICS = "source/personality-input-semantics.json"
PERSONALITY_METHODS = ("thread/resume", "thread/settings/update", "thread/start", "turn/start")
PERSONALITY_SCHEMAS = (*COLLABORATION_SCHEMAS, "v2/ThreadStartParams.json", "v2/ThreadResumeParams.json")
HISTORY_MODE_SEMANTICS = "source/history-mode-input-semantics.json"
THREAD_DATA = "source/thread_data.rs"
THREAD_DATA_SHA256 = "293359f14a1a11da8d54acce7bc69b5756c1d30b5a59e8768f5ce6b4e02edeb1"
COMMON = "source/common.rs"
COMMON_SHA256 = "ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3"
HISTORY_MODE_METHODS = ("thread/start",)
HISTORY_MODE_SCHEMAS = ("ClientRequest.json", "v2/ThreadStartParams.json")
START_SOURCE_SEMANTICS = "source/thread-start-source-input-semantics.json"
START_SOURCE_METHODS = ("thread/start",)
START_SOURCE_SCHEMAS = ("ClientRequest.json", "v2/ThreadStartParams.json")
DECODER_RUST = "source/serde-1.0.228/private-de.rs"
DECODER_SHA256 = "68ee17774d3bbc693d9f19803747fa2c3afdb7046482e6d94ac6cf7db5a4fe20"
DECODER_LICENSE = "source/serde-1.0.228/LICENSE-MIT"
DECODER_LICENSE_SHA256 = "23f18e03dc49df91622fe2a76176497404e46ced8a715d9d2b67a7446571cca3"
DECODER_CRATE_SHA256 = "9a8e94ea7f378bd32cbbd37198a4a91436180c5bb472411e48b5ec2e2124ae9e"
DECODER_ORIGIN = "source/serde-1.0.228/origin.json"
CARGO_LOCK_SHA256 = "17cdd862471774ba7aef836aaf0a0a3ed76bd23e503b1fc7278c89d1f2719d03"


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


def derive_collaboration(vendor):
    if digest(vendor / CONFIG_TYPES) != CONFIG_TYPES_SHA256:
        raise ValueError("Pinned collaboration mode decoder changed")
    rust = (vendor / CONFIG_TYPES).read_text()
    declaration = re.search(r'pub enum ModeKind \{\n(.*?)\n\}', rust, re.S)
    if not declaration or not declaration[1].startswith('    Plan,\n    #[default]\n'):
        raise ValueError("Pinned ModeKind variants changed")
    aliases = re.findall(r'alias = "([^"\n]+)"', declaration[1])
    if aliases != ["code", "pair_programming", "execute", "custom"]:
        raise ValueError("Pinned Default aliases changed")
    if not declaration[1].endswith('    )]\n    Default,'):
        raise ValueError("Pinned alias target changed")
    hashes = {}
    for name in COLLABORATION_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        if document["definitions"]["ModeKind"]["enum"] != ["plan", "default"]:
            raise ValueError("Official canonical mode contract changed: " + name)
        hashes[name] = digest(path)
    document = json.loads((vendor / "experimental/ClientRequest.json").read_text())
    if request_methods(document, "ModeKind") != list(COLLABORATION_METHODS):
        raise ValueError("ModeKind request input graph changed")
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(COLLABORATION_METHODS),
        "definition": "ModeKind",
        "canonical_tag": "default",
        "input_aliases": aliases,
        "input_object_branches": unit_object_branches(["plan", "default", *aliases]),
        "source_sha256": {CONFIG_TYPES: CONFIG_TYPES_SHA256, **buffered_decoder_sources(vendor)},
        "schemas_sha256": hashes,
        "semantics": "Accept the four pinned Default string aliases and externally tagged unit objects for plan/default and those aliases only in the two reachable request graphs. The internally tagged ClientRequest buffers nested params; its pinned serde decoder accepts null or empty-map unit payloads with exactly one known key. Preserve caller values, settings constraints, negotiation and canonical output schemas. Native owns canonical string normalization, parser behavior and persistence.",
    }


def request_methods(document, definition):
    reachable = []
    for branch in document["oneOf"]:
        pending, seen = [branch["properties"]["params"]], set()
        while pending:
            value = pending.pop()
            if isinstance(value, dict):
                reference = value.get("$ref", "").removeprefix("#/definitions/")
                if reference and reference not in seen:
                    seen.add(reference)
                    pending.append(document["definitions"][reference])
                pending.extend(value.values())
            elif isinstance(value, list):
                pending.extend(value)
        if definition in seen:
            reachable.extend(branch["properties"]["method"]["enum"])
    return sorted(reachable)


def derive_multi_agent(vendor):
    if digest(vendor / CONFIG_TYPES) != CONFIG_TYPES_SHA256:
        raise ValueError("Pinned deprecated multi-agent input decoder changed")
    rust = (vendor / CONFIG_TYPES).read_text()
    if '#[serde(rename_all = "camelCase", from = "MultiAgentModeWire")]' not in rust:
        raise ValueError("Pinned MultiAgentMode decoder changed")
    declaration = re.search(r'enum MultiAgentModeWire \{\n(.*?)\n\}', rust, re.S)
    if not declaration or declaration[1] != (
            '    None,\n    Custom(String),\n    ExplicitRequestOnly,\n    Proactive,'):
        raise ValueError("Pinned MultiAgentModeWire variants changed")
    if 'MultiAgentModeWire::None => Self::Custom(String::new()),' not in rust:
        raise ValueError("Pinned none input conversion changed")
    decoder_sources = buffered_decoder_sources(vendor)
    hashes = {}
    for name in MULTI_AGENT_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        union = document["definitions"]["MultiAgentMode"]["oneOf"]
        if len(union) != 2 or union[0] != {"type": "string", "enum": ["explicitRequestOnly", "proactive"]}:
            raise ValueError("Official deprecated mode input contract changed: " + name)
        hashes[name] = digest(path)
    document = json.loads((vendor / "experimental/ClientRequest.json").read_text())
    if request_methods(document, "MultiAgentMode") != list(MULTI_AGENT_METHODS):
        raise ValueError("MultiAgentMode request input graph changed")
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(MULTI_AGENT_METHODS),
        "definition": "MultiAgentMode",
        "input_branches": [
            {"type": "string", "enum": ["none"]},
            *unit_object_branches(["none", "explicitRequestOnly", "proactive"]),
        ],
        "native_none_decoded_value": {"custom": ""},
        "source_sha256": {CONFIG_TYPES: CONFIG_TYPES_SHA256, **decoder_sources},
        "schemas_sha256": hashes,
        "semantics": "The pinned native from=MultiAgentModeWire decoder accepts none and maps it to Custom with empty text. Internally tagged ClientRequest buffers nested params: its serde ContentDeserializer accepts one-key unit objects for none/explicitRequestOnly/proactive with null OR empty-map payload. Preserve exact caller values, reject additional distinct keys/nonempty payloads, and do not broaden outputs. All three current request fields are deprecated and ignored; decoding does not activate delegation or change effective public explicitRequestOnly settings.",
    }


def unit_object_branches(names):
    return [{"type": "object", "required": [name], "additionalProperties": False,
             "properties": {name: {"enum": [None, {}]}}} for name in names]


def derive_summary(vendor):
    if digest(vendor / CONFIG_TYPES) != CONFIG_TYPES_SHA256:
        raise ValueError("Pinned reasoning summary input decoder changed")
    rust = (vendor / CONFIG_TYPES).read_text()
    declaration = re.search(
        r'#\[serde\(rename_all = "lowercase"\)\]\n'
        r'#\[strum\(serialize_all = "lowercase"\)\]\n'
        r'pub enum ReasoningSummary \{\n(.*?)\n\}', rust, re.S)
    if not declaration or declaration[1] != (
            '    #[default]\n    Auto,\n    Concise,\n    Detailed,\n'
            '    /// Option to disable reasoning summaries.\n    None,'):
        raise ValueError("Pinned ReasoningSummary unit variants changed")
    names = [name.lower() for name in re.findall(r'^    (\w+),$', declaration[1], re.M)]
    hashes = {}
    for name in SUMMARY_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        union = document["definitions"]["ReasoningSummary"]["oneOf"]
        if len(union) != 2 or [value for branch in union for value in branch["enum"]] != names:
            raise ValueError("Official canonical summary contract changed: " + name)
        hashes[name] = digest(path)
    document = json.loads((vendor / "experimental/ClientRequest.json").read_text())
    if request_methods(document, "ReasoningSummary") != list(SUMMARY_METHODS):
        raise ValueError("ReasoningSummary request input graph changed")
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(SUMMARY_METHODS),
        "definition": "ReasoningSummary",
        "input_object_branches": unit_object_branches(names),
        "source_sha256": {CONFIG_TYPES: CONFIG_TYPES_SHA256, **buffered_decoder_sources(vendor)},
        "schemas_sha256": hashes,
        "semantics": "The ordinary lowercase ReasoningSummary unit enum accepts one-key objects for auto/concise/detailed/none through internally tagged ClientRequest's pinned buffered serde decoder, with null or empty-map unit payload. Preserve the entire canonical string contract, caller objects, enclosing constraints, outer null/omission semantics and negotiation. Native owns canonical applied settings and scope; selected none omits provider reasoning.summary rather than sending a none string. Output schemas remain canonical.",
    }


def derive_personality(vendor):
    if digest(vendor / CONFIG_TYPES) != CONFIG_TYPES_SHA256:
        raise ValueError("Pinned personality input decoder changed")
    rust = (vendor / CONFIG_TYPES).read_text()
    declaration = re.search(
        r'#\[serde\(rename_all = "lowercase"\)\]\n'
        r'#\[strum\(serialize_all = "lowercase"\)\]\n'
        r'pub enum Personality \{\n(.*?)\n\}', rust, re.S)
    if not declaration or declaration[1] != '    None,\n    Friendly,\n    Pragmatic,':
        raise ValueError("Pinned Personality unit variants changed")
    names = [name.lower() for name in re.findall(r'^    (\w+),$', declaration[1], re.M)]
    hashes = {}
    for name in PERSONALITY_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        if document["definitions"]["Personality"] != {
                "type": "string", "enum": names,
                "description": "Deprecated: `friendly` and `pragmatic` no longer select a style."}:
            raise ValueError("Official canonical personality contract changed: " + name)
        hashes[name] = digest(path)
    document = json.loads((vendor / "experimental/ClientRequest.json").read_text())
    if request_methods(document, "Personality") != list(PERSONALITY_METHODS):
        raise ValueError("Personality request input graph changed")
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(PERSONALITY_METHODS),
        "definition": "Personality",
        "input_object_branches": unit_object_branches(names),
        "source_sha256": {CONFIG_TYPES: CONFIG_TYPES_SHA256, **buffered_decoder_sources(vendor)},
        "schemas_sha256": hashes,
        "semantics": "The ordinary lowercase Personality unit enum accepts one-key none/friendly/pragmatic objects through internally tagged ClientRequest's pinned buffered serde decoder, with null or empty-map unit payload. Preserve canonical string schema, caller objects, outer null/omission distinctions, enclosing constraints and negotiation on exactly four input graphs. Native owns instruction construction: fresh none strips the model template's Personality section, while later updates and resume retain inherited base instructions. Friendly/pragmatic no longer select distinct styles. Output schemas remain canonical.",
    }


def derive_history_mode(vendor):
    sources = {THREAD_DATA: THREAD_DATA_SHA256, THREAD: SOURCES[THREAD], COMMON: COMMON_SHA256}
    for name, expected in sources.items():
        if digest(vendor / name) != expected:
            raise ValueError("Pinned history mode input source changed: " + name)
    rust = (vendor / THREAD_DATA).read_text()
    declaration = re.search(
        r'#\[derive\(Default, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS\)\]\n'
        r'#\[serde\(rename_all = "lowercase"\)\]\n'
        r'#\[ts\(rename_all = "lowercase", export_to = "v2/"\)\]\n'
        r'pub enum ThreadHistoryMode \{\n(.*?)\n\}', rust, re.S)
    if not declaration or declaration[1] != '    #[default]\n    Legacy,\n    Paginated,':
        raise ValueError("Pinned ThreadHistoryMode unit variants changed")
    names = [name.lower() for name in re.findall(r'^    (\w+),$', declaration[1], re.M)]
    field = (
        '    /// Persisted thread history contract to use for this new thread.\n'
        '    #[experimental("thread/start.historyMode")]\n'
        '    #[ts(optional = nullable)]\n'
        '    pub history_mode: Option<ThreadHistoryMode>,')
    if field not in (vendor / THREAD).read_text():
        raise ValueError("Pinned historyMode field declaration changed")
    common = (vendor / COMMON).read_text()
    if ('#[serde(tag = "method", rename_all = "camelCase")]\n        pub enum ClientRequest {' not in common
            or 'serde_json::from_value(serde_json::Value::Object(request))' not in common):
        raise ValueError("Pinned ClientRequest buffered input path changed")
    hashes = {}
    for name in HISTORY_MODE_SCHEMAS:
        path = vendor / "experimental" / name
        document = json.loads(path.read_text())
        if document["definitions"]["ThreadHistoryMode"] != {"type": "string", "enum": names}:
            raise ValueError("Official canonical history mode contract changed: " + name)
        definition = document["definitions"]["ThreadStartParams"] if name == HISTORY_MODE_SCHEMAS[0] else document
        if definition["properties"]["historyMode"] != {
                "anyOf": [{"$ref": "#/definitions/ThreadHistoryMode"}, {"type": "null"}],
                "description": "Persisted thread history contract to use for this new thread."}:
            raise ValueError("Official historyMode field contract changed: " + name)
        hashes[name] = digest(path)
    document = json.loads((vendor / "experimental/ClientRequest.json").read_text())
    if request_methods(document, "ThreadHistoryMode") != list(HISTORY_MODE_METHODS):
        raise ValueError("ThreadHistoryMode request input graph changed")
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(HISTORY_MODE_METHODS),
        "definition": "ThreadHistoryMode",
        "input_object_branches": unit_object_branches(names),
        "source_sha256": {**sources, **buffered_decoder_sources(vendor)},
        "schemas_sha256": hashes,
        "semantics": "The ordinary lowercase ThreadHistoryMode unit enum accepts one-key legacy/paginated objects through internally tagged ClientRequest's pinned buffered serde decoder, with null or empty-map unit payload. Only thread/start reaches this input definition. Preserve the complete canonical string schema, caller objects, enclosing constraints, outer null/omission and experimental field negotiation. Native owns canonical creation mode and its persisted history contract; acceptance does not submit a turn. Output schemas remain canonical.",
    }


def derive_start_source(vendor):
    sources = {THREAD: SOURCES[THREAD], COMMON: COMMON_SHA256}
    for name, expected in sources.items():
        if digest(vendor / name) != expected:
            raise ValueError("Pinned thread start source input changed: " + name)
    rust = (vendor / THREAD).read_text()
    declaration = re.search(
        r'#\[derive\(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS\)\]\n'
        r'#\[serde\(rename_all = "camelCase"\)\]\n'
        r'#\[ts\(rename_all = "camelCase", export_to = "v2/"\)\]\n'
        r'pub enum ThreadStartSource \{\n(.*?)\n\}', rust, re.S)
    if not declaration or declaration[1] != '    Startup,\n    Clear,':
        raise ValueError("Pinned ThreadStartSource unit variants changed")
    names = [name[:1].lower() + name[1:] for name in re.findall(r'^    (\w+),$', declaration[1], re.M)]
    field = (
        '    pub history_mode: Option<ThreadHistoryMode>,\n'
        '    #[ts(optional = nullable)]\n'
        '    pub session_start_source: Option<ThreadStartSource>,')
    if field not in rust:
        raise ValueError("Pinned standard sessionStartSource field declaration changed")
    common = (vendor / COMMON).read_text()
    if ('#[serde(tag = "method", rename_all = "camelCase")]\n        pub enum ClientRequest {' not in common
            or 'serde_json::from_value(serde_json::Value::Object(request))' not in common):
        raise ValueError("Pinned ClientRequest buffered input path changed")
    hashes = {}
    for profile in ("stable", "experimental"):
        for name in START_SOURCE_SCHEMAS:
            path = vendor / profile / name
            document = json.loads(path.read_text())
            if document["definitions"]["ThreadStartSource"] != {"type": "string", "enum": names}:
                raise ValueError("Official canonical start source contract changed: " + profile + "/" + name)
            definition = document["definitions"]["ThreadStartParams"] if name == START_SOURCE_SCHEMAS[0] else document
            if definition["properties"]["sessionStartSource"] != {
                    "anyOf": [{"$ref": "#/definitions/ThreadStartSource"}, {"type": "null"}]}:
                raise ValueError("Official sessionStartSource field contract changed: " + profile + "/" + name)
            if name == START_SOURCE_SCHEMAS[0] and (
                    request_methods(document, "ThreadStartSource") != list(START_SOURCE_METHODS)):
                raise ValueError("ThreadStartSource request input graph changed: " + profile)
            if profile == "experimental":
                hashes[name] = digest(path)
    return {
        "kind": "locally-derived-input-contract-not-official-export",
        "upstream_commit": COMMIT,
        "generator": "scripts/codex/generate_input_semantics.py",
        "methods": list(START_SOURCE_METHODS),
        "definition": "ThreadStartSource",
        "input_object_branches": unit_object_branches(names),
        "source_sha256": {**sources, **buffered_decoder_sources(vendor)},
        "schemas_sha256": hashes,
        "semantics": "The ordinary camelCase ThreadStartSource unit enum accepts one-key startup/clear objects through internally tagged ClientRequest's pinned buffered serde decoder, with null or empty-map unit payload. Only thread/start reaches this standard input definition in both stable and full profiles. Preserve the complete canonical string schema, caller objects, enclosing constraints and outer null/omission. Native selects new/cleared history initialization for the new thread; acceptance does not submit a turn or clear other threads. Input acceptance and first-turn initialization provenance do not qualify source-specific SessionStart hook effects. Output schemas remain canonical.",
    }


def buffered_decoder_sources(vendor):
    sources = {
        DECODER_RUST: DECODER_SHA256, DECODER_LICENSE: DECODER_LICENSE_SHA256,
        DECODER_ORIGIN: hashlib.sha256(encode(decoder_origin()).encode()).hexdigest(),
    }
    for name, expected in sources.items():
        if digest(vendor / name) != expected:
            raise ValueError("Pinned buffered input decoder reference changed: " + name)
    decoder = (vendor / DECODER_RUST).read_text()
    if 'Content::Map(ref v) if v.is_empty() => visitor.visit_unit(),' not in decoder:
        raise ValueError("Pinned buffered unit payload contract changed")
    return sources


def decoder_origin():
    return {
        "kind": "pinned-dependency-source-reference-not-codex-export",
        "package": "serde", "version": "1.0.228", "license": "MIT OR Apache-2.0",
        "included_license": "LICENSE-MIT",
        "crate_url": "https://static.crates.io/crates/serde/serde-1.0.228.crate",
        "crate_sha256": DECODER_CRATE_SHA256,
        "upstream_commit": COMMIT, "codex_cargo_lock_sha256": CARGO_LOCK_SHA256,
        "source_member": "serde-1.0.228/src/private/de.rs",
        "source_sha256": DECODER_SHA256, "license_sha256": DECODER_LICENSE_SHA256,
        "semantics": "Complete source reference only, never compiled. The internally tagged ClientRequest buffers nested params through ContentDeserializer; its enum decoder requires one map entry and unit decoder accepts null or an empty map. These are actual nested request-input semantics, not a change to outgoing JSON or canonical output values.",
    }


def verify_decoder_lock(path):
    if digest(path) != CARGO_LOCK_SHA256 or (
            'name = "serde"\nversion = "1.0.228"\n'
            'source = "registry+https://github.com/rust-lang/crates.io-index"\n'
            f'checksum = "{DECODER_CRATE_SHA256}"') not in path.read_text():
        raise ValueError("Pinned Codex dependency lock changed")


def corrections(vendor):
    return ((SEMANTICS, derive(vendor)), (RESPONSE_SEMANTICS, derive_response_item(vendor)),
            (COLLABORATION_SEMANTICS, derive_collaboration(vendor)),
            (MULTI_AGENT_SEMANTICS, derive_multi_agent(vendor)),
            (SUMMARY_SEMANTICS, derive_summary(vendor)),
            (PERSONALITY_SEMANTICS, derive_personality(vendor)),
            (HISTORY_MODE_SEMANTICS, derive_history_mode(vendor)),
            (START_SOURCE_SEMANTICS, derive_start_source(vendor)))


def write(vendor):
    (vendor / DECODER_ORIGIN).write_text(encode(decoder_origin()))
    for relative, value in corrections(vendor):
        (vendor / relative).write_text(encode(value))


if __name__ == "__main__":
    from inventory import VENDOR
    write(VENDOR)
