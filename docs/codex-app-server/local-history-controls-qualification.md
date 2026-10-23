# Native local-history controls qualification

This profile targets the actual Codex `rust-v0.163.0` app-server, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Eight actual-native cases passed twice in
`apps/samgita_codex_driver/test/native_local_history_controls_test.exs`.
The evidence covers selected memory metadata, local compression, retained
summary and cached Git-diff behavior. It does not establish full compatibility.

## Scope and ownership

All four requested methods have production handlers in the pin. The profile
uses unchanged TurnFixture, including its immediate Session cleanup registration,
owned temporary HOME/CODEX_HOME/workspace and synthetic loopback model dependency.
Every case checks that ModelFixture.requests is empty: no model turn, command,
paid task, approval or MCP invocation is required.

Only native-created synthetic thread records are changed. SQLite observation is
read-only, bound to the fixture's state_5.sqlite and parameterized by native ID.
The test does not create schema rows, seed fake memory success, use Samgita.Repo,
or edit memory state through SQL. Legacy JSONL metadata is observed directly;
paginated metadata is observed in SQLite, matching the pinned ownership contract.
No consolidation, memory retrieval or external memory service is qualified.

Compression starts with two actual native-created, materialized empty legacy
rollouts. Both native writers are closed before aging only the selected file's
mtime to eight days. Startup compression is explicitly disabled in the owned
configuration so the explicit request is the trigger. Native writer locks, the
six-hour run marker and cooldown remain intact; no lock is forged or removed.
An actual plain-to-Zstandard file transition must complete before preservation
checks. The empty response alone is never treated as completion.

Git fixtures create a disposable local worktree and a disposable bare repository
under the fixture root. The origin URL names that local bare directory only;
the fixture seeds local tracking refs and symbolic origin/HEAD without fetching,
pushing, cloning or contacting a network remote. This qualifies computation from
cached local refs, not the freshness or contents of a real remote. Hooks and
commit signing are disabled for the owned fixture. No project repository or
external Git configuration is modified.

This reuses the existing TurnFixture isolation scope; it does not introduce a
network namespace or expand external-provider authorization.

## Executed native cases

| Case | Required observable behavior |
| --- | --- |
| Loaded legacy memory mode | Disabled/enabled/disabled RPCs append exact native SessionMeta memory_mode values and persist the same SQLite value; no turns exist. |
| Paginated cold memory mode | SQLite mode survives native restart; unloaded metadata updates persist enabled then disabled across another restart without implicitly loading the thread. |
| Memory rejection | Unknown thread, ephemeral metadata changes, malformed UUID/mode/type and disabled negotiation reject explicitly and preserve the prior durable value. |
| Explicit compression | After startup with compression disabled, an eligible closed native rollout becomes .jsonl.zst with Zstandard magic; a recent sibling remains byte-identical and plain; summary reads survive the transition and restart; explicit native resume rematerializes every original byte as the prefix, with no turn. Repeat ACK is labeled trigger-only. |
| Unsupported store and negotiation | In-memory store returns exact -32601 for compression with null/omitted or wire-only empty-map params and -32600 for rollout-path summary queries. Nonempty-map/scalar params fail native deserialization; disabled negotiation rejects before store dispatch. |
| Persisted summary | Empty paginated summary matches native ID/path/cwd/provider/version/source, null gitInfo and empty preview; timestamps have store millisecond precision; absolute/relative path and ID selectors agree across cold restart, including stable-only negotiation. |
| Summary rejection | Missing UUID/path, directory path and malformed selectors return exact errors or typed native deserialization errors, with no fabricated result and no loaded thread. |
| Local cached Git diff | Clean local snapshot returns exact baseline SHA and empty diff; changed tracked/untracked Unicode contents appear under their expected hunks; a repeated read is identical; nonrepository and malformed cwd fail. |

## Immutable upstream contracts

Paths below are relative to the pinned codex-rs checkout.

