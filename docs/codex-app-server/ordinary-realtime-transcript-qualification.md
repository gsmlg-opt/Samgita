# Ordinary native realtime transcript

V435 runs on `main` base `928b49c3120257fb47d8ad04fdb47a4538c7803a`.
Only seven physical owners become scoped implemented:2683–2687 for the canonical
transcriptSegment alternative/role/text/type/literal,6395 for the separate whole
timeline alternative, and5883 for the separately validated v2 delta threadId.
Canonical identities and hashes remain in the manifest and source artifact.

The [ordinary test][test] adds one opt-in transcript case to the existing
[finite peer][peer], preserving the original six-notice/two-row start-stop case.
Native launch remains direct fixed YOLO, one local V2 WebSocket and one native
session.update. No model turn, Responses request, inference, audio or handoff is
needed. After the actual start RPC, complete native start prefix and recorded
peer ACK/update readiness, a single zero-body local POST releases a peer Event.
The control request/response is independently prescribed and bounded at8KiB
combined/5s, using stdlib TCP. No sleep stands in for readiness. The peer emits
only these legitimate backend messages:

```text
response.output_text.delta: "Owned realtime λ "
response.output_text.delta: "draft."
response.output_text.done:  "Owned realtime λ revised final."
```

The independent durable text is `Owned realtime λ draft.`. The native flat done
notice separately preserves the revised final text. Exact complete item oracles
require an initially empty assistant transcript and its final streamed text,
with caller session `owned-v435-realtime-session`. Native item IDs are distinct
UUIDv7s from observed item starts; no type/role/text/session expectation comes
from output. The different backend ACK identity never replaces caller identity.

Thirteen complete original native envelopes must arrive in order: start item
pair/start, empty transcript item-start, first item/flat deltas, second item/flat
deltas, streamed transcript item-completed, revised flat done, ended-close item
pair/closed. Full prescribed params, bracketed emittedAtMs, generation, sequence
and original pre-Session JSON/schema/decode identity are checked. Both original
item-delta params also equal independent complete `{threadId,itemId,delta}`
maps and separately validate `v2/ThreadRealtimeItemTranscriptDeltaNotification`
for5883. Public item delta uses the actual `transcript/delta` spelling; the
default case now explicitly rejects all three real transcript methods.

Original start response/start facts precede release; all seven transcript
notices precede the one explicit stop request. Stop response remains the exact
correlated `{}`, independently of terminal delivery; no ACK/terminal mutual
ordering is assumed. Real thread/read forms the store barrier. Two complete
timeline pages must equal start/transcript/closed rows in increasing nonnegative
positions, nextCursor:null and activeRealtimeSessionAtPageStart:null. The page
contains neither empty transcript nor revised done text. Its own response schema
and original correlated wire are checked;6395 does not inherit notification
ownership from a shared hash. Final drain rejects extra selected notices, server
requests, ordinary turns/items, gaps and uncertainty.

Peer journal requires one WS path/update, two HTTP requests including exactly
one functional control, ACK plus exactly the three backend messages, no Responses
or unexpected HTTP. Frozen inputs and final journal remain exact through checked
native/peer owner/PID/Port/socket/thread/listener cleanup. Closing releases the
Event before sockets/joins. Original limits remain128frames/events,64KiB inbound/
8KiB outbound,2MiBcapture/journal,32peerframes,5sstages,20sactive/60scase. The
default case retains its original requests, ACK-only journal, zero transcript/
inference, two-row page and all cleanup checks. No bound/assertion was relaxed.

Official pin remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Thirteen whole sources match the immutable archive. Native V2 parsing occurs at
`protocol_v2.rs:39–43`; `realtime_history.rs:340–395,419–444` concatenates deltas
and seals an existing segment without replacing its text from done. Native
`session/realtime_history.rs:21–52` emits history effects and durably appends
completion before delivery; `bespoke_event_handling.rs:467–499,543–566` emits
item events and the distinct flat done. Source/seven-node evidence:
`/tmp/samgita-v435-binding/source.json`, SHA256
`10c0010e5ae580b6d375f327b6fe0cacfe3b1067baaccd35432495d7d5426040`.

Focused actual-native **2/0**, final30-module **49/0** twice at501432/987654
pass,81.458/82.109 command seconds. Eleven Python syntax checks, scoped format,
driver compile with warnings as errors, root strict Credo and inventory pass.
All414guarded sources stay stable;412prior paths stay exact and these two files
change. Exact commands/logs/source guard:
`/tmp/samgita-v435-functional-checks/final/{results,source}.json`, SHA256
`ca197cd3f1ef1b64c4af1b872cf3947371b97da5eb8d0619624ed527b2b8c4c7` /
`e06b4bbbdb0b509d4e819c41394158aa6250b30608d270893dd4082279120b9d`.
Test/peer SHA256:
`01f993d12f36a263b91f49ccdebae5cd76b7d5e6316433046a0e943c24022573` /
`f895e8ffeb3fd39141d71d4572b06c221acd446be0e250ce32750e40fc34b6f6`.
Binder `/tmp/samgita-v435-bind.py`; evidence
`/tmp/samgita-v435-binding/evidence.json`, SHA256
`3cc2b4d67872df6efd126b724f20db812d56d2a7627b768d719ea13c7bd3d9ce`.

Contracts become **5,225 implemented /1,330 missing /66 blocked**; requirements
remain **462 implemented /12 missing /11 blocked**, zero verified. Only the
selected assistant transcript/Linux stdio/local V2 backend profile is covered.
User-role/done-only/tail/backing-turn/reconnect/audio/media/remote and other OS/
transport profiles remain unqualified. Prohibited tests/audits, broad suites and
hosted workflows stay unrun; A11, unavailable legacy/external/platform/full-goal/
release gates stay incomplete. Push suppresses CI; no publication/deployment.
Rollback removes this opt-in scenario/seven bindings while retaining default
start-stop behavior and historical records. Continue the original dynamic-tool
item ingress profile; a scoped checkpoint does not complete the goal.

[test]: ../../apps/samgita_codex_driver/test/native_realtime_start_stop_test.exs
[peer]: ../../scripts/codex/ordinary_realtime_fixture.py
