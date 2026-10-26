# Legacy dynamic-tool input

The normal schema-validated driver now accepts the legacy flat
`thread/start.dynamicTools` declarations accepted by pinned Codex. It also rejects
the mixed canonical/legacy lists that the native decoder rejects. This repairs
two input-validation discrepancies on base
`7deadd87663628cec33959e31543b960a4c7858e`; it does not rewrite caller messages,
change native execution, or complete the broad default/negotiation requirements.

## Pinned producer and repair

Target: Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The source archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

The real request processor deserializes `ThreadStartParams.dynamic_tools` with
`codex_protocol::dynamic_tools::deserialize_dynamic_tool_specs`. Its normal
production path accepts legacy flat declarations without `type`, despite the
official JSON export describing only tagged canonical declarations. This is a
reachable request decoder, independently source-backed; it is not a fabricated
legacy event producer.

`Schema.Input` adds a separately labeled, source-derived legacy item contract to
the in-memory method document. Required string fields, arbitrary `inputSchema`,
optional/nullable namespace and boolean flags follow the pinned Rust struct.
Unknown fields retain native serde behavior. A separate list-level check matches
native format detection, including null-valued legacy signatures and nested
tools. Original canonical constraints and experimental field-presence negotiation
remain enforced. Official exports, input maps and encoding stay unchanged.

`scripts/codex/generate_input_semantics.py` derives the descriptor from the exact
Rust fields, checks immutable source hashes and both official field contracts,
and rejects unrecognized field syntax. Inventory generation/checking includes
this supplement; provenance adds its two artifacts and generator command.
All **770 official JSON exports** and all previous pinned artifacts retain their
original hashes. Eleven complete upstream files match their archive members.

Native Codex alone applies the semantics:

| Legacy input | Actual provider behavior | Canonical persisted flag |
| --- | --- | --- |
| Both flags null | Direct namespace/function exposure | `deferLoading` omitted |
| `exposeToContext:false`, deferral absent | Native tool-search discovery before the dynamic call | `deferLoading:true` |
| `exposeToContext:false`, `deferLoading:false` | Explicit false overrides the legacy flag; direct exposure | `deferLoading` omitted |

The native normalized namespace stores an empty description. Its actual provider
description is `Tools in the owned_catalog namespace.`; the canonical declaration
tests retain their different explicit description. The driver neither groups
namespaces nor inserts these defaults into the outgoing request.

## Reproduction and behavior evidence

Before production changes, the seven-case dedicated protocol module fails
**six** cases. It rejects valid legacy input and accepts canonical declarations
with forbidden legacy signatures. All **three** new actual-native tests fail at
local `thread/start` validation; the other four owning cases are excluded only
in that initial location-selected reproduction. Logs remain at
`/tmp/samgita-v350-protocol-before.log` and `-native-before.log`.

After the repair, the dedicated protocol module and full native owning module
each pass **7/0**. The unchanged Responses fixture supplies model items only;
the pinned executable produces all app-server responses, tool requests, events
and stored metadata. Assertions cover exact provider exposure/discovery,
correlated `item/tool/call` arguments and response, started/completed tool items,
assistant output, canonical session metadata and stored item timestamps. A new
cold PID reads the same item without loading the thread, changing rollout bytes
or making extra provider requests. Existing owned-process cleanup remains intact.

Source/unit coverage also includes omitted/null/boolean flag variants,
unnamespaced/grouped inputs, opaque fields, malformed required fields and
list-wide format consistency. These extra shapes are **not** all independent
native success profiles. Wire equality plus the unchanged Session encoding path
supports losslessness; this native fixture has no independent outgoing-byte
recorder. Cold item reads do not establish a resumed inference turn's exposure.

## Final permitted checks

All eleven final commands pass. Fixed seeds are `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Four reviewed protocol modules | **17/0 twice**, no exclusions |
| Ten reviewed ordinary driver modules | **50/0 twice**, no exclusions; 54.978/55.475s |
| Driver composition | 21 actual-binary cases plus 29 scripted Session fault cases per seed |
| Independent consumer copied outside umbrella | **1/0**, actual native initialization/list; supplement validates locally |
| Compile and scoped format, protocol and driver | Pass, warnings treated as errors |
| Root strict Credo | Pass on **512 sources** |
| Python AST and inventory consistency | Five files parse; inventory passes |
| Before/after executable-source guard | **319** files stable; all **309** other previous sources unchanged |

The initial final-matrix attempt stops on strict Credo: the expanded test helper
has cyclomatic complexity 10, above the unchanged limit 9. Extracting declaration
selection into a helper preserves every assertion/deadline; the complete final
matrix then passes. The failed result remains in the parent artifact directory.
The earlier inventory rejection of unregistered new artifacts is also retained.

Exact environments, file lists and command arrays are in
`/tmp/samgita-v350-run.py` and `-final-run.py`. Final artifacts live under
`/tmp/samgita-v350-functional-checks/`; immutable-source binding is reproduced by
`/tmp/samgita-v350-source.py`, and manifest binding by
`/tmp/samgita-v350-bind.py --verify`.

| Artifact | SHA256 |
| --- | --- |
| Initial stopped `results.json` | `2a440e10b4f44ec19c877f641678958f1ccde6568bf4b015cdf5859ec60016c5` |
| Eleven immutable files and red/lint evidence | `0d329e48551aa88963c91b533eb3f0ec1abbe6975532cfdef07dba6fbeb40e0c` |
| Final `final/results.json` | `ac4b84c029c2e318da6ee270eeeb19fa01879b7e482ded3e53144c1f1806dd4b` |
| Final `final/source.json` | `e36529b680628167570eab4991fd45bbaaacd39b6dcd83f6e121c2a20f971ea6` |

## Migration, rollback and remaining gates

No PostgreSQL schema or data migration occurs. Existing native histories,
uncertain operations and platform journals remain untouched. The native writer
already persists canonical tool metadata; this repair changes local input
validation only. Rolling back the package restores the earlier legacy-input
rejection and mixed-format discrepancy. Do not rewrite history, erase uncertainty
or replay any possibly executed operation as part of rollback.

Six requirement records receive scoped supplemental evidence only. No requirement
state or physical schema owner is promoted: contracts remain **5,018 implemented /
1,537 missing / 66 blocked**; requirements remain **462 implemented / 12 missing /
11 blocked**, **zero verified**. Source-only legacy behavior omitted by the
official export does not create invented physical-schema owners. Both broad
negotiation/default requirements remain missing. Strict completeness exits **1**.

All owned ordinary launches use fixed YOLO settings. No security, credential,
authentication, authorization, permission or approval tests/audits, mixed broad
suites or hosted workflows run. Existing gates remain intact and incomplete.
No database restart/protection result is promoted on this changed schema layer.
A11, producerless legacy paths, unavailable external/OS/platform profiles and
full compatibility remain incomplete. No tag, publication or deployment occurs.