- `app-server-protocol/src/protocol/common.rs:704-729` declares experimental
  thread/memoryMode/set and rollout/compress; the latter accepts optional unit
  params. `common.rs:1482-1492` retains both legacy summary and Git methods.
  `app-server/src/message_processor.rs:1438-1444,1544,1830` dispatches all four
  methods to production processors. `app-server-protocol/src/export.rs:76`
  deliberately keeps the legacy methods in the export allowlist.
- `app-server-protocol/src/protocol/v2/thread.rs:1120-1156` restricts the public
  memory enum to enabled/disabled; threadId is required; response is empty.
  `thread.rs:115-119` makes an explicit historyMode experimental, so paginated
  threads are created before switching to stable-only negotiation in summary
  qualification.
- `app-server/src/request_processors/thread_processor.rs:1895-1915` performs
  the memory metadata update through ThreadManager with include_archived=false.
  `core/src/thread_manager.rs:975-1025` rejects ephemeral updates, routes loaded
  and cold paths and guarantees materialization on successful metadata updates.
  `thread_processor.rs:6343-6352` preserves native invalid-request classification.
- `thread-store/src/local/update_thread_metadata.rs:92-104,157-178,195-225`
  separates paginated SQLite metadata from legacy SessionMeta compatibility.
  `update_thread_metadata.rs:606-612` persists memory_mode in SQLite;
  `update_thread_metadata.rs:877-925` records and flushes native legacy metadata,
  including temporary writer shutdown for cold updates. The tests read these
  outputs rather than infer persistence from the empty RPC response.
- `state/src/sqlite.rs:38,60-69` pins state_5.sqlite under the configured root;
  `state/src/runtime/threads.rs:101-106` reads the exact threads.memory_mode row.
  `app-server/tests/suite/v2/thread_memory_mode_set.rs:22-111` asserts loaded and
  stored persistence directly through the state database. The profile uses an
  external read-only Python SQLite connection for the same durable observation.
- `app-server/src/request_processors/rollout.rs:10-24` checks LocalThreadStore,
  spawns the worker and returns trigger acknowledgement.
  `app-server-protocol/src/protocol/v2/rollout.rs:8-13` explicitly warns that
  acknowledgement is not completion and locks/cooldowns can skip work.
- `rollout/src/compression.rs:53-59,364-370,386-431,470-493` defines background
  ownership, seven-day age, six-hour marker cooldown and claimed local runs.
  `compression.rs:909-922,935-965,976-999` preserves writer publication fencing,
  source rechecks and age checks. `compression.rs:116-177` rematerializes plain
  data for append. No protection is disabled by this profile.
- `app-server/tests/suite/v2/rollout_compress_tests.rs:24-66,69-102,106-131`
  is the upstream reference for explicit trigger after startup with the feature
  disabled, completion observation, experimental rejection and in-memory-store
  rejection. The profile substitutes native-created no-turn data for a fabricated
  rollout and observes actual completion with a bounded deadline.
- `app-server/src/request_processors/thread_processor.rs:5714-5760` reads
  summaries through the production thread store by ID or local path.
  `thread_processor.rs:6298-6340` fixes missing-ID and path-error mapping;
  `thread_processor.rs:6450-6494` maps stored fields and millisecond timestamps.
  The similarly named read_summary_from_rollout and extraction helpers in
  thread_summary.rs are cfg(test), not the production evidence path.
- `thread-store/src/local/read_thread.rs:135-190,201-241` resolves relative
  paths from CODEX_HOME, supports plain/compressed representations and classifies
  directory/missing paths. For paginated summaries it uses canonical SQLite
  metadata. `app-server/tests/suite/conversation_summary.rs:76-113,211-252`
  supplies ID and relative-path references; no legacy notification emission is
  claimed by returning a retained legacy request's result.
