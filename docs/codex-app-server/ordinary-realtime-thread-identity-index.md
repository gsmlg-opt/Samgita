# Existing realtime notification thread identities

V521/V522 index existing actual-native evidence after pushed `7309e33` for
stock `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`.
Only two exact physical schema fields gain scoped implemented metadata.
The tests, scenarios, runtime, providers, fixtures, schemas, method inventory,
deadlines and capture bounds remain unchanged.

## Two distinct production paths

| Physical owner | Native event and public emitter |
| --- | --- |
| 5878: `ThreadRealtimeItemCompletedNotification.threadId` | Canonical `HistoryItemCompleted` becomes `thread/realtime/item/completed` in `app-server/src/bespoke_event_handling.rs:491–501` |
| 5880: `ThreadRealtimeItemStartedNotification.threadId` | Canonical `HistoryItemStarted` becomes `thread/realtime/item/started` in `app-server/src/bespoke_event_handling.rs:467–476` |

Each emitter independently takes the thread identity from
`conversation_id.to_string()`. The realtime lifecycle creates native UUID
session-started/closed items, reduces history effects and dispatches these two
canonical event kinds through their own public notification types. Eight whole
producer files and both standalone schemas equal the immutable official source
archive. The same primitive node hash does not establish sibling coverage;
the distinct production paths and received frames do.

Both standalone schemas require a string `threadId`, canonical node SHA256
`bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7`.
Their complete schema SHA256 values are:

- Completed: `b2a5e38840b8afc2111620c332801603e832b91ad4c95dd1f13c926923b760ef`.
- Started: `ef1a68a635ce680b321e276fd9144ef614b37bab16942368bdc16bb8ee217f46`.

## Existing original-frame oracle

The first case at
`apps/samgita_codex_driver/test/native_realtime_start_stop_test.exs:191`
obtains and UUID-checks a separate `thread/start` result. Its expected complete
maps require both started and completed notifications to carry that exact
thread identity for the native session-started and requested-close items.
Exact count/order, item association, connection generation and bounded native
timestamps remain required. Aggregate notification validation already requires
the same string field.

`assert_originals` compares these notifications with captured original inbound
JSON, then independently decodes each body through JSON and Wire. The case
retains exact timeline facts, its finite local realtime backend/no-inference
oracle and confirmed owned cleanup. The backend acknowledges its own WebSocket
protocol; it does not manufacture app-server history notifications.

Full-map equality rejects a missing, null, mistyped or incorrect thread ID.
An additional field assertion would repeat this oracle. Independent standalone
schema/archive checks bind these physical fields without changing the test.
The test SHA256 remains
`770f42dc299b9d30c438bd90ca78596c11352ca5c3dd72eab5a52bb5ae3ddf57`.

## Executed evidence and indexing boundary

The unchanged file is part of the just-passed **68-file / 129-case** ordinary
selection at seeds `501432` and `987654`. All fourteen reviewed functional
steps passed with 1,687 identical guarded hashes; see the
[combined-source results](ordinary-local-environment-info-qualification.md#final-combined-source-functional-qualification).
That execution used fingerprint
`c73312083a489a82c534e28dc4cde12a6c3484cd938fa1471025be9869fc3451`.

This index reuses that actual execution and requires a new metadata binding:
all executable/test/schema/config/fixture hashes and every command must remain
exact; only the two manifest nodes and the normalized fingerprint declaration
may change. It does not represent a new native run or new runtime behavior.
Current metadata fingerprint:
`f10b34714ca2cb70741ace0cef7c7745560b25ef7ee3223fd60415188118319a`.

| Source/review artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v521-next-gap-evidence.json` | `14fc3aee0807f4e1bb9f6387f917f141b365a7ed60d49da2e4768f50c184e590` |
| `/tmp/samgita-v521-independent-source-review.json` | `787fccebd173894cbd52deafe56985fe48e716781fb5540c84bd45218cb21c4a` |
| `/tmp/samgita-v522-next-gap-evidence.json` | `d1347609ae846681c92d3d5a3744f5f6fdcbb73e467736bb1fa3dd8dc9e4681c` |
| `/tmp/samgita-v522-independent-source-review.json` | `25303fa6854a780854c5e1d9e4bb3c9f9e6c48191f591ec965c0b223eec999b2` |

The final metadata binding passes. All **1,686** other guarded sources and the
complete command plan are identical to the passed execution. All 485
requirements and all 6,619 other contracts remain unchanged from `7309e33`.
Fresh inventory consistency and `git diff --check` pass. Eight producers,
both archive schemas, exact canonical nodes, all 14 result/log hashes and the
unchanged owning case are bound. No new native execution was needed.

| Final artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v521-v522-final-binding.json` | `230812aadefd5419bc524e25c1323932d9f30b123e09b343563b93f11c1e4fea` |
| `/tmp/samgita-v521-v522-inventory.log` | `a67dc4e224dce8a424dce25cf22d347c159835c322d112098e15f048542294d8` |
| Reused `/tmp/samgita-ordinary-v519-v520-qualified/results.json` | `b8a57e0e171a74b19fcbf1e8139f717bc163c2658d337be9f0cfb4594a605cfb` |

Only owners 5878/5880 change from missing to scoped implemented. Contracts:
**5,495 implemented / 996 missing / 130 blocked**; requirements unchanged at
**462 implemented / 12 missing / 11 blocked**. **Zero verified**. Transcript
and other item variants, aliases, arbitrary IDs, remote realtime services,
other transports/OS and complete-method acceptance receive no inferred credit.

Rollback removes this index and restores these two metadata nodes/fingerprint.
Security, credential, authentication, authorization, approval and permission
tests/audits, broad suites and hosted workflows stay unrun and incomplete.
A11, unavailable emitters/external/OS, full compatibility and release gates
remain incomplete. Automatic CI stays suppressed; no publication or deployment.

Next is the reviewed scratch addition of an explicit local
`featuredPluginIds: []` presence/value assertion to the existing plugin-filter
case. It is not integrated or executed and earns no state credit yet.
