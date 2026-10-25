# Retained native queue field owners

This is a source/evidence mapping audit with no new test execution. Seven exact
request fields already have independent positive queue effects in the retained
native lifecycle test. They receive scoped implementation evidence rather than
duplicate tests or inferred whole-method success.

The historical v6 owning run uses immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, recorded executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It passes **115/0 at each 501432/987654**. Current owning queue test and both
provider fixtures byte-match its terminal guarded snapshot and both retained
native log hashes. No new binary or current whole-graph result is inferred.

## Exact physical owner mapping

All callsites below are in
`apps/samgita_codex_driver/test/native_queue_lifecycle_test.exs`.

| Owner | Field | Independent retained oracle |
| --- | --- | --- |
|5738 | Delete queuedSubmissionId | Lines 110–145/504–505 delete the prescribed second of three genuine native queue IDs; deleted:true and exact surviving third/edited-first records persist across native restart. |
|5739 | Delete threadId | The native-created thread selects that durable queue; the same exact survivors are observed through that thread after restart. No multi-thread or authority claim. |
|5743 | List threadId | Lines 118–129 require prescribed first/second/third page membership/cursors; lines 141–145 require the exact final surviving records after restart. Expected content comes from submitted literals plus correlated native add IDs. |
|5746 | Reorder queuedSubmissionIds | Lines 134–145 reorder third/second/first, delete second and persist third/edited-first. Lines 223–245/253–261 independently observe selected second→edited-first execution order through native user events and provider requests. |
|5747 | Reorder threadId | Durable surviving order is queried by the same actual thread across restart; dispatch also requires user-event/provider thread identity to equal that ID. |
|5748 | Start queuedSubmissionId | Lines 265–297 explicitly select genuine non-head second after restart and require second→first→third dispatch and exact provider counts. Lines 300–322 instead omit selection and dispatch first→second. Explicit null success remains unverified. |
|5749 | Start threadId | Lines 592–632 correlate actual user-event thread/turn, provider thread/turn/queue trigger, prescribed input and the genuine start response turn ID; exact queue drain and request counts prove the effect. |

No malformed/missing-ID, permission/auth/approval or other boundary assertion is
used for this mapping. The mixed owning suite is not rerun under the current
restriction. Its initial queue-start response state is not a selective-history
inProgress observation; no history emitter gap is reopened.

Five complete production files byte-match the archive, four exported schemas
match their pinned provenance and seven owner nodes match inventory hashes.
The [queue processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_queue_processor.rs#L99)
passes the supplied IDs/order to the
[queue service](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/queue/src/service.rs#L287)
and persistent operations. The
[SQL implementation](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/queued_items.rs#L107)
filters by thread, deletes the selected ID and commits reordered positions.
The synthetic provider only journals inputs and emits fixed assistant text;
Codex allocates queued IDs, stores records and chooses dispatch order.

## Historical binding and current limits

The byte-identical owning test SHA256 is
`6a4df174e6cce040c35ba48e0c1d2531b7fba3f944cfecf67ec564b657e73dfe`;
queued/base provider hashes are
`989d614f92d08cd2fe43798e144cf2a533a5a1082be118e902da63fd0087df16` /
`a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8`.
Native log hashes are
`9a604611fc729313391d351a486b69ca9db66810507681a51e4e9d04a9491f8d` /
`ab50dcb2f08ff855d57d4fe58a6879ad6aff1e0dbdaca93e147fe7c27c955c88`.

Ten of twelve relevant source bindings match; current Session and TurnFixture
differ from that historical graph. Therefore current complete-dependency
qualification remains unproven. A retained per-call raw-wire archive was not
established. No explicit-null start branch, aliases, whole-schema propagation
or verified promotion is claimed.

Detailed original/current hashes, exact assertions and terminal-log binding are
retained in `/tmp/samgita-v228-queue-owner-review/`. The historical runner is
`/tmp/samgita-native-cold-process-queue-v6-owning-20261025.py`, terminal record
`/tmp/samgita-native-cold-process-config-v6-terminal-20261025.json`, at historical
`4db58a8860e62d67117fa2b0ca093374ede1c7e0`. It was read without execution.

Only these seven rows receive retained scoped implementation evidence, recorded
in `/tmp/samgita-v231-functional-checks/manifest-binding-queue.json`. Contracts
become **4,695 implemented / 1,867 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified in both. The new
functional **35/0 twice** checkpoint does not execute this mixed queue suite or
replace its historical binding with a current-graph pass.

All seven fields remain incomplete for full qualification. Security/permission
checks and related broad/hosted workflows stay unrun under the current user
restriction. Full compatibility, A11 and external/OS success gates remain
incomplete; no release, publication or deployment is claimed.
