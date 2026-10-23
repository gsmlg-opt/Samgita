# Native organization and read-state lifecycle qualification

This unit targets immutable Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, through the existing Linux stdio
driver. It covers the native thread-section catalogue, manual membership/order
and durable read-state lifecycle using disposable native processes and the
existing synthetic Responses peer. It changes no production code or shared
fixtures.

Current status: all eight actual-binary cases pass with seeds `501432` and
`987654`. Compilation with warnings as errors, scoped formatting and whitespace
checks pass. This qualifies only the selected Linux stdio/local synthetic
behaviors below; other profiles and full compatibility remain incomplete.

## Pinned source contract

Paths below are relative to the pinned upstream `codex-rs/` directory:

- `app-server-protocol/src/protocol/common.rs:692–696,820–839,863–868`
  declares stable `thread/section/move` and `threadSection/*` methods, with
  per-thread move serialization and a shared global catalogue lock. Only
  `thread/readState/update` requires experimental negotiation. There is no
  section-change notification family.
- `app-server-protocol/src/protocol/v2/thread.rs:1100–1119,1317–1398`
  defines the required nullable `sectionId` for moves, optional append/before
  placement, and catalogue methods. Update appearance omission preserves its
  value, null clears it, and an object replaces the whole appearance.
  `thread_data.rs:190–199` retains nullable icon/color fields in responses.
- `app-server-protocol/src/protocol/v2/thread.rs:1535–1543` serializes sort-key
  enum values as snake case. Manual order is requested with
  `sortKey: "section_position"`, also asserted in `common.rs:2215–2216`.
- `app-server/src/request_processors/thread_sections.rs` trims names, protects
  the pinned section, checks nonempty IDs and limits each appearance field to
  64 UTF8 bytes. Semantic catalogue errors use `-32602`. Page limits clamp to
  the supported interval. SQLite-disabled operation is a separate unsupported
  profile and is not exercised here.
- `state/src/runtime/thread_sections.rs` allocates distinct UUIDv7 section IDs
  even for duplicate names. Deletion clears positions and entry times for both
  active and archived members in an immediate transaction.
- `state/src/runtime/thread_section_order.rs:1–190` lists by ascending ID with
  an opaque lexical cursor and uses an immediate transaction for moves.
  Same-section reordering preserves entry time; null unassigns. Missing target
  sections, self-before moves and before-members outside the target are invalid.
- `app-server/src/request_processors/thread_processor.rs:705–743,6343–6353`
  maps invalid moves to native `-32600` responses. Its unsubscribe path at
  `1034–1060` removes the connection subscription before the ACK; unloading is
  deferred and is not a required unsubscribe completion event.
- `app-server-protocol/src/protocol/v2/thread.rs:2045–2099` defines opaque
  read-state revisions, nullable/turn/thread-start unread positions, explicit
  expected-revision actions and `thread/readState/changed` snapshots.
- `app-server/src/request_processors/thread_read_state.rs` limits durable
  state to eligible persisted user threads, reads snapshots without creating a
  receipt, notifies subscribers, and awaits notification dispatch before an
  applied update response. A stale revision returns exact `-32600`, message
  `read state changed`, and structured `readStateConflict` data containing the
  committed current state. History replay does not republish attention.
- `state/src/runtime/thread_read_state.rs` compares revisions inside an
  immediate transaction, preserves the earliest unread turn when later terminal
  attention arrives, deduplicates published turn identity and generates fresh
  opaque revisions for applied actions. `thread_lifecycle.rs:370–379` awaits
  terminal attention publication before the ordinary turn-completed output.
- Upstream behavior references are
  `app-server/tests/suite/v2/thread_sections.rs`, `thread_read_state.rs`, and
  `thread_metadata_update.rs:59–174,415–593`.

## Eight verified scoped cases

`apps/samgita_codex_driver/test/native_organization_lifecycle_test.exs` owns:

1. Trimmed names, UUIDv7 identity, distinct IDs for duplicate names, ID-ordered
   pagination including native zero-limit clamping, appearance preserve/replace/
   clear semantics, and catalogue persistence after native restart.
