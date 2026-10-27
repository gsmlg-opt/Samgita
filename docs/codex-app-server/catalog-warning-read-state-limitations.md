# Catalog, warning and read-state serialization limits

V459 binds seven exact field-level producer limits at `main`
`c8a486e5466902c0abf9068e2142eb4c7a514660`. It changes no code, schema, test,
fixture, runtime or existing evidence arrays. The immutable target is Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`; no alternate
binary, synthetic result or other endpoint supplies success evidence.

| Contracts | Exact owner | Unavailable native variant |
| --- | --- | --- |
| 3380 | `v2/CollaborationModeListResponse.json#/definitions/CollaborationModeMask/properties/mode/anyOf/1` | Null mode |
| 3381 | Same definition, `properties/model` | Populated model string; existing null-only evidence is retained |
| 3864 | `v2/ConfigWarningNotification.json#/properties/range/anyOf/1` | Explicit JSON null range |
| 5850–5853 | `v2/ThreadReadStateUpdateResponse.json#/definitions/ThreadUnreadPosition/oneOf/1`, its `turnId`, `type` and `type/enum/0` | Turn-position alternative in successful update response |

The [closed collaboration preset producer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/models-manager/src/collaboration_mode_presets.rs#L6-L24)
returns exactly Plan/Default, each with `Some(mode)` and `model: None`. Both
production manager implementations delegate directly; thread manager/catalog
and protocol conversion copy these fields unchanged. No list parameter, model
catalog or configuration selects another producer. A null result does not
qualify the populated model arm. The prior mixed-file test reference remains
historical and is not rerun or presented as fresh ordinary evidence.

The [warning serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/config.rs#L1159-L1177)
declares `range: Option<TextRange>` with `skip_serializing_if = "Option::is_none"`.
None omits the property; Some emits the range object. Every typed constructor
therefore lacks an explicit-null range output. Existing omitted-range evidence
does not qualify that separate advertised branch.

The [read-state update transaction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/thread_read_state.rs#L87-L110)
constructs Applied from freshly committed Read→None or Unread→empty string.
The success converter maps these to null/threadStart. Nonempty positions from
read/list/change notifications or conflict error data use different values and
cannot qualify the successful turn alternative. The existing complete
[success-path proof](read-state-update-success-limitation.md) remains unchanged.

Two overlapping collaboration `reasoning_effort` null nodes, **3386/3387**, are
deliberately unchanged. Source distinguishes outer None from Some(None), but
both serialize as JSON null. This review supplies no new runtime evidence or
blanket alias/branch credit for either physical node. The reachable populated
hook-plugin identifier is also unchanged pending its separate functional test.

All **5,259** Rust files and the full local Rust file set match the official
archive; ten independently recorded complete source hashes and seven physical
nodes match their canonical exports/generated copies. Whole-source catalog
references distinguish the two production managers from test implementations.
Original tests, transport arrays and limitations are preserved; no passing test
or transport credit is added by this source-only binding. All 850 V456 source
hashes and 13 successful logs remain exact. No new tests/native processes run.

Report `/tmp/samgita-v459-report.md`, SHA256
`1c3f6a8899e62e4dd7ad7462d82103241f0fec528566abbad13fa4e4d61bab6d`;
binder `/tmp/samgita-v459-bind.py`; source/reference/node binding
`/tmp/samgita-v459-binding/source.json`, SHA256
`e3c9020ec5ad849124627d203d8e0d185c1e649b83c748d529f5e9d28d0184c5`;
evidence SHA256
`59958181e261f00c7d045c8fc1992b6313690fa5f249b8c472e8b48c0d00400a`.
Inventory consistency and diff whitespace are checked after integration.

Contracts: **5,286 implemented / 1,241 missing / 94 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
These variants require an explicit target/evidence-contract decision or a
supported upstream producer. No workaround, schema deletion or scope waiver is
applied. Rollback reverts only these seven field status/evidence changes and
documentation. Continue enabled ordinary hook-plugin metadata. Fixed YOLO stays
setup only; security/permission tests/audits, broad/hosted checks, A11,
legacy/external/platform and release gates remain incomplete. No publication
or deployment.