- `thread-store/src/local/read_thread.rs:31-112` prefers SQLite for an ID read
  and substitutes legacy rollout display metadata only when its preview is
  nonempty. Thus this empty legacy thread retains SQLite `updatedAt` by ID;
  its path read uses file mtime. The profile captures both full maps before
  compression, asserts the exact aged path timestamp with millisecond precision,
  and preserves each map after compression and cold restart. The same source's
  missing-rollout fallback supplies exact `no rollout found for thread id ...`
  memory-update errors; `thread_processor.rs:6343-6352` retains -32600.
- `app-server-protocol/src/protocol/common.rs:229-248,271-288,722-729` declares
  the internally tagged request and `Option<()>` compression params, then
  converts the incoming JSON into that enum. `Cargo.lock:14007-14010` pins
  serde 1.0.228. That version's `src/private/de.rs:1301-1320`
  `ContentDeserializer::deserialize_unit` accepts unit or an empty map and
  rejects nonempty maps/scalars. `app-server/src/message_processor.rs:112-116`
  maps deserialization failures to -32600 with `Invalid request: ...`.
  In contrast, the unchanged official experimental `ClientRequest.json:9022-9043`
  permits only null/omitted params. Local `Schema.validate_message/4`
  (`apps/samgita_protocol_codex/lib/samgita_protocol_codex/schema.ex:133-162`)
  enforces that exported schema. The empty-map test explicitly uses
  `validation: :wire` to observe the native accepted representation and asserts
  the exact unsupported-store -32601; it is not a successful compression or
  deserialization-rejection claim. No provider schema was rewritten.
- `app-server-protocol/src/protocol/v1.rs:85-125,136-140,184-187` defines both
  summary selectors, all summary fields and the Git cwd/sha/diff contract.
  `app-server/src/request_processors/git_processor.rs:11-36` maps failed local
  computation to native invalid request.
- `git-utils/src/info.rs:355-368,433-449,454-478,600-704,706-775` computes from
  cached refs, honors symbolic remote HEAD, selects the closest remote SHA and
  appends untracked diffs with no textconv/external diff hooks. The symbolic HEAD
  fixture avoids the separate git-remote-show fallback, which could otherwise
  inspect a configured remote. No fetch/push occurs in the selected path.

## Positive field mapping

The passing native profile supports selected positive behavior evidence for
eight method entries: client_request and server_response for each of
thread/memoryMode/set, rollout/compress, getConversationSummary and
gitDiffToRemote. Compression and memory responses are empty contracts with no
field promotion inferred from an acknowledgement.

Twenty exact schema IDs support positive field evidence, with `schema:` prepended:

- `v2/ThreadMemoryModeSetParams.json#/properties/threadId`
- `v2/ThreadMemoryModeSetParams.json#/properties/mode`
- `v2/ThreadMemoryModeSetParams.json#/definitions/ThreadMemoryMode/enum/0`
- `v2/ThreadMemoryModeSetParams.json#/definitions/ThreadMemoryMode/enum/1`
- `supplemental/v1/GetConversationSummaryParams.json#/anyOf/0`
- `supplemental/v1/GetConversationSummaryParams.json#/anyOf/0/properties/rolloutPath`
- `supplemental/v1/GetConversationSummaryParams.json#/anyOf/1`
- `supplemental/v1/GetConversationSummaryParams.json#/anyOf/1/properties/conversationId`
- `supplemental/v1/GetConversationSummaryResponse.json#/properties/summary`
- `supplemental/v1/ConversationSummary.json#/properties/conversationId`
- `supplemental/v1/ConversationSummary.json#/properties/path`
- `supplemental/v1/ConversationSummary.json#/properties/modelProvider`
- `supplemental/v1/ConversationSummary.json#/properties/cwd`
- `supplemental/v1/ConversationSummary.json#/properties/cliVersion`
- `supplemental/v1/ConversationSummary.json#/properties/source`
- `supplemental/v1/ConversationSummary.json#/properties/timestamp` (nonnull only)
- `supplemental/v1/ConversationSummary.json#/properties/updatedAt` (nonnull only)
- `supplemental/v1/GitDiffToRemoteParams.json#/properties/cwd`
- `supplemental/v1/GitDiffToRemoteResponse.json#/properties/sha`
- `supplemental/v1/GitDiffToRemoteResponse.json#/properties/diff`

