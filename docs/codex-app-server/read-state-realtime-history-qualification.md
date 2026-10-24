# Native unread turns and complete realtime history

Five additional native cases qualify selected read-state and realtime history
behavior on stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The complete owning block passes **15/0** at both seeds `501432` and `987654`
(15.3s / 15.1s). Synthetic Responses/realtime services supply backend inputs;
the real native process creates all protocol results, notifications and stored
history. No app-server result, database receipt or replay cursor is injected.

| New cases | Independent observable behavior |
| --- | --- |
| Live terminal attention in both history modes | Three explicitly requested assistant turns produce distinct native IDs. The first unread position survives the second result while its CAS revision changes; acknowledgement permits the third to become the new first position. Exact read/list/changed payloads agree, changed precedes completed, stale read and unread fail with the exact winning turn state, and cold unloaded reads preserve history without replay or another provider request. |
| User delta and failed closure | Independently supplied user deltas differ from the final transcript revision. Exact user facts, UUIDv7 IDs and failed closure are retained by the complete warm timeline and a distinct cold native process. Existing warm failed-history coverage remains separate. |
| Active paging and cold cursors | Limit-one pages contain the two prescribed segments exactly once. Opaque cursors, canonical positions and the opening session agree before and after closure and cold restart; the actual session-start page opens at null. |
| Explicit terminal transcript-tail recording | Opt-in true persists all six ordinary-plus-realtime rows in order, with no inference. Delta facts retain delta text, while one recording-only UserMessage contains the revised final text in the exact XML-escaped delegation envelope. Its durable turn is completed with zero duration and no error; the whole unfiltered history survives a distinct unloaded process. |

The new tests are `native_read_state_fields_test.exs:113-234` and
`native_realtime_lifecycle_profile.exs:276-629`; exact fact/full-history/cold
helpers are at `894-990`. Previous null/threadStart and realtime assistant/ended
owners are not recounted. Nine previously missing physical contracts gain
selected implementation evidence: four notification turn-position nodes, user
role, failed outcome, realtime entry position, opening-session field and the
explicit tail flag. Existing cursor evidence gains no new owner count.

## Pinned source and unreachable response alternative

`app-server/src/request_processors/thread_lifecycle.rs:367-377` publishes
terminal attention before `turn/completed`.
`request_processors/thread_read_state.rs:91-152` requires a newly delivered,
eligible durable user-thread terminal event with visible attention and flushes
history before publication. `state/src/runtime/thread_read_state.rs:45-69`
retains the earliest unread turn, advances revisions and suppresses duplicate
publication. Official `app-server/tests/suite/v2/thread_read_state.rs:65-144`
and `state/src/runtime/thread_read_state_tests.rs:75-104` corroborate these
semantics; those source tests are references, not executed repository evidence.

The same shared type's four turn alternatives in
`v2/ThreadReadStateUpdateResponse.json` remain **missing**. At the pin,
`state/src/runtime/thread_read_state.rs:74-106` constructs Applied exclusively
as read => null or unread => threadStart. The processor at `181-189` returns
that owned Applied value after notification; a race cannot rewrite it into a
turn-position success. Conflict error data at `191-196` can contain the turn
winner, but is not this success response. No mock or equal-schema owner transfer
is substituted for the absent production path.

`core/src/realtime_history.rs:372-395` seals delta text independently of final
transcript revisions. `thread-store/src/local/thread_history/realtime.rs:199-247`
defines opening-session state strictly before the page's oldest entry, including
pages containing the later close fact. The tail flag defaults false in
`request_processors/turn_processor.rs:1259-1261`. When explicitly true,
`core/src/realtime_conversation/transcript_tail.rs:21-99` writes a recording
turn without starting inference; `core/src/context/realtime_delegation.rs:34-67`
defines the exact wrapper and escaping. All anchors refer to the immutable pin.

## Verification and limits

Commands ran serially from `apps/samgita_codex_driver`, with `MIX_ENV=test` and
`CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`:

```sh
devenv shell --no-tui -- mix format test/native_read_state_fields_test.exs test/native_realtime_lifecycle_profile.exs
devenv shell --no-tui -- mix test test/native_read_state_fields_test.exs test/native_realtime_lifecycle_profile.exs --warnings-as-errors --seed 501432
devenv shell --no-tui -- mix test test/native_read_state_fields_test.exs test/native_realtime_lifecycle_profile.exs --warnings-as-errors --seed 987654
```

Both terminal logs are `/tmp/samgita-native-unread-realtime-{501432,987654}-20261024.log`.
Driver formatting and strict Credo also pass. Test SHA256 values are
`b69feb35624d04f775e784fa2326b642b67cfad96222cec5472c1f73f3c7897a`
and `8f6e48020ee7d14e27ed380d2f5046425a7f20508e3939c22e4e3c8f36d87153`.
All original cleanup/owner-death guardians and deadlines remain unchanged.

The source audits and candidate hashes are in
`/tmp/samgita-unread-turn-source-audit-20261024.md`,
`/tmp/samgita-realtime-timeline-source-20261024.md` and
`/tmp/samgita-realtime-bem-tail-source-20261024.md`. BEM promotions, running-turn
tail association, empty-tail suppression, persistence failure, duplicate Core
publication, policy exclusions, real media/backends and other deployment
profiles gain no acceptance from these cases. Final combined-source/hosted
checks, complete compatibility and A11 remain incomplete. No release,
publication, external integration or deployment follows.

## Remaining direct operation owners

A subsequent source-only audit indexes **seven additional physical owners**
against the same unchanged test hash and two terminal **15/0** logs. Six are the
read/unread operation branch, `type` and enum nodes in
`v2/ThreadReadStateUpdateParams.json`. Requests at `236-263`, explicit success
and conflict assertions at `48-70,94-106,141-148,180-189` establish those exact
operations with independently constrained receipts, revisions and native effects.
The seventh is the distinct notification `threadStart` object branch: the test
prescribes that object at `48-50,239-246` and requires the exact ordered native
`thread/readState/changed` parameters at `63-70`. Already indexed children,
nulls and response owners receive no new count.

The outer `ThreadReadResponse.readState:null` is unasserted and remains missing;
it differs from the exercised inner `firstUnread:null`. The four successful
update-response turn alternatives remain missing for the immutable-source reason
above. No fabricated read/list-local definitions or same-hash transfer is used.
Candidate hashes and exact evidence are in
`/tmp/samgita-remaining-read-state-contracts-20261024.json`, SHA256
`2a1427820337442b942e51547fd8d8ac6461f9ffb5d3a2626a4fe845049a5ce5`, and
`/tmp/samgita-remaining-read-state-owner-audit-20261024.md`. This index adds no
runtime change, execution or fully verified promotion. Final-source matrices
and all remaining acceptance gates still apply.
