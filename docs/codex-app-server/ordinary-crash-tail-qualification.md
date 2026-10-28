# Genuine ordinary process-crash tail recovery

This unit follows `cd7cfd214bd0d87d90da8e626c32fb7818981dfa` on existing `main`.
It continues the full client/driver goal against stock Codex `rust-v0.163.0`,
source commit `83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`, archive
SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Fixed YOLO configuration remains opaque setup. No security, permission,
credential, authentication, authorization, approval or sandbox behavior is
tested. Audits, broad mixed suites and hosted workflows remain unrun under the
user's restriction. Retained gates and tests remain unchanged.

## Actual native failure and first cold content access

A second distinct case in `native_ordinary_active_page_recovery_test.exs`
reuses its unchanged ordinary provider and capture/setup helpers. The preceding
explicit-interruption case and its exact14-request inventory remain unchanged.
No production driver, transport, cleanup helper or native binary changes.

The first ordinary turn completes with independently prescribed content. The
second finishes its prescribed assistant message, starts an empty subsequent
item and holds before the provider terminal response. Native notifications
establish the serial-listener barrier. A public paginated
`thread/read(includeTurns:true)` must return the original completed prefix and
the exact canonical inProgress active turn, including original item identities,
content/order, full view and null terminal time/duration. This response comes
from persisted canonical pages after ordered native persistence; an ACK or live
overlay alone cannot satisfy the prerequisite.

Only then does a one-shot test controller SIGKILL the exact owned native
process. The original stdio helper remains the sole group reaper and cleanup
ACK producer. Independent observations require its real ACK, actual exit137,
normal Owner termination, nil Port, native/helper disappearance and the
Session's generation1 disconnected gap with no pending request or interaction.
The provider handler is closed only after that evidence, without ever writing
its active terminal response. There is no native interrupt, graceful native
close or provider cancellation before the crash.

A different native process uses the same untouched owned home. Its first
content operation is explicit descending/full turns/list, limit2. The entire
active turn equals the warm persisted object with only status changed to
interrupted; canonical items, original prefix and null terminal metadata stay
exact. Loaded-thread inventories remain empty. No resume, new turn, native
active terminal notification or additional provider request occurs.

## Checked-owned controller and cleanup evidence

`ordinary_crash_tail_controller.py` starts no Codex/server and writes no native
history. The test derives the helper PID from its exact owned Port and verifies
the Port's connected Owner process. It captures native/helper start identities,
the actual helper parent, complete expected launch argv, owned cwd/home and
known executable/helper hashes. The controller opens both pidfds and checks the
same identities before one native `pidfd_send_signal(SIGKILL)`. It never signals
the helper, retries a signal or falls back to an arbitrary numeric shell kill.
These are positive resource-ownership prerequisites for the lifecycle failure,
without permission or access-control outcome testing.

The immutable native executable and running image must match their pin. The
real stdio helper source remains SHA256
`34f63e30a21b040084a473c3c5ce9e175a43dce6691021ab3126d0d53dbce39f`.
The controller is pinned to
`71aa0085278620fdfc7b460bfc7604dab12fd4cdbce16a58fc1f0c8c4c38a0c5`.
Its bounded stdout proof is fixture control, separate from native protocol.
It cannot satisfy the independent real Owner completion atomics:
index1 requires actual ACK consumption and index2 actual helper exit137.
The test also requires real monitoring, Port closure, process reaping and
Session-gap observations. Original cleanup deadlines/guardians stay intact;
root deletion remains conditional on confirmed owned cleanup.

The controller requires Linux/Python pidfd support and fails explicitly if it
cannot establish its prerequisites. No disabled/skipped success substitutes for
an unavailable environment. The successful environment here meets them.

## Genuine persisted records and semantic limits

After confirmed reaping, the test reads only the bounded native-returned
canonical JSONL path beneath the owned synthetic home. It writes no rollout or
SQLite rows. The native file must contain exactly the two original task_started
identities, prefix-only task_complete, two exact canonical completed active
items and no turn_aborted. The unfinished subsequent item has no completed
record. Source-exact producer spellings and canonical UserMessage/AgentMessage
representations are required, rather than authoring a fixture history.

The canonical file's SHA remains unchanged after the first cold page and owned
cold shutdown. Thus interrupted is presentation normalization of a genuine
orphaned inProgress tail, not a newly persisted TurnAborted or execution
completion receipt. Exactly12 byte-backed correlated native request/reply pairs,
two initialized notifications, one thread, two original turns and two provider
requests occur. No automatic replay or duplicate execution is inferred.