Two additional fields remain limited boundary evidence, not positive promotions:
`schema:supplemental/v1/ConversationSummary.json#/properties/preview` is observed
only as an empty string, and
`schema:supplemental/v1/ConversationSummary.json#/properties/gitInfo` only as null.
No gitInfo object/nullability variant, absent timestamp, nonempty summary preview,
arbitrary source variant or unrelated native Thread/read/diagnostics field is
qualified. Missing-input errors do not promote additional positive variants.
Formatted source groups: lines30-130 memory,132-218 compression/store/gates,
220-286 summary and288-328 Git. Helper observations start at331.

## Verification status and limits

Installed and validated on shared `main` baseline
`4fb9125a5024236ee25738be98dac689ba47a8ab`, with only the named test and this document
owned by this unit. No shared runtime, fixture, configuration, schema, manifest or
Git state was changed by this worker. Final test-source SHA-256:
`195106940b340e5a1fa3f1f62468e29e5751de7545bd10d4cb6da3d865f6bb50`.

The initial actual-native run at seed501432 failed:8 tests,3 failures,9.7s,
exit2 (session61130 terminated). These were incorrect expectations: a missing
memory ID uses the store fallback text; empty legacy ID/path summaries have
different timestamp sources; an empty map reaches native unit dispatch rather
than deserialization failure. One bounded repair corrected those expectations,
retaining all eight cases, exact ID/path maps, physical compression, cold
persistence, byte-prefix preservation and the original timeouts. It added native
nonempty-map/scalar rejection checks. Cumulative repair counters: Sol1/Astra0.

Commands actually run from the repository root (2026-10-24 Asia/Shanghai):

```sh
sha256sum tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl
devenv shell --no-tui -- env MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl sh -c 'cd apps/samgita_codex_driver && mix test test/native_local_history_controls_test.exs --include real_codex --seed 501432'
devenv shell --no-tui -- env MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl sh -c 'cd apps/samgita_codex_driver && mix test test/native_local_history_controls_test.exs --include real_codex --seed 501433 && mix compile --warnings-as-errors && mix format --check-formatted test/native_local_history_controls_test.exs'
devenv shell --no-tui -- env MIX_ENV=test mix compile --warnings-as-errors
devenv shell --no-tui -- env MIX_ENV=test mix credo --strict --files-included apps/samgita_codex_driver/test/native_local_history_controls_test.exs
```

Binary hash matched the immutable pin. Repaired seed501432 passed8/0 in10.5s;
unchanged seed501433 passed8/0 in10.3s. Both sessions exited0. Independent driver
compile, focused format/check and root compile passed. Root strict Credo actually
checked323 source files despite the requested file selector; it ran69 checks and
found no issues (4.4s,3217 mods/funs). Read-only `/proc` inspection after validation
found no pinned native executable or model-fixture process. No turn-fixture
directory had mtime at/after the formatted test (2026-10-23T21:35:26.219372Z);
older unowned fixture directories were preserved. Every case asserted an empty
model-request log. All owned validation commands finished; the validation slot
was released to the coordinator. Repository-wide tests, hosted CI and publication
were not run by this unit.

This bounded profile does not prove concurrent memory updates, memory
consolidation, compression lock races, disk failures, marker expiry, arbitrary
Git histories, real remote freshness, all nullable/source variants or full Codex
compatibility. A11, external providers, package publication and deployment remain
separate gates. The coordinating owner handles manifest integration, commit/push
and final aggregate qualification.
