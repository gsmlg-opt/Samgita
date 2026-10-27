# Actual native foreign-session import

V403 adds [full import-notification ingress evidence](import-notification-envelopes-qualification.md)
to the inert-subagent path in this owning module. Historical runs below retain
their source scope; the new32-case matrix explicitly selects all seven current
ordinary cases at both seeds with prior assertions and bounds unchanged.

A separate success-only profile now imports an owned synthetic foreign-format
transcript through the real pinned Codex app-server. It proves actual native
session creation, completed-source deduplication and cold persistence. This
extends the [earlier import profile](import-lifecycle-qualification.md); its
original mixed suite is not run under the current test restriction.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Processing and durable observations

`native_session_import_success_test.exs` creates an inert two-message JSONL
under private `HOME/.claude/projects/owned-import/`. Text, actual owned cwd and
independently recorded UTC timestamps are the input oracle. This is synthetic
Claude-format input, not evidence of a real Claude producer. The test never
constructs or modifies native rollout/SQLite data.

Actual `externalAgentConfig/detect` must return exactly the expected `SESSIONS`
selection, source path/cwd/title and empty companion collections. Import sends
that exact selection. Its correlated import-ID response acknowledges the
request; two progress notices and completion establish processing. Captured
frame order requires the receipt before those notices. The completion's native
target ID must match durable import history, one actual native thread, canonical
SessionMeta and full native history. No `recordHistory` call manufactures success.

Native import uses **Legacy** history. The independently expected completed
turn is `external-import-turn-1`, with `item-1` user input, `item-2` foreign
assistant text and `item-3` native `<EXTERNAL SESSION IMPORTED>` marker. Full
public maps and raw response/event maps are asserted, including original source
chronology, null error and native `last_agent_message:null`.

Only after completion/history are observed does a second explicit import submit
the identical source. It receives a different operation ID and empty successful
result; that empty completed history is also persisted. Exactly one thread/turn,
unchanged canonical bytes and unchanged full public history remain. This tests
deduplication after known completion, not ambiguous-disconnect retry or exactly-once
external execution. Normal owned shutdown/reaping precedes a distinct cold
reader; both import histories, full raw/public history and IDs/times must survive
before any resume. Model requests remain zero. Input/config/catalog bytes stay
exact, with no loaded thread, pending/uncertain request or event gap. Bounds,
finite deadlines and the original process owner are preserved.

## Imported title and public name

The initial test failed on public `thread/list.name`: it is **null**, while the
completed import history retains the parsed title. The importer patches
`ThreadMetadataPatch.title` at `session_importer.rs:521–528`, whereas the separate
legacy name-index write uses `patch.name` at
`thread-store/src/local/update_thread_metadata.rs:193–234`. Public projection
uses `StoredThread.name` at `thread_processor.rs:6443`.

The corrected oracle requires exact null name while retaining separate title,
full metadata, timestamp, source/history and cold-equality assertions. It does
not rename the thread, normalize the response or remove the field. Claude cwd/title
come from the transcript. The subsequent Cursor section qualifies request cwd
fallback and embedded precedence separately. Title-setting semantics,
changed-source append and general title/name consistency stay incomplete.

## Physical ownership and checks

Only these canonical ClientRequest nodes become scoped **implemented**:

| Owner | Exact node |
| --- | --- |
| 184 | `ExternalAgentConfigMigrationItemType/enum/9`: `SESSIONS` |
| 258 | `MigrationDetails/properties/sessions`: nonempty selection |
| 596 | `SessionMigration/properties/path`: actual parsed input |

The actual import request graph resolves these exact nodes; each node hash is
independently checked against its physical owner. No sibling/reference/hash
propagation occurs. Twenty-one whole source files match their unique immutable
archive members, covering parser/exporter, processor/importer, durable histories,
Legacy name storage and public projection.

