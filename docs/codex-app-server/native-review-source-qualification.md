# Genuine Review child source discovery

The pinned ordinary inline Custom review creates a genuine persistent internal
Review child. Driver list/search can distinguish that actual child from its
vscode parent after producer shutdown and across two fresh native readers.
This supplements existing physical owner678,
`ClientRequest.json#/definitions/ThreadSourceKind/enum/5`, without promoting
any new owner or claiming complete review-method or provider compatibility.

Pin: `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Real producer and identity chain

`native_review_source_values_test.exs` starts an owned stock app-server and
creates a non-ephemeral Paginated vscode parent. One ordinary assistant turn
supplies a populated control. Genuine `review/start`, inline delivery and Custom
inert text then run the native ReviewTask/delegate path. The existing local
Responses fixture supplies the second assistant result. Native review parsing
accepts that plain text as an explanation with no findings; this is no claim
about model reasoning or code-review correctness.

The inline response identifies the parent review thread/turn. The second actual
model request independently supplies the internal child thread/turn and its
parent-thread/parent-turn linkage. Canonical child SessionMeta corroborates the
distinct thread ID, Review source, root session identity, parent, provider/cwd
and subagent attribution. Observed optional root-turn metadata agrees with its
durable counterpart; an absent root ID is not inferred. Real entered/exited review
and completion items belong to the parent. A public child thread-start event
or symmetric parent turn-start event is not invented.

Fixed bounded read-only readiness observes actual canonical completion and full
native paginated items. Parent completion alone is not a delegate flush barrier.
Public UserMessage/AgentMessage IDs come from actual durable `item_completed`
TurnItems. Raw user/assistant ResponseItems and classified environment context
are retained independently; environment text stays opaque. After normal owned
producer shutdown/reaping, canonical history and the two-request journal freeze.

Two fresh readers each issue child-only `subAgentReview`, parent-only `vscode`
and mixed-OR list/search before hydration. All12 filter requests and complete
responses retain original native correlation IDs. Independent source/ID sets,
12-field projections and literal snippets discriminate actual producer rows.
Subsequent full turn/item paging preserves actual user/assistant IDs/content
and parent review history through the cold replacement process. Loaded-thread
lists stay empty and model requests stay exactly two. Source/config/catalog,
history and provider journal bytes remain unchanged.

## Native projection differences retained

Two development failures exposed distinct native representations, not a reason
to repair or normalize native responses. Let P be the parent thread and C its
real Review child:

| Observed child representation | Source | Session identity | Parent | Thread attribution |
| --- | --- | --- | --- | --- |
| Canonical SessionMeta | `{"subagent":"review"}` | P | P | `subagent` |
| Unloaded Paginated/SQLite `thread/read` | `{"subAgent":"review"}` | C | P | `subagent` |
| Unloaded ordinary DB list/search | `{"subAgent":"review"}` | C | null | null |

Public SessionSource uses camelCase serialization. The stored public constructor
sets sessionId from thread_id; loaded/resume paths have their own startup
override. This profile establishes the displayed unloaded path, not universal
root-session consistency. The canonical root and provider lineage remain
independent assertions. Shared-session behavior on every API is unqualified.

List/search use rollout-summary conversion, which hardcodes thread_source=None.
Their ordinary state-DB scan rebuilds a page with an empty parent map; the
resulting child parent field is null. Search selects the same no-relation DB
path despite reading canonical text for matching. Persisted `thread/read`
separately recovers actual parent metadata from SessionMeta and classification
from SQLite. The parent vscode row also has null summary attribution versus
`user` in read. Every projection retains all12 fields with explicit
route-specific expectations. No field is dropped, synthesized in the driver or
treated as a successful general ancestry guarantee.

## Pinned source closure

Forty-four complete Rust/template files match their unique immutable archive
members. Key paths and source boundaries:

- `app-server/src/request_processors/turn_processor.rs:1452–1471,1569–1600`:
  genuine inline Custom dispatch and parent response identity.
- `core/src/tasks/review.rs:99–139,198–289` and
  `core/src/codex_delegate.rs:82–139,230–389`: actual Review child, assistant
  parsing, parent output and delegate shutdown limits.
- `core/src/session/session.rs:942–952,1038–1088`: actual root session and normal
  non-ephemeral persistence.
- `app-server-protocol/src/protocol/v2/thread_data.rs:27–56` and
  `app-server/src/request_processors/thread_processor.rs:6373–6441`: public
  source serialization and stored view identity.
- `thread-store/src/local/read_thread.rs:325–422`: richer persisted read.
- `thread-store/src/local/helpers.rs:130–184`, `list_threads.rs:306–321`,
  `search_threads.rs:97–138,167–181`, `rollout/src/state_db.rs:433–482` and
  `rollout/src/recorder.rs:2127`: summary ancestry omissions.
- `app-server-protocol/src/protocol/thread_history_projection.rs:78–108` and
  `protocol/v2/item.rs:873–909`: durable paginated message identity mapping.

Both actual list/search graphs resolve to canonical owner678. Actual
`review/start` resolves ReviewStartParams and the Custom ReviewTarget producer.
The exact independent enum-node SHA256 is
`5cc708a85d1d6e44ff3cf912b9ddffe694298365f329defe2360068555e9f006`;
export SHA256 remains
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
References, siblings and equal hashes gain no evidence from this test.

## Qualification and limits

Base: `ddbb5b5efc6bd9bfa6c87fdbddd18eb132c006c0`.
Elixir1.18.5/OTP27.3.4.17, independent driver paths, `MIX_ENV=test`,
`ERL_FLAGS='+S 2:2'` and the pinned binary. The owning profile passes1/0 at
seed501432 after the two documented source-backed projection corrections.
The initial integrated run stops at strict Credo, before native tests: one
complex canonical oracle and one nested readiness helper. Extracting metadata,
opaque-context and readiness helpers preserves all assertions, bounds and
deadlines. The final reviewed **57-file matrix passes111/0 twice**, seeds
501432/987654, command times206.490/196.564 seconds. Scoped format,
warnings-as-errors compile, strict Credo on507 sources, outside actual-binary
consumer1/0,30 fixture ASTs plus the existing inline Exec-launcher AST and the
**308-source guard** pass. All307 prior guarded sources remain byte-identical.
44 whole files, exact owner678 and actual producer/list/search request graphs
pass the source closure; final binding changes only this owner's evidence,
limitations and test references. No state or count is promoted.

Commands and the explicit functional allowlist are retained in
`/tmp/samgita-v336-final-run.py`; complete final logs are in
`/tmp/samgita-v336-functional-checks/functional-final/`. Initial static failure
is preserved in `functional-initial-static/`. Failed native oracles remain in
`/tmp/samgita-v336-owning-501432.log` and
`samgita-v336-owning-after-projection-501432.log`. Source and manifest binding
use `/tmp/samgita-v336-source.py` and `samgita-v336-bind.py`.

| Evidence | SHA256 |
| --- | --- |
| Final command results | `19aa9664a90166e6d1c3599b1580db1cf90c89f17a225419c7d7c6417010ecbf` |
| Source guard | `84800058629550e4469613015941ae270e3a0c1508f207f3ecb6ccee1a55f5bf` |
| Whole-source/schema closure | `e8ce420fb3a77325d082fcc4bfcf568679da981606b2f251be0a1e1e3edc81c2` |
| Manifest | `1e05e72cb7ac5e93cbc0ce32cc0266774fb75b1c618dcd2fcc7ae017694a652d` |

Inventory consistency passes; strict completeness still exits1. Counts remain
**462 implemented /12 missing /11 blocked** requirements and
**4,996 implemented /1,559 missing /66 blocked** contracts, zero verified.

The current ordinary code-review fixture uses fixed yolo setup. No security,
credential, authentication, authorization, permission or approval tests/audits
run. Broad suites and hosted workflows remain unrun under the user's
restriction. Other genuine source producers, legacy production, unavailable
external/platform/OS profiles, A11 and full-goal/release gates stay incomplete.
No real provider, publication, deployment or platform-readiness claim follows.
