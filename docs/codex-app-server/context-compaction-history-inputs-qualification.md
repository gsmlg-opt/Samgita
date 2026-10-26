# Generic ContextCompaction history inputs

Two real pinned-native profiles qualify current generic Responses decoding,
raw/durable item identity and supplied-history consumption for ContextCompaction.
The source is a local synthetic Responses stream, not a real provider's
compaction service. This evidence does not establish legacy production emission,
remote-v2 checkpoint installation or full context restoration.

## Decode, capture and consume

`apps/samgita_codex_driver/test/native_supplied_context_compaction_history_test.exs`
uses `scripts/codex/supplied_context_compaction_history_fixture.py`. Its first
Responses stream supplies only `{"type":"context_compaction"}` followed by an
ordinary assistant message. Native Codex supplies the cmp_ ID and source-turn
metadata, writes the durable response item and emits the real
`rawResponseItem/completed` notification when `experimentalRawEvents` is enabled.
The fixture writes no app-server frame, native ID, rollout row or sidecar.

After one completed source turn and explicit native close/reap, the test captures
the native-written whole user/context maps. Independent equality fixes original
user ID, source turn/time and classification, plus the complete context map:

```elixir
%{
  "type" => "context_compaction",
  "id" => actual_generated_cmp_id,
  "internal_chat_message_metadata_passthrough" => %{"turn_id" => actual_source_turn}
}
```

Exactly one actual raw notification must equal that entire durable context map
and have the expected thread and turn. No normal contextCompaction UI item or
compaction action is inferred from the raw variant. No compacted checkpoint row
is fabricated or expected.

A distinct cold native begins with an empty loaded list. One profile imports
both actual maps unchanged through unstable `thread/resume.history`. The other
deliberately sets only context metadata to present client null, independently
expecting only that key to be omitted from the native persisted copy. This is
modified current input, not native-null emission. Both require a new idle
thread/path, whole maps once/in order and no turn or inference during import.

One explicit continuation consumes the exact original context copy with only
non-OpenAI passthrough removed; the original cmp_ ID remains. Source and followup
user markers each occur once and initialization metadata states supplied_history.
The literal followup assistant answer and correlated turn completion are required.
No tool or additional compaction work occurs. Requests stay **1 → 1 → 2** per
profile. Complete imported originals, source/config/catalog/script bytes and
empty workspace remain checked before/after followup and after native close/reap.

## Source reachability and exact owners

Only these `ClientRequest.json` physical nodes under
`/definitions/ResponseItem/oneOf/16` gain implementation evidence:

| Owners | Evidence and limit |
| --- | --- |
|433|Current whole raw ContextCompaction object|
|435|Actual generated nonempty cmp_ ID; null-ID behavior is not covered|
|436/437|Actual source-turn metadata property/object branch|
|438|Separate deliberate client-null metadata, normalized to omission|
|439/440|Exact context_compaction type and literal|

Owner434 stays missing and unchanged. Deferred Trigger430–432 and Other441–443
also stay missing and unchanged; shared hashes or references receive no promotion.
Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Twenty-one complete production files match the pinned official archive and
fourteen physical nodes independently match their canonical hashes.

The source investigation reads all8665 regular archive members, including5259
Rust files. No ordinary explicit ContextCompaction constructor or recorded
incoming Responses fixture is found in that bounded review. That does **not**
prove unreachability: `codex-api/src/sse/responses.rs:354–359` is a current generic
production deserializer of this exact ResponseItem. The actual-native profile
exercises that path, not an invented backend producer. Backend implementation
and historical production traffic are outside this source archive and remain
unverified.

`core/src/session/turn.rs:2855–2927`, `tools/router.rs:257–308`,
`stream_events_utils.rs:93–105,360–399` and `session/mod.rs:3481–3753` establish
ordinary non-tool recording with native identity/metadata preparation.
`session/mod.rs:4391–4400`, the opt-in thread listener and
`app-server/src/bespoke_event_handling.rs:1167–1181` establish real raw events.
`rollout/src/policy.rs:80–99` and `context_manager/history.rs:1033–1053` retain
ContextCompaction while filtering Trigger/Other. The thread processor's current
Forked-history route preserves supplied originals; `core/src/client.rs:1007–1018,
1092–1095` explains metadata stripping with the prefixed ID retained only in the
separate provider copy.

## Verification and bounds

The owning module passes **2/0**, seed501432, in3.8seconds, log
`/tmp/samgita-v315-context-history-501432.log`. Before execution, complete user
and context assertions are separated to retain strict Credo complexity limits;
all full-map, time, distinct-ID and order oracles remain. No native semantic
failure or repair is observed.

Final commands/environment: `/tmp/samgita-v315-run.py`; artifacts:
`/tmp/samgita-v315-functional-checks/functional/`. The final reviewed
**46-file matrix passes91/0 twice**, seeds501432/987654, in
**169.948/160.244 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on496 sources, outside actual-binary consumer **1/0**, twenty-five fixture
ASTs and the **292-source** guard pass. All prior290 guarded sources match
baseline `5bc887591270dbf193fbed92b584a033d60f8677` byte-for-byte; only the new
test and Responses producer are added.

| Evidence | SHA256 |
| --- | --- |
| Results | `bc1c10598d83bb55b3f6ffac1cd30482a789a8c6a6ed7ec0329ee65f5bd9991e` |
| Source guard | `94e61ad7d1d711fbd6f740a134bc6573ab64fb9e45d9db90bcfce867ffefc3dd` |
| Twenty-one pinned files and fourteen nodes | `c726568972968cef1ae3b6834b3edac7d7ff6f2b00a7a7e457fe579a0638810d` |
| Resulting manifest | `73d7dc76af6fbd0e32ac9f1581be93d570707f5f0754d13094e09531f61ca6cf` |

Existing256event/8MiB Session defaults,256event/1MiB local capture/import,
4MiB files/2048rows/262KiB lines and20s/60s event/case deadlines remain.
Owned process guardians, native close/reap and provider owner/completion/Port
checks precede root removal. No timeout increase, blind retry or weaker gap
assertion occurs. Fixed yolo is setup, not policy qualification.

Final binding proves exactly seven promotions with schema identities, planned
tests, requirements and all excluded/deferred owners unchanged. Inventory
consistency passes; strict completeness exits **1**. Contracts become **4,944
implemented / 1,611 missing / 66 blocked**; requirements stay **462 implemented /
12 missing / 11 blocked**, zero verified. Actual provider emission, legacy
execution, remote-v2 installation, arbitrary metadata, full restoration,
external/OS/transports, A11 and full compatibility remain unqualified.
Prohibited safety/auth/permission/approval tests and broad/hosted workflows stay
unrun. Release gates remain incomplete; no publication or deployment occurs.
