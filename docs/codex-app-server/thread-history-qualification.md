# Native search, occurrences and timeline

Six actual-binary cases in
`apps/samgita_codex_driver/test/thread_search_timeline_test.exs` use immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012` and the
Linux musl executable pinned in [qualification](qualification.md). Codex writes,
indexes and reads its own history in disposable workspaces. A loopback model
fixture supplies deterministic turns; it is not a replacement app-server.

| Profile | Assertions |
| --- | --- |
| Content search | Escaped quotes, slashes, Unicode and literal content survive filters and recency pagination. Exact native source is `vscode`; archived and live searches remain distinct across process restart. |
| Occurrences | Three repeated case-insensitive matches retain exact UTF16 snippet ranges, turn/item IDs and inclusive turn cursors. Pagination continuation survives a cold process. |
| Invalid cursors | Malformed, cross-thread and cross-query cursors return exact correlated upstream errors without changing results; zero limits follow native clamping. |
| Timeline | Turn boundaries and user/assistant items retain canonical positions, IDs, status, nullable voice state and integer timestamps/duration. Reverse pagination has no gaps or duplicates; cold continuation agrees. |
| Fork and revert | The child retains the inherited prefix plus its own history. Later parent turns and a parent revert cannot change child search/timeline evidence. |
| Gates and storage | Upstream itself rejects experimental calls without negotiation. Legacy history and archived timeline return their documented errors; archived occurrences and legacy content search remain readable. |

`thread/read` with `includeTurns: true` provides the upstream persist/project
barrier before querying history. No index polling, sleep, retry-until-green,
assertion removal or timeout increase establishes readiness. Each case asserts
the exact number of model requests.

## Pinned exporter discrepancy and correction

The initial run had four failures: three valid timeline responses failed schema
validation, and one source-filter expectation incorrectly assumed `appServer`.
The source expectation now explicitly requires the actual `vscode` value.
A bounded trace of one owned Session's received stdio bytes captured the real
timeline response without bypassing validation. Its `turnStarted` and
`turnCompleted` entries use `turnId`, `startedAt`, `completedAt` and `durationMs`.
The official JSON export instead describes/requires corresponding snake_case
names. This is an upstream export/serializer discrepancy, not a slow response.

Exact source evidence, relative to the immutable source's `codex-rs/`:

- `app-server-protocol/src/protocol/v2/thread.rs:1875-1920` applies serde
  `rename_all_fields = "camelCase"` to `ThreadTimelineEntry`. Boundary variants
  have matching TypeScript renames but lack per-field schemars renames. The item
  variant already supplies explicit matching schemars/serde/TypeScript names.
- The same binary's experimental `v2/ThreadTimelineEntry.ts` contains the
  camelCase boundary fields. The unchanged experimental
  `v2/ThreadTimelineListResponse.json` contains the snake_case boundary fields.

`scripts/codex/generate_output_semantics.py` derives a narrowly scoped output
contract correction from the pinned Rust and executable-generated TypeScript.
`source/output-semantics.json` names the six property renames across these two
variants. Provenance hashes the full Rust source, TypeScript export and descriptor;
the descriptor also records the original JSON hash. Generation and offline checks
fail on unsupported naming, structure or source/TypeScript disagreement.

`Schema.Output` checks those hashes and corrects only property/required names in
this response's validation contract. It does not transform received values,
accept the exporter-only identity, replace the validator, alter types, relax
integer bounds or discard fields. All official stable/experimental JSON bytes
remain unchanged. The manifest preserves exported contract IDs/pointers and adds
explicit native wire names; the response records a hash of its effective contract.
Changed effective contracts cannot inherit prior progress evidence silently.

Three protocol regressions first failed **3/3** and then exercise native names,
original-export disagreement, required identity, integer bounds, nullable times,
union/type rejection and opaque additions. Three Python regressions check exact
renames, unchanged official bytes, fail-closed source/TypeScript/export mutations
and manifest metadata. These are contract tests, separate from the six real
native history journeys.

The six native cases passed at seeds `501432` and `987654` with compilation
warnings as errors and scoped formatting. The coordinator's complete native
protocol suite then passed **37 tests**, seed `501432`; the goal/MCP regression
combination passed **9 tests**, seed `987654`. Logs:
`/tmp/samgita-thread-search-timeline-{initial,contract-fix}.log`,
`/tmp/samgita-native-timeline-{wire-diagnostic,contract-red,inventory-tests}.log`.
The complete protocol/goal/MCP output is
`/tmp/samgita-native-timeline-protocol-goal-mcp-green.log`.
The synthetic diagnostic response is local only; it contains no real credentials.

Realtime/audio timeline entries, every item/field variant and other supported
transport/OS profiles remain unqualified. The selected search, occurrence,
timeline, turn-list, archive, fork and revert entries are implemented; this is
not full history compatibility or Samgita Task acceptance. Final aggregate and
hosted results remain separate evidence.
