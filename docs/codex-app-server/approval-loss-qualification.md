# Native approval replay and ambiguous response loss

The later [command loss unit](command-approval-loss-qualification.md) adds three
actual-native command paths without changing the original file/permission
oracles or deadlines. The full owning block passes10/0 at both seeds; the
six-case results below describe their earlier source checkpoint. The broad
approval lifecycle remains incomplete.

Six tests against stock Codex `rust-v0.163.0` pass at seeds `501432` and
`987654`, **6/0** each, 8.6 seconds each. Source commit:
`83086188ae0614bd882818ff1aa23f3194962012`; binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The independent driver connects to an explicitly owned, authenticated native
WebSocket listener. Its local Responses fixture supplies fixed model output;
all app-server messages, approval callbacks, history and file effects come from
the immutable native executable.

## Observed outcomes

Each of file-change and permission approval exercises three separate paths:

- An unanswered callback survives a borrowed connection disconnect. Initialize
  and read do not replay it. Explicit warm resume returns the exact original
  request, including wire ID, parameters and creation timestamp, under a fresh
  local generation/reference. A stale handle cannot answer the current request;
  only an explicit response produces the single owned file effect.
- The test transport drops one outbound response before peer receipt while
  reporting local send success. The driver records `sent_unconfirmed`, then
  `uncertain` on disconnect. Warm resume replays the pending original request.
  There is no automatic response or turn retry. A fresh explicit response has
  the same wire digest, while the old generation's uncertainty remains visible.
- The real response reaches Codex, but the transport suppresses its actual
  resolution/completion notifications. Bounded metadata proves those native
  notifications arrived. Exact file bytes, provider counts and read history
  establish completion of the original turn. Resume finds no pending callback;
  nothing is retransmitted. Only explicit caller acknowledgement retires local
  uncertainty after reconciliation evidence is available.

The test-only transport forwards delivered bytes unchanged and never creates an
app-server frame. These are deterministic losses at the client transport boundary,
not evidence of observed TCP packet loss. Outbound/discarded metadata is bounded
and contains allowlisted IDs, status and digests rather than payloads or credentials.

The file scenarios make exactly two model calls; permission scenarios make three
and prove a real patch follows the recovered grant. Each history contains exactly
one completed turn. Request identities, explicit-null file fields, local permission
environment/root, fresh handles, counters, no policy files and no automatic
inference are asserted. Borrowed reconnect/close leaves the native listener's
owner alive; final cleanup uses the existing confirmed owned-process shutdown.

## Failure, correction and validation

The initial seed `501432` run failed **4/6** in 11.7 seconds. A test completion
predicate passed the notification helper's absent `nil` to strict Boolean `and`,
raising `BadBooleanError`. No native/protocol defect was established. The test
now checks `not is_nil(...)` explicitly and matches resolution against the exact
original request ID and thread. Both final repeats pass without removing an
assertion, adding a retry, or changing a deadline or product implementation.

From the independent driver in verified Devenv, with `MIX_ENV=test` and the exact
hash-checked `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_approval_loss_test.exs --seed 501432
mix test test/native_approval_loss_test.exs --seed 987654
mix format --check-formatted test/native_approval_loss_test.exs \
  test/support/approval_loss_transport.ex
```

Python AST, namespace prerequisite and scoped strict Credo on the test and support
module also pass. Initial logs:
`/tmp/samgita-approval-loss-initial-*-20261024.log`; corrected logs:
`/tmp/samgita-approval-loss-boolean-fix-*-20261024.log`. The default native CI
suite includes the test. Final aggregate and hosted evidence is recorded separately.

## Immutable source and limits

References are relative to the pinned `codex-rs/` source:

- `app-server/src/outgoing_message.rs:281-287,452-506,568-603` retains ordinary
  pending callbacks across connection loss, replays them unchanged by thread,
  and consumes a callback before delivering its result to the tool continuation.
- `app-server/src/request_processors/thread_lifecycle.rs:719-746,930-971` uses
  live thread state and explicitly replays pending requests after warm resume.
- `app-server/src/outgoing_message.rs:134,250-257` initializes callback storage
  in memory. This does not support cold callback replay after native process loss.
- `app-server/src/bespoke_event_handling.rs:1799-1853,1939-1969` maps actual
  permission/file replies without an approval-response acknowledgement RPC.
- `core/src/session/mod.rs:3013-3054,3190-3225,3310-3401` owns callback lifetimes
  and permission grants; `core/src/tools/handlers/apply_patch.rs:495-553` applies
  the resulting authority to a real filesystem effect.

There is no generic approval-response status query or upstream deduplication
guarantee. An absent replay alone cannot establish success; use authoritative
history and effects, and retain uncertainty when those are insufficient. Do not
resend a state-changing operation because its connection changed. This unit
strengthens selected implemented contracts and leaves the broad approval lifecycle
missing. Cold pending callbacks, other interaction kinds, TLS/UDS/proxy loss,
real external networks/services, OS profiles and A11 remain unqualified. No
publication, deployment or complete-compatibility claim is made.
