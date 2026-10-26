# Actual native foreign-session import

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
come from the transcript. Request cwd fallback, title-setting semantics, Cursor,
changed-source append and general title/name consistency stay separately incomplete.

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
