# Native loaded-thread queries and runtime controls

This bounded native profile targets Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The test path is
`apps/samgita_codex_driver/test/native_thread_control_queries_test.exs`.
Its eight actual-native cases passed at seeds `501432` and `987654`. This
qualifies only the declared Linux stdio profile and its directly asserted
fields; full compatibility and external-provider readiness remain unverified.

## Ownership and isolation

The profile uses the existing, unchanged `TurnFixture`: owned temporary HOME,
CODEX_HOME, workspace, private shell path and synthetic loopback model dependency;
`StdioSessionFixture.register_cleanup` is called immediately after each Session
starts. Only explicitly owned app-server processes and fixture paths are closed
or removed. Every case asserts the model dependency received no requests. No
turn, command, approval, MCP invocation, live account or external credential is
required. The native app-server, rather than a protocol mock, handles every RPC.

This profile preserves the existing fixture isolation scope. It does not add a
network namespace or establish arbitrary external-provider readiness. The model
peer exists to reuse the established fixture; no model response is requested.

## Executed cases

| Case | Native assertions |
| --- | --- |
| Empty loaded set | Omitted/null defaults, zero limit and even a malformed string cursor return empty data and null nextCursor. |
| Sorted pagination | Three exact thread IDs sort lexicographically; zero acts as one; omitted/null limits return the remaining set; existing cursors are exclusive; final cursor is null. |
| Absent UUID cursor | Valid UUIDs below and above every generated ID select insertion points; uppercase UUID cursor canonicalization matches the existing anchor. |
| Native input errors | A malformed string cursor fails once the loaded set is nonempty; wrong JSON types and out-of-range u32 limits reach native deserialization and preserve loaded membership. |
| Unsubscribe statuses | Unknown UUID is notLoaded; first unsubscribe is unsubscribed; repeat is notSubscribed; the thread remains loaded and idle under the unchanged default idle delay. |
| Thread-local counters | Independent threads increment/decrement exact count and paused values; balanced zero rejects underflow; rejection leaves the counter usable. |
| Cold reset | Naming an empty paginated thread makes it durable without a turn; a new native process starts unloaded; counter access requires explicit resume; persisted identity/name survive, runtime count resets to zero and history remains empty. |
| Official experimental self-test | Exact empty/Unicode/control-string/null/omitted echo behavior; wrong types reject natively; disabled experimental negotiation rejects the self-test and counter methods before thread lookup. |

## Source contracts

All paths below are relative to the immutable `codex-rs/` checkout.

- `app-server/src/request_processors/thread_processor.rs:2887-2940` collects
  loaded thread IDs, returns early for an empty set before parsing a string
  cursor, sorts, canonicalizes a UUID cursor and uses binary-search insertion
  points. Its limit is `max(limit.unwrap_or(total), 1)`.
- `app-server-protocol/src/protocol/v2/thread.rs:1655-1678` defines nullable
  string cursor, nullable u32 limit, string data and nullable nextCursor.
- `protocol/src/thread_id.rs:13-45` generates UUIDv7 IDs but parses any valid
  UUID string. The all-zero and all-ones cursors are valid absent boundaries;
  tests explicitly assert their ordering against actual generated IDs.
- `app-server/src/request_processors/thread_processor.rs:974-990,1034-1064`
  separates loaded-thread lookup from unsubscribe's notLoaded, unsubscribed
  and notSubscribed statuses.
- `core/src/config/mod.rs:4031-4032` defaults idle unload to 1800 seconds. This
  profile does not wait for eviction, configure a zero delay or infer a closed
  notification from an unsubscribe response. Explicit eviction/event behavior
  belongs to the separate thread-event lifecycle profile.
- `app-server-protocol/src/protocol/v2/thread.rs:748-787` defines threadId,
  signed count and paused for increment/decrement.
- `app-server/src/request_processors/thread_processor.rs:1822-1862` derives
  paused from count greater than zero; core invalid-request underflow preserves
  its classification. Its shared load_thread does not implicitly resume.
- `core/src/codex_thread.rs:208-255,1226-1251` initializes runtime counters with
  Default, registers at zero-to-one, balances to zero, and rejects underflow
  with `out-of-band elicitation count is already zero`.
- `core/src/thread_manager.rs:975-1025` guarantees a materialized thread on a
  successful metadata update. `app-server/tests/suite/v2/thread_name_persistence.rs:1-112`
  is the upstream reference for naming an empty paginated thread and resuming
  it across restart before any turn. The test does not fabricate history or
  require an unmaterialized thread to survive restart.
- `app-server-protocol/src/protocol/v2/thread.rs:168-184` defines nullable
  optional self-test value and nullable echoed result.
- `app-server/src/request_processors/catalog_processor.rs:506-514` implements
  the actual embedded `mock/experimentalMethod` echo endpoint. It is an
  official test-only method, not an approval mock or general behavior proof.
- `app-server-protocol/src/protocol/common.rs:585-605,1217-1224` marks the
  counters and self-test experimental. `app-server/src/message_processor.rs:112-116,978-981`
  maps typed deserialization errors to Invalid request and enforces negotiated
  capability. `app-server/tests/suite/v2/experimental_api.rs:454-462` fixes the
  exact -32600 capability rejection and no-data response.

