# Positive native search-source owners

This evidence-indexing unit starts from
`eb821c96986b0821efcdf9e11aea6765508449f0` on `main`. It changes only the manifest
and documentation. Existing ordinary tests, production code, fixtures, schemas
and all 386 sources in the immediately preceding passing matrix are unchanged.
No additional runtime behavior is claimed by indexing these observations.

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The source archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Seven independently bound physical nodes

Each pointer below belongs to its own standalone export. Its exact literal and
inventory-encoded node hash are checked independently; matching hashes or a
canonical request definition do not transfer evidence between endpoints.

| Owner | Export | Pointer within definitions | Positive literal |
| --- | --- | --- | --- |
| 6073 | `v2/ThreadSearchParams.json` | `ThreadSourceKind/enum/0` | `cli` |
| 6075 | `v2/ThreadSearchParams.json` | `ThreadSourceKind/enum/2` | `exec` |
| 6078 | `v2/ThreadSearchParams.json` | `ThreadSourceKind/enum/5` | `subAgentReview` |
| 6080 | `v2/ThreadSearchParams.json` | `ThreadSourceKind/enum/7` | `subAgentThreadSpawn` |
| 6098 | `v2/ThreadSearchResponse.json` | `SessionSource/oneOf/0/enum/0` | `cli` |
| 6100 | `v2/ThreadSearchResponse.json` | `SessionSource/oneOf/0/enum/2` | `exec` |
| 6108 | `v2/ThreadSearchResponse.json` | `SubAgentSource/oneOf/0/enum/0` | `review` |

The [typed method declaration:841–844][method] uses those parameter/response
types. [Source filtering:6–81][filters] distinguishes Cli, Exec, Review and
ThreadSpawn, while [actual search:2774–2884][search] applies those selectors,
returns native stored matches and converts their source. The public
[source conversion:27–56][public] preserves Exec/Cli strings and the nested
Review representation. Thirty-two complete upstream sources match their unique
immutable archive members, including those endpoint and producer chains.

`native_exec_source_values_test.exs` creates genuine Exec and terminal Cli
sessions through the stock executable, separately from a vscode control.
Each of its two cases uses two fresh native readers; each reader sends actual
singleton source, vscode and mixed-OR searches before hydration. Exact captured
request bytes/IDs, independently known matching ID sets, prescribed snippets
and full source projections require positive returned Cli/Exec rows. These are
discriminating searches, rather than empty-result exclusion checks. See
[Exec](native-exec-source-qualification.md) and
[Cli](native-cli-source-qualification.md) for native production and normal-exit
barriers, original failed-oracle evidence and retained history details.

`native_review_source_values_test.exs` creates a real inline Custom code-review
child, distinct from its vscode parent. Provider metadata and canonical history
identify that child independently of search. Both fresh readers send child-only,
parent-only and mixed-OR searches, requiring exact IDs and the nested public
`{"subAgent":"review"}` result. This is an ordinary code-review producer;
see its [qualification](native-review-source-qualification.md).

The [V1 child search case](v1-child-search-qualification.md) independently
creates and closes a genuine child, then sends exact warm/first-cold
`sourceKinds:["subAgentThreadSpawn"]` queries. The original known child, real
snippet, complete source and retained history must match. This specifically
binds input selector 6080; it does not re-count its already implemented null-path
owner or infer umbrella-source input coverage.

## Evidence and limits

All three unchanged owning modules are present in the final reviewed matrix
recorded by the [ordinary input-wait unit](search-user-input-wait-qualification.md):
**87 schema / 154 ordinary driver cases at both 501432 and 987654**, outside
consumer **1/0**, scoped format/compile, strict Credo and inventory consistency.
The current 386 source bytes equal that passing guard. Model journals,
canonical/public history, empty loaded lists, correlated native responses and
checked owned-process cleanup remain exact. This source-equivalence binding
does not claim another runtime or broad-suite run.

Only the seven named physical contracts change from missing to scoped
implemented. All requirement rows remain byte-for-byte equivalent as data:
**462 implemented / 12 missing / 11 blocked**. Contracts become **5,076
implemented / 1,479 missing / 66 blocked**; both inventories have zero verified.
The binding and exact hashes are under
`/tmp/samgita-v385-functional-binding/binding.json`, with generator
`/tmp/samgita-v385-bind.py` and source-only recipe
`/tmp/samgita-v385-ordinary-recipe.md`.

No parent/union, alias, other endpoint or exclusion-only appServer/Compact/
Other/Unknown source receives promotion. No positive umbrella `subAgent` input
oracle is asserted. Other transports/backends/OS, real providers, upstream
unavailable producers, A11 and full-goal acceptance remain incomplete. Security
and permission tests, audits, broad suites and hosted workflows remain unrun
under the user's restriction. No package is published or service deployed.
Rollback reverts only these seven evidence records and documentation.

[method]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L841-L844
[filters]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/filters.rs#L6-L81
[search]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2774-L2884
[public]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs#L27-L56
