# Native realtime ended-outcome evidence index

V437 is evidence-only on `main`
`204bea4a8f1e6baa2f18649500b4ecf3ecf988cc`. Only physical owner2700,
`ServerNotification.json#/definitions/ThreadRealtimeSessionOutcome/enum/0`,
becomes scoped implemented. Its independently prescribed literal is `ended`,
canonical SHA256
`58e05e8d66023d540d23db5ddf55315f3248253a94c754dda9d1508e8b2855f9`.
There is no executable change or new test run.

The unchanged first [ordinary realtime case][test] already requires complete
native closed-item started/completed envelopes with outcome:ended after one
explicit requested stop. It prescribes the caller session, item type and outcome
independently; only native UUIDv7 identity and measured emission times are bound.
Original JSON captured before Session decoding equals the complete expected
notifications and validates the canonical experimental ServerNotification
schema. Correct generation, exact order/counts, original RPC correlation and
native stop brackets remain. The peer never creates an app-server closed item
or outcome. Two exact stored timeline reads corroborate persistence; the equal
hash of already implemented timeline owner6412 is not the notification proof.

Pinned native `realtime_conversation.rs:2036–2057,2812–2826` supplies requested
closure. `realtime_history.rs:281–296` creates a fresh actual closed item and
selects Ended when its failure flag is false. Public conversion in
`protocol/v2/realtime.rs:126–132`, durable append in
`session/realtime_history.rs:33–52` and native notification emission preserve it.
Six whole upstream files and the single canonical node match the immutable
archive/export. Source pin remains `83086188ae0614bd882818ff1aa23f3194962012`,
Codex `rust-v0.163.0`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source evidence `/tmp/samgita-v437-binding/source.json`, SHA256
`4f87f6d12003eeecf6f923a165b78ec04c91996cdce84e0eb2432a29ac8bc9f2`.

This reuses [V435's final-source checks][prior]: focused **2/0**, **49 ordinary
cases twice**, all eight permitted check logs and414matching source hashes.
No historical mixed realtime module or new audio scenario is run. Exact reused
commands/logs/source guard:
`/tmp/samgita-v435-functional-checks/final/{results,source}.json`, SHA256
`ca197cd3f1ef1b64c4af1b872cf3947371b97da5eb8d0619624ed527b2b8c4c7` /
`e06b4bbbdb0b509d4e819c41394158aa6250b30608d270893dd4082279120b9d`.
Test SHA256:
`01f993d12f36a263b91f49ccdebae5cd76b7d5e6316433046a0e943c24022573`.
Binder `/tmp/samgita-v437-bind.py`; evidence
`/tmp/samgita-v437-binding/evidence.json`, SHA256
`03b21c9b58997d08314ce48fb9869f94c627c302d6239c47ab79db5f4b030eed`.

Contracts become **5,226 implemented /1,329 missing /66 blocked**; requirements
remain **462 implemented /12 missing /11 blocked**, zero verified. Failed
outcome, other closure conditions, audio/media/remote services and other OS/
transports remain unqualified. Synthetic audio forwarding would not establish
actual media acceptance. Prohibited tests/audits, broad suites and hosted
workflows remain unrun; A11 and legacy/external/platform/full-goal/release gates
stay incomplete. No publication/deployment. Rollback restores this one evidence
binding without changing runtime or history. Continue the original dynamic-tool
item ingress unit.

[test]: ../../apps/samgita_codex_driver/test/native_realtime_start_stop_test.exs
[prior]: ordinary-realtime-transcript-qualification.md
