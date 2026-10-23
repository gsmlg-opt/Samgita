# Thread revert native qualification

Three actual-binary cases passed locally at seeds `501432` and `987654`,
3.0 seconds each. Namespace preflight, formatting, warnings-as-errors compile
and scoped strict Credo passed. This is selected Linux/stdio behavior evidence,
not complete field/error qualification, hosted acceptance or publication.

## Target and implementation

- Codex: immutable `rust-v0.163.0`, source commit
  `83086188ae0614bd882818ff1aa23f3194962012`.
- Native Linux musl executable expected SHA256:
  `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
  The profile verifies this before each native startup.
- Test:
  `apps/samgita_codex_driver/test/native_thread_revert_profile.exs`.
- Existing dependency peer: `scripts/codex/model_fixture.py`, explicitly selected
  through the existing `ModelFixture`/`TurnFixture` setup. No new peer is needed.
  Its `assistant` scenario returns a fixed text message through actual HTTP
  Responses SSE. The peer never writes app-server messages.
The installed profile uses existing support modules and introduces no driver
interface, dependency or production-code change. Hosted CI explicitly selects it.

## Observed behavior

All three ExUnit cases execute the immutable native process:

1. Start a fresh non-ephemeral paginated thread with experimental API negotiation.
   Complete exactly two synthetic, tool-free text turns; record native turn IDs.
   Read the original history through both native `thread/read` and
   `thread/turns/list`. Reject an unknown turn with native error `-32600` and
   `turn not found: owned-missing-turn`; verify the two-turn history survives and
   observe no success notice. Then call native `thread/revert` before turn two,
   require unchanged thread identity, empty inline turns and opaque history
   cursors, and consume the actual native `thread/reverted` notice. Hydrate the
   response's backward turn cursor and independently read/list history to prove
   that only the unchanged first turn remains, with its user and assistant text.
   Reconnect the owned stdio session, initialize a fresh native process, resume by
   thread ID with `excludeTurns: true`, and verify the same retained prefix. The
   backend request count must remain exactly two throughout, including restart.
2. Reject a fresh ephemeral thread before inference, with native `-32600` and
   `ephemeral threads do not support thread/revert`. Its metadata remains readable.
3. Reject a fresh explicitly legacy thread before inference, with native `-32600`
   and `thread/revert only supports paginated threads`. Its metadata remains
   readable.

The existing owner helper provides disposal on assertion failure; each
case also explicitly closes its native session. Fresh HOME, CODEX_HOME, TMPDIR,
workspace and shell executable are owned scratch resources. Native startup uses
an empty environment inheritance list and disables remote control. The fixture
config targets only its loopback provider and disables Web search/provider
retries. This profile does **not** independently prove network namespace
confinement or every implicit native external destination; parent runtime review
must retain that distinction.

A prewritten scratch sentinel and a recursive file-content snapshot must remain
unchanged. No Git commands, shell tool calls, real project workspace mutation,
external inference service, real credentials or paid tasks are part of this
profile. Codex is permitted to mutate its owned conversation-history store.

Notification absence assertions cover events observed after the error and a
successful native metadata/history read. They do not assert an infinite absence
window. Full-history `thread/read(includeTurns: true)` and
`thread/turns/list(itemsView: "full")` are deliberately exercised as retained,
deprecated compatibility paths; normal metadata-only reads and cursor hydration
are also checked.

## Exact pinned source assertions

All paths below are relative to the pinned `codex-rs/` source root under
`tmp/codex/0.163.0/codex-83086188ae0614bd882818ff1aa23f3194962012/`.

- `app-server-protocol/src/protocol/v2/thread.rs:116-119` marks
  `thread/start.historyMode` experimental.
- `thread.rs:1281-1311` specifies the prefix strictly before `beforeTurnId`, no
  local-file rollback, empty response `thread.turns`, and backward opaque cursor
  hydration. `thread.rs:2132-2134` declares the notice's `threadId`.
- `app-server/src/request_processors/thread_processor.rs:606-630` awaits
  `thread_revert_response`, sends the success response, then emits exactly one
  `ServerNotification::ThreadReverted`. An error returned by that helper exits
  before either success emission. The profile checks success/notice correlation;
  it does not assert cross-channel response/notification arrival ordering.
- `thread_processor.rs:2149-2173` checks direct-input eligibility and rejects
  ephemeral/nonpaginated histories with the exact messages above.
- `thread_processor.rs:2179-2237` subscribes before shutdown, drains shutdown
  events with a ten-second bound and reports shutdown/drain errors.
- `thread_processor.rs:2280-2347` removes the old runtime, cancels pending
  thread requests, invokes the store mutation, preserves subscriptions, and
  reloads before returning. Receipt-cleanup errors are warnings after a committed
  revert; they do not independently fail success. Runtime reload can fail after
  the store mutation has committed.
- `thread_processor.rs:2350-2460` reloads from current persisted history without
  a stale rollout path, checks the same thread ID, restores/checkpoints settings,
  retains listeners and builds backward cursors with empty inline turns.
- `thread-store/src/local/revert_thread.rs:15-17,105-153` retains old immutable
  rollouts, computes the before-turn boundary, writes a replacement rollout and
  switches the same thread's SQLite rollout pointer through compare-and-swap.
- `thread-store/src/local/thread_history/turn_lookup.rs:47-49` produces the
  unknown-turn message. `thread_processor.rs:6354-6365` maps store invalid-request
  and conflict errors through native invalid-request handling.
- `thread.rs:1705-1714,1742-1775` defines read hydration and turn pagination;
  `thread_processor.rs:3334-3404` implements paginated full-item hydration.
  `app-server-protocol/src/protocol/v2/thread_data.rs:415-423` declares
  `itemsView: "full"`. `thread_processor.rs:4263-4328` restores paginated history
  after cold resume while honoring `excludeTurns`.
- `app-server/tests/suite/v2/thread_revert.rs:420-593` is the upstream two-turn,
  notice, retained-prefix, cold-resume and invalid-turn example. Its third turn
  is intentionally excluded here to keep exactly two provider requests.
  `thread_revert.rs:597-710` additionally exercises active-turn interruption;
  that broader branch is not covered by this draft.
- Existing `scripts/codex/model_fixture.py:14-24,84-106` produces fixed assistant
  Responses SSE in the assistant scenario; `:117-135` pins fixture destinations
  and disables retry. Existing `TurnFixture.finish_turn/3` waits for an actual
  native terminal event and rejects server tool/approval requests.

## Validation and unqualified boundaries

From the independent driver directory in verified Devenv, with `MIX_ENV=test`
and the pinned `CODEX_BINARY`, both commands passed **3 tests / zero failures**:

```sh
mix test test/native_thread_revert_profile.exs --seed 501432
mix test test/native_thread_revert_profile.exs --seed 987654
mix compile --warnings-as-errors
mix format --check-formatted test/native_thread_revert_profile.exs
```

Root scoped `mix credo
apps/samgita_codex_driver/test/native_thread_revert_profile.exs --strict` passed.
Logs: `/tmp/samgita-thread-revert-*-20261024.log`. Existing cleanup checks passed;
this unit does not add deliberately failed-assertion shutdown qualification.
The notification gains scoped `implemented` evidence, and both existing method
entries retain earlier evidence. Only seven positive revert parameter, cursor,
thread and notification contracts are added; none is fully verified.

No deterministic native timeout/lost-response injection is added: the existing
Responses peer cannot reliably pause native `thread/revert` after commit but
before its response. An ambiguous revert can already have changed history.
Never retry it automatically; reconcile current history by thread ID first.
Driver `Session` correctly classifies `thread/revert` as a mutation because it is
absent from its read-only list, but that source fact does not qualify this
operation's uncertain native lifecycle. This profile only checks an empty uncertain
ledger after acknowledged results and restart, with no mutation replay.

Active-turn cancellation, pending server requests, reverting the first turn to
empty history, inherited/forked history, stale explicit resume paths, concurrent
pointer conflicts, unread-position retirement, all shutdown/reload failures,
direct-input restrictions, experimental-disabled gates and transport loss during
revert remain unqualified. A11 and other existing platform/external gates remain
incomplete. Keep these distinctions in any future manifest entry.

No native runtime repair, deadline increase or assertion relaxation was needed.
All commands and owned fixture/native processes completed before delivery.
