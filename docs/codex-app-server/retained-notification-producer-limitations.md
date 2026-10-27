# Retained notification fields without native producers

V457 makes seven field-level blockers explicit at `main`
`c279c7ca2315ad66fa89db5556ee81aead423fe3`. It changes no schema, code, test,
fixture or executable. The existing parent notification blockers remain; these
exact fields now also carry the immutable source boundary. Previous synthetic
codec/handler and native-negative test/transport evidence is preserved unchanged
with its original limits. No new passing-test or transport credit is added.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Exact field owners | Contracts | Native prerequisite |
| --- | --- | --- |
| `v2/FileChangeOutputDeltaNotification.json#/properties/{delta,itemId,threadId,turnId}` | 3996–3999 | Removed production emitter |
| `v2/ThreadPredictionUpdatedNotification.json#/properties/{result,sourceTurnId,threadId}` | 5725–5727 | Unimplemented prediction operation and absent notification producer |

The [file-change type declaration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1517-L1529)
explicitly states “The server no longer emits this notification.” Its four
required strings and wire declaration remain. Whole-source references are
declarations, media classification, TUI consumers and a test-client allowlist;
there is no production constructor/send path. Genuine `patchUpdated`, final
file-change items, disk effects and final diff updates are different events and
cannot qualify this legacy output notification.

The [prediction dispatcher](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1450-L1453)
unconditionally returns `method_not_found("thread/prediction/request is not
implemented yet")`. It schedules no work. The [retained result type](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_prediction.rs#L11-L35)
and wire declaration have no production constructor/send path. Prediction-style
fork metadata is a separate feature. Preserving its results does not establish
prediction-notification success.

Fresh binding compares all **5,259** Rust files byte for byte with the official
archive, checks the complete local Rust file set and records all 20 matching
source lines for the two notifications and prediction request. Five key complete
declaration/dispatch/classification files match their independently recorded
hashes. Positive upstream non-emission/unimplemented statements complement the
whole-source reference review; absence in a runtime test is not the argument.
The first scratch binding expected the wrong Rust match-arm syntax and stopped
before any manifest mutation; its guard was corrected to the exact source arm.
No behavior test failed or was weakened.

All seven physical nodes match the canonical experimental export and generated
copy. Six string nodes have SHA256
`bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7`;
prediction `result` has SHA256
`6fc082ff199df67e1bb01fab77f9105a7c104e2ad6b7e7554ce6da08c09ed6c2`.
No sibling, alias, union alternative or parent receives transferred credit.
The underlying complete-evidence requirement is unchanged.

Source report `/tmp/samgita-v457-candidate.md`, SHA256
`b5e3aeb72570c195210e40d3d8fa3f355b271b24042385b6ac1d3fd8bc93fa02`;
binder `/tmp/samgita-v457-bind.py`; source/reference/node binding
`/tmp/samgita-v457-binding/source.json`, SHA256
`495343679f7139588c8b17e138c43206e30d4e862058f91df77a94bd6e7bd41b`;
evidence SHA256
`375a66ad11495b374a7191e5587cca3d25cf62494a51a03151fdc3445c4046a0`.
All 850 V456 source hashes and 13 successful logs stay exact. No new native or
test run occurs. Inventory consistency and diff whitespace are checked after
binding. The inspected command/process payload slice already has scoped
implemented evidence; this review adds no duplicate scenarios or control credit.

Contracts: **5,277 implemented / 1,257 missing / 87 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
Native success remains unavailable under the immutable target. An explicit
target/evidence-contract decision or a supported upstream producer is required
to reconcile that requirement; a mock, different notification, modified binary
or credential cannot supply it. No local workaround, schema deletion or scope
waiver occurs. Rollback reverts only these seven status/evidence changes and
documentation, preserving prior tests and records. Continue ordinary native
request/event evidence. Security/permission tests/audits, broad/hosted workflows,
A11, legacy/external/platform and release gates remain incomplete. No publication
or deployment.