Baseline: `a74536c696506c5ab9f6ff0bc5cc70b135833d4e`.
Elixir1.18.5/OTP27.3.4.17, `MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`, pinned
`CODEX_BINARY`, independent driver build/config/dependency paths. The owning case
passes1/0 after the recorded name-oracle failure. The final affected block passes
**5/0 twice**, seeds501432/987654: new import module and the preceding three
Cli/Exec/Review/source-filter modules. Scoped format, warnings-as-errors compile,
strict Credo on508 sources, outside actual-binary consumer1/0 and retained
relay/inline-Exec AST checks pass. All310 guarded sources are stable across
checks; all309 prior sources remain byte-identical.

Exact commands/logs: `/tmp/samgita-v341-run.py` and
`/tmp/samgita-v341-functional-checks/final/`. Source/final bindings use
`/tmp/samgita-v341-source.py` and `/tmp/samgita-v341-bind.py`.
The initial failure is `/tmp/samgita-v341-owning-initial.log`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `d2bf415c5579518b47b69a90e74b0570abfcf9f61533346cf30097a82d500a8f` |
| Source guard | `91411a58c79c72f96a37ec5e81d510f3b1fe655d16c515d43f43836ab3e6055b` |
| Whole source/schema comparisons | `88211ba3906c28fda6beff1588863ef6fbf2eb9cdde3f2ccdb06682f3de87507` |

Inventory consistency passes; strict completeness remains exit1. Contracts are
**4,999 implemented /1,556 missing /66 blocked**; requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Every import
format/default/variant and whole method-family completeness are not established.
Fixed yolo is ordinary setup only. Security, credential, permission,
authentication, authorization and approval tests/audits, mixed suites and hosted
workflows remain unrun. A11, unavailable legacy/external/platform/OS success,
full compatibility and release remain incomplete. No publication, deployment,
production migration or real Claude/provider integration is certified.

## Cursor request cwd and embedded precedence

Two additional actual-native cases distinguish requested cwd from native launch,
discovery and source metadata. Each creates an inert Cursor-format JSONL at
private `HOME/.cursor/projects/empty-window/agent-transcripts/session.jsonl`.
Both records carry explicit UTC timestamps exactly ten seconds apart. The
user record contains a supported context wrapper and `<user_query>`; imported
raw/public text must match the independently expected unwrapped prompt. This
is synthetic foreign-format input, not proof of a real Cursor producer.

| Input | Real detection | Requested cwd | Persisted import cwd |
| --- | --- | --- | --- |
| No embedded cwd | Owned HOME, through native `empty-window` semantics | Separate existing owned directory | Requested directory |
| Explicit embedded cwd | Embedded existing owned directory | The same separate requested directory | Embedded directory |

The import request changes only the selected session's cwd after checking real
detection. Both cases reuse the original complete import journey: ordered
receipt/progress/completion, full success and durable history, one actual Legacy
thread, exact raw canonical messages and public items, source chronology,
completed-source deduplication and cold native reads. The original Claude
case retains its assertions. All three cwd directories remain empty, source
and configuration bytes remain unchanged, and model requests stay zero. No
native history or database record is handcrafted, and no title setter is claimed.

The actual import schema graph independently resolves only physical owner
**595**, `ClientRequest.json#/definitions/SessionMigration/properties/cwd`,
node SHA256 `bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7`.
It becomes scoped **implemented**, with no sibling or verified promotion.
Twenty-six whole files match the immutable archive. In addition to the prior
importer/storage evidence, they bind Cursor discovery, `MigrationFallback`,
record parsing/unwrapping and embedded-before-fallback selection in
`external-agent-migration/src/`.

Baseline: `0e913725e39e198b84ea5eb6e29053cfd031e58b`. The three owning cases
pass **3/0** initially. The final affected four-file block passes **7/0 twice**,
seeds `501432` and `987654`, in 28.379s and 28.479s. Scoped format,
warnings-as-errors compile, strict Credo on 508 sources, outside actual-binary
consumer **1/0** and retained relay/inline Exec AST checks pass. The 310-source
guard is stable; all 309 unrelated prior sources, including production driver,
protocol and process cleanup, remain byte-identical. No runtime test failed,
deadline increased, assertion removed or test skipped.

