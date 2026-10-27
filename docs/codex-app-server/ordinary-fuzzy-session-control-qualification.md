# Native fuzzy search correlation and registered-session removal

V506 follows `20045af` on the existing `main`. Target: official
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the existing ordinary functional test, evidence and selector change;
the driver, upstream implementation and platform remain unchanged.

## Actual ranking, populated stop and distinct cold process

`native_fuzzy_notification_envelope_test.exs` retains its original full/subset
case, literal ranking goldens, original-ingress capture, fixture construction
and owned-resource cleanup. Three additional cases each launch two sequential
real native processes against their own five-file tree. The complete one-shot
result must equal the independently authored oracle: `abexy` score84 and
indices0/1/2, `sub/abce` score72 and indices4/5/7, `abcde` score71 and
indices0/1/4, including exact root, path, name, type and order.

| Case | Warm query / stop IDs | Cold query / stop IDs |
| --- | --- | --- |
| Negative integer | `-5061134` / `-5061154` | `-5062134` / `-5062154` |
| Positive integer | `5061134` / `5061154` | `5062134` / `5062154` |
| Unicode string | `owned-search-λ🙂-warm` / `owned-stop-雪🙂-warm` | `owned-search-λ🙂-cold` / `owned-stop-雪🙂-cold` |

Each actual stop follows explicit session creation and an original native
notification containing that exact nonempty ranking. The original ingress
ledger must place this snapshot before the stop request. Its original typed-ID
ACK must be followed by the exact native `-32600` missing-session update error.
A separate one-shot query must still return the complete ranking. A successful
no-op stop of an absent session cannot satisfy these checks.

Warm owner/Port/native process shutdown is confirmed before cold startup.
Cold requires distinct native and Session PIDs, an unchanged warm capture prefix,
the old opaque session ID absent before recreation, no startup/one-shot session
notification replay, and the same complete query/start/populated-stop journey
with distinct operation IDs. A newly created Session may restart generation1;
each event is checked against its actual current generation. No thread/model
execution or automatic replay occurs.

Original sent/received bytes, exact one-response-per-request correlation,
strict codec round trips, full request schema, original notification maps,
native emission clock and causal ordering are required. Each warm/cold pair
has23 outgoing frames and21 responses, including initialization; variable
partial/idle notices remain bounded. Original limits stay30s per case,5s per
operation/selected notice,1s cleanup,128 captured frames/1MiB aggregate,
4KiB outbound and64KiB inbound. Tree/config/workspace/code bytes stay frozen.

## Pinned source and limits

Original IDs are String or signed i64 in `app-server-protocol/src/rpc.rs:13–21`.
Actual handlers are in the immutable
[search processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/search.rs#L39-L134):
real one-shot matching, registration, update/error and registry removal.
The [official ranking fixture](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/fuzzy_file_search.rs#L220-L296)
independently prescribes the literal result.

Registry removal is not worker join or a post-ACK notification fence.
`app-server/src/fuzzy_file_search.rs:111–116` sets cancellation;
`file-search/src/lib.rs:159–166` signals shutdown. The reporter checks
cancellation before spawning outgoing work, so an already spawned notice may
arrive after ACK. All captured late notices are validated after shutdown;
there is no quiet-window assertion, busy-walker claim or invented final fence.

Nine whole producer files and the two precise canonical nodes are archive-equal
in `/tmp/samgita-v506-implementation-evidence.json`, SHA256
`7a06960f76fe7d630bb9469497c4ae3cc5dd98992e13375d30a814cdc0574114`.
The independent source review found no actionable defect. Only physical
ClientRequest `id` owners1134/1154 gain scoped implemented evidence, canonical
SHA256 `f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.
No alias, complete cancellation lifecycle, other transport or full-method
qualification follows.

## Qualification and remaining gates

Initial focused runs pass **4/0** at seeds501432/987654 in7.0/6.9s. Strict Credo
then fails because `assert_typed_inventory` has complexity10, maximum9.
Extracting only the expected outgoing-method list preserves all assertions,
counts, effects and deadlines. Corrected focused runs again pass **4/0** at
both seeds in7.0/6.9s, and strict Credo passes across593 files. Original logs
are `/tmp/samgita-v506-focus-501432.log` and
`/tmp/samgita-v506-focus-987654-credo.log`.
The corrected log is `/tmp/samgita-v506-final-focus-credo.log`.

The final command
`devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v506-qualified`
passes **14/14** reviewed checks. All **61 files / 120 actual-native cases**
pass at seeds501432/987654 in205.5/204.3s. Selected WebSocket overflow/replay
cases pass at455834/501432/987654; the outside consumer passes **1/0**.
Inventory, driver/umbrella warning-free compilation, format, strict Credo,
Dialyzer and assets pass. All1,680 guarded sources stay identical, fingerprint
`fb92547339a1e68c6833237a2f6259ce42584b17d1dcbea5c8ebbfc1ade82ef1`.

| Final evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-v506-qualified/results.json` | `3159e397517bb67a2a5eea7e115bff4b5c5efee98b9b84f9b51bd76f2c122dcc` |
| `/tmp/samgita-ordinary-v506-qualified/source.json` | `22ac7d183057fb424f7bf6ac6ba898bece5e8b5f761e591b011be35e234152d2` |
| `/tmp/samgita-v506-final-binding/source.json` | `72a147281b7b9dee220ce094f5a36b1bddd560c4da9a82c47f296bb1bd448107` |

The binding rechecks all nine complete producers directly against the immutable
source archive, both canonical nodes and final owning test/launch/cleanup bytes.
Original full/subset goldens, capture, setup, native startup, run_profile and
cleanup remain byte-identical to20045af. Exactly two physical owners become
scoped implemented: **5,477 implemented / 1,014 missing / 130 blocked contracts**.
Requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
Next is the reviewed idle `thread/inject_items` durable-ACK/cold-continuation
profile; its scratch implementation is not yet runtime evidence.

No security, credential, authentication, authorization, permission or approval
test/audit, broad suite or hosted workflow runs. Fixed yolo settings remain
ordinary setup. Prohibited checks, A11, unavailable emitters/external/OS success,
complete compatibility and release remain incomplete. Nothing becomes verified.
Rollback removes these test/evidence extensions without modifying persisted
platform records. No package publication, deployment or live credential change.
