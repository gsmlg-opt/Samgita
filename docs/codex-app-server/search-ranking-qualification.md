# Independent native search and local plugin ranking

Target: immutable Codex rust-v0.163.0, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This record concerns real app-server output over Linux stdio, with disposable
owned histories, synthetic model responses and local plugin files. No scripted
app-server frames, paid tasks, external accounts or production data are used.

## First independent ordering failure

The first complete four-file block reports **24 tests / one failure**, seed
501432, 43.1 seconds. Its full and first-page search orders match the independent
raw native timestamps; the created_at ascending continuation repeats the first
thread instead of returning the second. The failed assertion remains in
`/tmp/samgita-native-cold-process-queue-v12-search-rank-attempt1-20261025/native-owning-501432.log`.
The second seed and later runner checks did not execute after that failure.
Separate strict Credo438 files passes on this source; it does not repair paging.

Pinned `rollout/src/recorder.rs:2170` serializes created_at with
SecondsFormat::Secs. `thread-store/src/local/search_threads.rs:216-240` builds
the forward created cursor from that truncated value. Native timestamp filtering
in `state/src/runtime/threads.rs:1507-1539` compares raw milliseconds. An ascending
cursor earlier than its fractional-millisecond anchor includes that anchor again;
descending filtering can omit a same-second remaining match. This is an upstream
observable limitation, separate from the already recorded reverse-cursor defect.
It is not repaired by increasing a deadline or by comparing one RPC with another.

The immutable upstream anchors are the
[recorder](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rollout/src/recorder.rs#L2170),
[search cursor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/search_threads.rs#L216-L240)
and [native filter](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/threads.rs#L1507-L1539).
The source-only diagnosis/report is retained in
`/tmp/samgita-thread-search-created-cursor-diagnosis-20261025/`.

The standalone test observes only its own state_5.sqlite using URI mode=ro and
PRAGMA query_only=ON. It never seeds, edits or repairs Codex state. Four actual
assistant turns produce two matching histories, a nonmatching control and one
later continuation that reverses created-versus-recency order. Original source
bytes, full history, native timestamps and provider counts must remain intact
through metadata reads, search and a confirmed cold restart.

The local plugin case supplies six competing name/keyword match ranks in reverse
marketplace order, plus a description-only control. Exact IDs, display names,
keywords, local provenance, installed:false and enabled:false are checked under
default/personal scope and cold restart. Search cannot silently install or enable
one. Remote search, sharing, authorization and pagination are separate profiles.

## Terminal scoped qualification

The corrected complete four-file native block passes **24/0 at both fixed
seeds**, 501432/987654, 44.4/43.9 seconds. Root and standalone warning-free
compile, format, namespace preflight and strict Credo438 files pass. Its
manifest-inclusive1,490-file source guard matches at terminal before later
evidence edits. The runner and same-named log directory are
`/tmp/samgita-native-cold-process-queue-v13-search-rank-attempt2-20261025.py`.
The terminal summary
`/tmp/samgita-native-search-ranking-v13-terminal-20261025.json` has SHA256
`b911ce1900be53450ecf427bc8a1d6b11a1c96bd6598d8da98be18b773397e6c`.

From the standalone driver, both fixed seeds run the complete owning files:

```sh
mix test test/native_search_projections_test.exs test/thread_search_timeline_test.exs test/native_thread_list_fields_test.exs test/native_plugin_lifecycle_profile.exs --warnings-as-errors --seed 501432
```

All six independent full/first-page expectations remain checked before any
continuation diagnostics. Updated/recency retain the intended remainder and
terminal null cursor. Created cursors must equal the exact independently
calculated floor-second token. The test computes the exact returned subset from
raw milliseconds, direction and limit, requires ascending duplicate/same-cursor
fixed point, and identifies exactly which descending rows are skipped. A
descending cross-second fixture may omit none; no same-second outcome is
invented. Cold starts repeat these exact wire outcomes and saved continuations.
No automatic retry, cursor rewrite or production workaround is introduced.
The original failed ordinary-pagination assertion remains evidence that a valid
created_at paging guarantee is **incomplete**; a passing defect regression does
not close it. Required fractional timestamps are explicit fixture prerequisites.

Only four physical properties gain scoped implemented evidence: search Thread
createdAt/updatedAt/recencyAt and PluginSummary.keywords. The two existing data
owners gain depth. There is no sibling-schema/alias/wrapper or verified
promotion. Regenerated totals are485 requirements:462 implemented/12 missing/
11 blocked;6621 contracts:3399 implemented/3222 missing;zero verified.

Plugin source/config/skill bytes remain exact, auth.json remains absent, and no
turn, installation or enablement occurs. Search sources/history/raw timestamps
remain exact through warm/cold reads with exactly four provider calls and no
approvals. All owned sessions are explicitly closed with retained cleanup.
Only local Linux stdio, selected paginated search and first-page local plugin
ranking are evidenced. Reverse/valid-created pagination, complete summary
fields, remote storage/plugin pages, account/backend/OS success, A11 and full
compatibility remain incomplete. Complete final-source matrices are required.