Commands/results: `/tmp/samgita-v342-run.py` and
`/tmp/samgita-v342-functional-checks/final/`; source/final bindings:
`/tmp/samgita-v342-source.py` and `/tmp/samgita-v342-bind.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `62a5264f6ab27a531b071e2761f64bbe63500b3c50b677ee7356ae58b9600df6` |
| Source guard | `a9aa1cd03676585469818c5de92404100e3ac5332cde037072afd0838be01090` |
| Whole source/schema comparisons | `2fdde562fd066401dac8090d3b2467148c595b90ed63552e8676a54174004b90` |

Inventory consistency passes; strict completeness remains exit **1**. Contracts
are **5,000 implemented / 1,555 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Fixed YOLO is
ordinary setup only. The user's prohibited tests/audits, original mixed import
suite, broad suites and hosted workflows remain unrun. A11, unreachable legacy
paths, unavailable external/platform/OS success, full compatibility and release
remain incomplete. No package publication, deployment, production migration or
real Cursor/provider integration is established.

## Advisory requested title

A further positive case submits `Owned requested advisory title` in the selected
session's request metadata, after checking actual detection of the different
transcript-derived title. Captured outgoing bytes preserve that supplied value.
Actual import success, progress/completion, durable successful history, thread
preview and complete imported messages retain the original source title/text.
The separate legacy name index remains null, and the requested hint is absent
from the actual native rollout.

This matches the pinned source: protocol conversion accepts the field, but
`sessions/mod.rs:116–160` passes only path/cwd into source parsing;
`sessions/export.rs:39–83` derives the imported title from that parsed source.
The observed behavior is accepted/ignored advisory metadata. There is no
request-driven title setter or rename claim.

The case retains the full real import journey: correlated receipt and exact
processing notices, one native Legacy thread, complete raw/public history and
chronology, explicit repeat after known completion with a distinct empty
operation history, unchanged canonical bytes and a distinct cold native reader.
Zero model requests, unchanged source/config/workspace inputs, bounded capture,
finite deadlines and normal owned shutdown all remain asserted.

Only physical owner **597**,
`ClientRequest.json#/definitions/SessionMigration/properties/title`, becomes
scoped **implemented**. Node SHA256:
`cd49941f1a90808c0c692f85bc803a6dd936c9153aaac4a725cf9030c3fc9089`.
The real import graph and 34 whole immutable source files match. Null, omitted
and default variants, other formats/transports/OS and whole-family completeness
are not inferred from this explicit-value case.

Baseline: `06309b80592d6feb8513f13ee60e20930cb5749b`. The owning module
initially passes **6/0**. Final affected four-file checks pass **10/0 twice**,
seeds `501432` and `987654`, in 33.654s and 33.887s. Scoped format,
warnings-as-errors compile, strict Credo on 508 sources, outside actual-binary
consumer **1/0**, retained relay/inline Exec ASTs and the 310-source guard pass.
All 309 unrelated sources and production protocol/driver/process cleanup remain
byte-identical. No new failure, skipped assertion or deadline increase occurs.

Commands/logs: `/tmp/samgita-v345-run.py` and
`/tmp/samgita-v345-functional-checks/final/`; source/final bindings:
`/tmp/samgita-v345-source.py` and `/tmp/samgita-v345-bind.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `71234d9d74756b8ef36ac3122e529a1d19b153e4e2b62b0699bcd0a954487d79` |
| Source guard | `6c8189e5b920504ab2a5e6b486977b71641324acb83462fe9a4223c6822e5146` |
| Whole source/schema comparisons | `a1b0d87b2eb356704211b434221099e086aebb7139e85abe344ca801e79caac3` |

Inventory consistency passes; strict completeness exits **1**. Contracts become
**5,006 implemented / 1,549 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Fixed YOLO remains
ordinary setup. Prohibited tests/audits, mixed/broad suites and hosted workflows,
A11, upstream-unreachable legacy and unavailable external/platform/OS success,
full compatibility and release stay incomplete. No real Claude/provider
integration, package publication, deployment or production migration occurs.