2. Empty/unknown IDs and names, pinned rename/delete, ASCII and multibyte
   appearance limits, exact semantic errors, and unchanged catalogue on failure.
3. Materialized thread append/before/reappend order, preserved entry times,
   invalid move state preservation, null unassignment, and cold metadata/order
   reads that leave threads unloaded.
4. Renamed section projections in active and archived metadata, deletion clearing
   both memberships and entry times, then unarchive/restart persistence.
5. Two terminal turns retaining the first unread turn while advancing revision,
   matching native attention notices, read/list without acknowledgement, cold
   read/resume without model work or attention republication, and revert before
   the first turn clearing unread history.
6. Two competing read/unread actions submitted to the same native server with
   one expected revision: exactly one commits, the conflict contains the winner,
   stale actions preserve it, and fresh actions plus restart retain real native
   revisions. This proves only same-server serialization and actual revision
   comparison; it is not a cross-process concurrency proof.
7. Subscription removal ACK followed by an applied unread action and read-response
   barrier: durable snapshots still change while the removed subscriber receives
   no matching update notice. Resume restores subscription and a fresh action
   produces a matching notice. The observation is bounded by awaited native
   response/notification ordering, with no arbitrary absence sleep and no claim
   that unsubscribe immediately unloads the thread.
8. Absent/false experimental negotiation preserves stable catalogue/move methods
   while read-state updates reject locally and natively; ephemeral read-state
   eligibility and malformed required/type boundaries retain actual native
   errors. These no-turn cases require zero synthetic provider requests.

## Validation boundaries

The existing `TurnFixture`, `ModelFixture` and `StdioSessionFixture` own temporary
HOME, CODEX_HOME, workspace, loopback provider, native process cleanup and only
synthetic request journals. Cleanup is registered immediately after process
start. Every configured account/provider origin remains on the owned loopback
peer. No real credentials, paid model, platform database, external service or
production task is involved.

Prepared and qualified at repository baseline
`8331b9977d50ffd7615c962c3b2cd79e6eb5e3f2` on 2026-10-24. The unformatted test
draft remained outside the repository formatter glob until the coordinating
agent granted the exclusive build/process slot.

The initial run recorded **8 tests, 1 failure** at seed `501432`; log:
`/tmp/samgita-native-organization-initial.log`. The ordering case sent an invalid
camel-case sort-key enum, which the local pinned schema correctly rejected.
Pinned source and its explicit serde test establish `section_position` as the
wire value. One test-input correction retained all behavior assertions; no
runtime/schema change, skip or timeout increase was needed.

The following complete scoped verification then exited `0`:

```sh
devenv shell --no-tui -- bash -c 'cd apps/samgita_codex_driver &&
  MIX_ENV=test mix format test/native_organization_lifecycle_test.exs &&
  MIX_ENV=test mix compile --warnings-as-errors &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_organization_lifecycle_test.exs --include real_codex --seed 501432 &&
  MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl mix test test/native_organization_lifecycle_test.exs --include real_codex --seed 987654 &&
  MIX_ENV=test mix format --check-formatted test/native_organization_lifecycle_test.exs'
```

Seed `501432` completed **8 tests, 0 failures** in 7.6 seconds; seed `987654`
completed **8 tests, 0 failures** in 7.9 seconds. The same command passed
compilation with warnings as errors and scoped format checks. Full retained
output is `/tmp/samgita-native-organization-repair-1.log`. Scoped
`git diff --check` passed. All owned native/provider processes were reaped and
the exclusive execution slot was released. Cumulative repair count: one
successful test-input correction, zero unsuccessful repair rounds.

The binary used was the canonical local immutable artifact at
`tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`, independently SHA256-checked
as `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Only the selected Linux stdio profile is in scope. SQLite-disabled operation,
independent-process races, non-user thread-source eligibility, all terminal
attention suppression/error variants, remote transports, real providers,
platform-specific success and A11 remain unqualified. Source/schema coverage and
these cases cannot establish full compatibility, publication or production
readiness.