This qualifies a process crash while the OS/filesystem remain running. Native
flush is not an fsync/power-loss guarantee. Corrupt/truncated JSONL, deliberately
missing projections, unfinished assistant-item survival, other OS/transports,
real model providers and full lifecycle/compatibility remain unqualified.
No Samgita/PostgreSQL recovery, task acceptance or platform cutover is exercised.

## Source basis and focused results

The pinned chain is canonical append → ordered recorder persist/file flush →
materialized paginated content response → actual owned crash/reap → first cold
page → status-only orphan normalization. Relevant sources are
`session/mod.rs`, `rollout/policy.rs`, `rollout/recorder.rs`, the live writer,
thread-history reader/projection, thread processor and thread status. The
read-only canonical oracle additionally follows `protocol/items.rs`,
`protocol/protocol.rs` and `history/rollout_payload.rs`/`history/lib.rs`.
The source report freshly matches twelve files against the exact archive; the
draft adds four serializer matches and independent review rechecks seven.

Source report:
`/tmp/samgita-ordinary-crash-tail-barrier-20261028-report.md`, SHA256
`d2761166d8f9c83ae1d166921020313f6e2f76293e0c9d106b12923e649fdc3e`.
Draft handoff:
`/tmp/samgita-ordinary-crash-tail-barrier-20261028-draft-handoff.md`, SHA256
`f53b542b76da6628eeaad04317cd25b884abb6e293ffb965308d99b1312fdbfc`.
Independent source-only review finds no material issue:
`/tmp/samgita-ordinary-crash-tail-review-20261028-report.md`, SHA256
`dd3d478176ccd639a32e9dbb5631a2831701e7d69116f5f894f1bb3e4587bcd2`.
These source artifacts are separate from real runtime evidence.

The complete owning file passes **2/0 at seeds501432 and987654** on its first
functional run, followed by strict Credo, against1,758 unchanged guarded sources.
Command times are5.819/5.716 seconds. Evidence:
`/tmp/samgita-ordinary-crash-tail-focused-20261028`.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-crash-tail-focused-20261028.py
```

Results JSON SHA256:
`e36cf19b8830b8cb0ab72e436fd137efb2be8c882563522f7e9612cb256d92cd`;
source JSON SHA256:
`4a8b5635da49330231d1ad49296a6cab50aef818885e93ebbfa53b3a1661d573`.
The focused gate precedes final manifest/runner integration.

## Final combined-source functional qualification

The separately counted extension group becomes11 cases. The original164-case
command and320-second bounds, other command selections, all prior assertions
and cleanup contracts remain unchanged. All **17 reviewed functional steps
pass** against **1,758 identical guarded sources**:

| Check | Actual result |
| --- | --- |
| Selected neutral overflow/replay | 16/0, 13 excluded at each of455834,501432,987654 |
| Original native block | 164/0 at501432 and987654;296.548s and285.162s |
| Separate native extension block | 11/0 at both seeds;18.592s and18.690s |
| Owned helper cleanup phases | 4/0 with original ACK/exit/deadline requirements |
| Outside-umbrella consumer | 1/0 against actual pinned Codex, no Repo/Phoenix |
| Other checks | Driver format/compile, inventory consistency, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-crash-tail-combined-20261028
```

Results JSON SHA256:
`5b40d2a87189beb6847e14cfab6c9d2b84e9583eddbe33718b4b9d327cd4d0ff`;
source JSON SHA256:
`07caa089cd8571cee75aad0a73b81da49f33bfdbe5d9cfc5c40748a59ccb7ff3`.
The source fingerprint is
`617339b109a51a70b3ced03e0d352f42cc785439c3ca067d3328d97bac9618e0`.
Every command and individual log hash is retained in that evidence directory.
The thirteen WebSocket exclusions are unselected existing tests, not removed
assertions. No prohibited test, audit, broad suite or hosted workflow runs.
This successful combination does not establish the earlier intermittent helper
cleanup cause, full compatibility, confidentiality acceptance or release readiness.

## Continuing boundaries

No physical schema-owner state changes. Five already implemented method/
lifecycle entries receive this bounded supplement. Requirements remain
**462 implemented /12 missing /11 blocked**; contracts remain **5,728 implemented
/757 missing /136 blocked**, zero globally verified. This removes the missing
runtime evidence for this precise genuine process-tail scenario, without
claiming power-loss or complete crash/transport recovery.

Next ordinary work remains the side-effect-aware installed-response null
producer and other source-supported functional gaps. A11's pre-emission
prerequisite, source-proven unavailable legacy emitters, real external/backend/
other OS success, prohibited and broad/hosted checks, full compatibility and
publication/release remain incomplete. Green repeats do not establish the
original intermittent cleanup cause. Existing dependency locks, database
safeguards, first interruption case and production cleanup stay unchanged.
Nothing is tagged, published, released, deployed or run against a live service.
