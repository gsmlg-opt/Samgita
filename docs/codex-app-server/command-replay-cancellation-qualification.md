# Cancel a replayed native command approval

The stock pinned Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **one test / zero failures** at both `501432` and `987654` (1.9 seconds
each). This strengthens the selected [approval-loss cases](approval-loss-qualification.md)
with a real command callback and cancellation across two actual WebSocket
connection replacements. It does not qualify the complete approval lifecycle.

## Observable sequence

`native_command_replay_cancellation_test.exs` owns an authenticated loopback
native listener and borrows connections to it through the existing test
transport. Fault injection stays disabled; the wrapper records only bounded
allowlisted outbound metadata while delegating real sockets.

1. A fixed private-shell printf produces the original native command approval.
   Thread/turn/item/request IDs, timestamp, cwd, complete argv and proposed
   private-shell authority are checked before any output/effect.
2. Explicit reconnect changes connection generation, retains driver/native
   identity and exposes the expected reconnect gap. Initialization and a
   loaded-thread query replay no callback and make no provider continuation.
3. Explicit warm resume replays the **exact original wire request**, including
   timestamp and ID, with a fresh generation-bound local handle. The old handle
   is stale. No approval response is sent.
4. Explicit `turn/interrupt` targets the original thread/turn. Both the native
   interrupted turn and original request resolution must arrive, in either
   order. Neither handle can subsequently approve work.
5. A second real reconnect, initialization and explicit resume produce no
   callback or command effect. Exact paginated history contains the one original
   interrupted turn and no durable command item. The cancelled callback cannot
   be reconstructed from history or resurrected by this resume.

The outbound journal requires **zero approval replies**, one turn/start, one
turn/interrupt and two thread/resume operations. Exactly one model call occurs
throughout; the model-only fixture rejects extra calls beyond its one diagnostic
continuation. No stdout, completed command, execpolicy file or changed workspace
entry is accepted. Canary bytes remain exact. Native owner/port survives closing
the borrowed Session and is then explicitly stopped with confirmed cleanup.

The 15-second event deadline and 200ms bounded quiet observation remain those of
the retained loss harness. Quietness alone is not the oracle: native terminal
history, request resolution, stable provider count, no outbound replies and the
source cancellation contract establish the result. Only the two expected
explicit-reconnect gaps are consumed and asserted; unexpected gaps fail. There
is no sleep-based retry, deadline increase, automatic approval or turn replay.

## Pinned source contract

Paths are relative to the immutable `codex-rs/` tree:

- `app-server/src/outgoing_message.rs` 281-286, 452-470, 588-601 retains ordinary
  pending requests across a connection closure and replays the actual stored
  request. `request_processors/thread_lifecycle.rs` 935-964 makes replay follow
  an explicit warm-resume response; reconnect alone does not invoke it.
- `request_processors/turn_processor.rs` 1619-1662 validates active turn
  identity and submits interruption. `bespoke_event_handling.rs` 1208-1223,
  1540-1569 cancels pending callbacks and emits the interrupted turn.
- `outgoing_message.rs` 221-236, 604-636 removes callbacks before delivering
  the turn-transition cancellation to their continuations.
  `bespoke_event_handling.rs` 1987-1988, 2039 and
  `request_processors/thread_lifecycle.rs` 1019-1041 retire the command request
  without submitting a stale approval and preserve its resolution identity.
- `core/src/tools/orchestrator.rs` 204-224 and
  `core/src/unified_exec/process_manager.rs` 530-539, 588-595 stop before the
  execution emitter. `app-server-protocol/src/protocol/thread_history_projection.rs`
  56-98 materializes durable core items, not a live pending-approval placeholder.

Cold pending callback replay is a separate unavailable path: ordinary callbacks
are in-memory (`outgoing_message.rs` 134, 250-257). This test never pretends a
new native process restores that store. Native-process loss must retain
uncertainty and reconcile durable effects; it cannot justify blind replay.

## Reproduction and limits

In verified Devenv from `apps/samgita_codex_driver`, with `MIX_ENV=test` and
`CODEX_BINARY` set to the exact hash-checked pin:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test test/native_command_replay_cancellation_test.exs --warnings-as-errors --seed 501432
mix test test/native_command_replay_cancellation_test.exs --warnings-as-errors --seed 987654
```

Root strict Credo, in-memory Python fixture parsing and exact source guards pass.
Runner/artifacts: `/tmp/samgita-native-command-replay-cancel-v1-20261024.py` and its
same-named directory. Both native runs pass on the first integrated attempt;
no failing assertion or timeout is suppressed. Ordinary launch safeguards,
private disposable HOME/CODEX_HOME/TMPDIR and no inherited credentials remain.
This does not prove OS network namespace isolation, physical packet loss,
exactly-once remote execution or real provider authentication.

Only existing command/resume/interrupt/resolution/reconnect requirements receive
supplemental evidence. No schema/state promotion occurs, no unexercised client
approval response is credited, and `lifecycle:approval-decisions` stays missing.
All remaining variants, cold pending callbacks, other transports/OS/services,
legacy emitters, A11 and final combination/hosted gates remain open. No
publication, release or deployment is claimed.
