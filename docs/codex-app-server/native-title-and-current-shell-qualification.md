# Native initialization title and current local-shell data

The driver accepts omitted, null and Unicode initialization titles, and preserves
current `local_shell_call.in_progress` data through native raw output, durable
history, cold supplied history and the selected provider copy. These are scoped
input/runtime qualifications against the actual pinned binary. Downstream title
analytics and genuine legacy shell production remain unverified.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Initialization title

`native_initialize_title_values_test.exs` uses three separately owned fresh
native processes. Each sends a complete real `initialize` request with identical
name/version and one independently prescribed title input: absent, explicit null,
or `Owned initialization display λ🙂`. A bounded delegating transport records
only successfully sent initialize frames. The test requires the entire captured
wire map and decoded bytes to equal the original request, including its title
presence/value, and the native result to carry the original correlation ID.

The result must have exactly `codexHome`, `platformFamily`, `platformOs` and
`userAgent`, with the prescribed scratch home, unix/linux platform and independent
name/version user-agent boundaries. A subsequent correlated `thread/loaded/list`
returns an empty page and the driver remains ready with no pending/uncertain
operation or gap. No thread, turn or provider inference occurs. Source/config/
catalog bytes and the empty request journal remain unchanged, the workspace stays
empty, and the actual pinned executable/PID is checked before owned shutdown.

The source explains the selected observable result. The actual initialize
processor clones the complete params for analytics before destructuring
`ClientInfo { name, title: _title, version }`. Runtime identity uses name/version;
the response has no title echo. This qualifies native acceptance and selected
runtime behavior, **not global nonuse of title**. Analytics propagation, storage,
rendering or outcomes are explicitly unverified. No telemetry/logging/security
test or audit is part of this profile.

## Current in-progress local-shell data

`native_supplied_local_shell_history_test.exs` retains its original incomplete
native-metadata and client-null cases and adds one original-metadata in-progress
case. A small explicitly named wrapper selects the new literal through five
narrow fixture hooks whose defaults remain `incomplete`. The original complete
incomplete oracle and the complete original journey, collectors and cleanup are
preserved; the journey only receives an independent expected status.

The first ordinary Responses stream supplies current local-shell data with an
inert command and no ID, call ID or passthrough metadata. Stock native decoding
creates the real `lsh_` identity, canonical null fields and source-turn metadata.
Exactly one native `rawResponseItem/completed` must equal the whole durable shell
map, including literal `in_progress`, with the correct thread/turn IDs. The genuine
user map is independently checked in full, including identity, classification,
content, source turn and bounded native timestamp.

After closing/reaping the source, a distinct cold native process starts with no
loaded thread. The actual captured user/shell maps are sent unchanged through
`thread/resume.history`. A new idle thread/path retains them once and in order,
with unchanged preview and no automatic turn/inference. One deliberate followup
then consumes the original whole shell minus only passthrough metadata. Its
status, original identity, null call/action fields and inert command remain
explicit independent oracles. Provider requests remain **1 → 1 → 2**, and imported
originals/source bytes are rechecked after followup and shutdown.

This is the current generic decoder/non-tool-history path. Native routing does
not convert this raw item into a command execution; the absent call ID also
avoids synthesized call-output pairing. An in-progress historical item is not
evidence of an executing shell or pending platform work. The profile supplies no
legacy producer, native legacy emission, genuine historical backend traffic or
call/output-pairing acceptance. Existing20s turn/60s case deadlines,256-event/
1MiB bounds,4MiB files,2048 rows,262144-byte lines and finite owned-PID cleanup
remain intact.

## Physical owners and immutable source

Only these two canonical `ClientRequest.json` owners become scoped implemented:

| Index | Physical pointer | Independent node SHA256 |
| --- | --- | --- |
| 89 | `/definitions/ClientInfo/properties/title` | `cd49941f1a90808c0c692f85bc803a6dd936c9153aaac4a725cf9030c3fc9089` |
| 233 | `/definitions/LocalShellStatus/enum/1` | `7ba8684ecfd24588653c60005bffc8b6ce57be9016e44e2a703285fb48a7e323` |

The actual `initialize → InitializeParams.clientInfo → ClientInfo.title` and
`thread/resume → ThreadResumeParams.history → ResponseItem.LocalShellCall.status
→ LocalShellStatus` request graphs are independently resolved. Schema aliases,
parent/ref nodes, other statuses and outer request fields inherit no promotion.

Twenty-two complete Rust files are byte-equal to the immutable archive. Title
closure covers the real protocol/common/v1, dispatch and initialize processor.
Current-shell closure covers models/Responses decoding, native turn/session/tool
routing/non-tool recorder, raw-event dispatch/thread state, supplied-history
reconstruction, persistence policy/thread-store writer and provider-copy handling.
Source anchors include `initialize_processor.rs:80–96,130–143,185–220`,
`models.rs:1082–1097,2041–2063`, `responses.rs:354–359`,
`tools/router.rs:257–307`, `thread_processor.rs:4789–4803`,
`context_manager/normalize.rs:112–142` and `client.rs:1007–1020,1092–1102`.

## Final functional evidence

Base commit: `44574b29d6ff97c786493c447bf05a2d08a21a55`.
Environment: Elixir1.18.5/OTP27.3.4.17, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`,
fixed pinned `CODEX_BINARY`, no inherited umbrella build/dependency/partition paths.
Ordinary owned launches use fixed yolo configuration; no permission behavior is
tested.

The two owning modules first pass **6/0** at seed501432. The final reviewed
**53-file matrix passes107/0 twice**, seeds501432/987654, command times
181.660/181.558 seconds. Scoped format, warnings-as-errors compile, strict Credo
on503 sources, outside actual-binary consumer **1/0**, thirty Python fixture ASTs
and the **304-source guard** pass. Exactly two prior test/fixture sources adapt;
the other300 remain unchanged, and two focused sources are added. A reverse
comparison also preserves the original journey, full incomplete oracle,
collectors/cleanup and fixture defaults.

Commands/logs and exact53-file allowlist are retained in
`/tmp/samgita-v332-run.py` and `/tmp/samgita-v332-functional-checks/functional/`.
Immutable-source, exact-owner and final-result bindings are retained by
`/tmp/samgita-v332-source.py`, `samgita-v332-promote.py` and
`samgita-v332-final-binding.py` with JSON artifacts in that checkpoint directory.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `e84f83369e19a3891e49a5ee03bc560166ce549ae413732462a89e6da93dd2c7` |
| Source guard | `0daf7d3f6342bb32dc4d69472bf7666dd8007382ca22a7615c7160e0c7666107` |
| Source evidence | `bc189070f1556552ddf37ed935c6068223e644c674bcfae97475e964bd08025a` |
| Manifest | `90ebf440c527e09216114c84e884e8953713ef1b9a234fc1a7c62f16abd7e221` |

Inventory consistency passes. Strict completeness deliberately remains failed:
**462 implemented /12 missing /11 blocked requirements**, **4,985 implemented /
1,570 missing /66 blocked contracts**, **zero verified**. These results use the
actual binary and owned synthetic inputs; they do not establish real provider
integration, other OS/transports or legacy production reachability. Prohibited
tests/audits, broad suites and automatic hosted workflows remain unrun. A11,
external/platform and full-goal/release gates remain incomplete. No publication,
tag or deployment is made.