Malformed shape tests pass `validation: :wire` only to bypass the local pinned
schema gate and inspect actual native rejection. Other calls retain normal
local schema validation. Native type error assertions retain the exact error
classification and stable expected-type text without depending on JSON value
formatting inside serde's diagnostic string.

## Limits and remaining qualification

Counter response paused=true reports the pinned native counter state; no timeout
measurement or inference progress is tested. This does not prove all external
elicitation pause semantics, overflow recovery, concurrent counter ordering,
default idle eviction timing or event notifications. memoryMode remains outside
scope because its empty response alone cannot prove durable memory behavior.
The self-test qualifies only the upstream test endpoint's echo and negotiation.

Only directly asserted request/response fields should receive positive manifest
evidence. Full Codex compatibility, external integrations, A11, publication and
deployment remain separate gates. This profile changes no runtime, shared
fixture, manifest or CI configuration.

## Verification record

Installed and verified on main at baseline
`5c4ea77018f11b4f06bbe6c70301402b8fe29924`, with only this profile and this
document owned by the unit. Every command below exited zero and ran serially
under the exclusive validation slot; no repair was needed.

```sh
devenv shell --no-tui -- env MIX_ENV=test sh -c \
  'cd apps/samgita_codex_driver && mix compile --warnings-as-errors'
devenv shell --no-tui -- env MIX_ENV=test sh -c \
  'cd apps/samgita_codex_driver && mix format test/native_thread_control_queries_test.exs && mix format --check-formatted test/native_thread_control_queries_test.exs'
sha256sum tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl
devenv shell --no-tui -- env MIX_ENV=test \
  CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  sh -c 'cd apps/samgita_codex_driver && mix test test/native_thread_control_queries_test.exs --include real_codex --seed 501432'
devenv shell --no-tui -- env MIX_ENV=test \
  CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  sh -c 'cd apps/samgita_codex_driver && mix test test/native_thread_control_queries_test.exs --include real_codex --seed 987654'
devenv shell --no-tui -- env MIX_ENV=test mix compile --warnings-as-errors
devenv shell --no-tui -- env MIX_ENV=test mix credo --strict \
  --files-included apps/samgita_codex_driver/test/native_thread_control_queries_test.exs
git diff --check
```

The binary hash matched the immutable pin above. Native runs were **8 tests,
0 failures** in 4.7 seconds at seed 501432 and 4.5 seconds at seed 987654. Both
compile checks and the focused format/check passed. The root strict Credo
invocation loaded 320 source files and ran 69 checks, finding no issues.

After both runs, a read-only /proc inspection found no process whose executable
was the pinned native binary or whose argv selected the shared model fixture
script. No turn-fixture directory newer than the formatted test source remained.
Five older fixture directories and prior log files were preserved as unowned
pre-existing state. All launched commands completed; no process was terminated
outside the fixture's own cleanup. Sol repair rounds: 0.

## Positive evidence mapping

Line numbers refer to the installed test. Request and response entries share the
listed method; these are selected native behavior, not complete transport or
provider coverage.

| Method | Assertion lines | Qualified behavior |
| --- | --- | --- |
| `thread/loaded/list` | 24-127 | Empty short circuit; nullable/default/minimum limits; exact sorted IDs and exclusive/canonical/absent UUID cursors; final/null cursor; native input errors preserve membership. |
| `thread/unsubscribe` | 130-156 | Exact notLoaded, unsubscribed and notSubscribed status values; loaded/idle state after unsubscribe. No inferred closed event. |
| `thread/increment_elicitation` | 159-175,178-215 | Exact independent thread-local count/paused outputs, no implicit cold loading, reset after native process restart and explicit resume. |
| `thread/decrement_elicitation` | 159-175,178-215,265-267 | Balanced count/paused outputs and exact zero-underflow error; rejection leaves counters usable. |
| `mock/experimentalMethod` | 218-257 | Exact Unicode/control/empty/null/omitted echo; malformed values reject; disabled negotiation reaches exact native capability error. This is the upstream self-test endpoint. |

The new direct schema-field evidence is limited to:

- `v2/ThreadLoadedListParams.json#/properties/cursor` and `/properties/limit`;
  `v2/ThreadLoadedListResponse.json#/properties/data` and `/properties/nextCursor`.
- `v2/ThreadIncrementElicitationParams.json#/properties/threadId`;
  `v2/ThreadIncrementElicitationResponse.json#/properties/count` and `/properties/paused`.
- `v2/ThreadDecrementElicitationParams.json#/properties/threadId`;
  `v2/ThreadDecrementElicitationResponse.json#/properties/count` and `/properties/paused`.
- `v2/MockExperimentalMethodParams.json#/properties/value` and
  `v2/MockExperimentalMethodResponse.json#/properties/echoed`.
- `v2/ThreadUnsubscribeParams.json#/properties/threadId`;
  `v2/ThreadUnsubscribeResponse.json#/properties/status` and
  `/definitions/ThreadUnsubscribeStatus/enum/0`, `/enum/1`, `/enum/2`.

Canonical manifest IDs prepend `schema:` to those full schema paths. Existing
method/field evidence should be supplemented, preserving its prior limitations;
these assertions do not qualify unrelated fields of thread summaries, diagnostics
or resume responses. The project-wide acceptance matrix was not rerun by this
unit and remains the coordinating agent's responsibility.
