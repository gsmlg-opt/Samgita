# Native one-shot fuzzy-search values

Two functional cases qualify selected one-shot request/result fields on the
immutable `rust-v0.163.0` [pin](design.md), source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The stock native process performs actual local file search. The model journal
stays empty; no fabricated protocol peer, imported history or platform runs.

## Independent native oracles

The first case reproduces the
[original upstream ranking fixture](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/fuzzy_file_search.rs#L219).
Query `abe` over the prescribed five-file tree must return the complete ordered
maps: `abexy` score **84**, indices **[0,1,2]**; `sub/abce` score **72**, indices
**[4,5,7]**; `abcde` score **71**, indices **[0,1,4]**. Expected fields are literals
with the independently supplied root; no response supplies its own oracle.

Four exact request maps distinguish cancellation token omitted, explicit null,
string and sequential reuse of that same string. Each returns the full ranked
wrapper. Blank query, empty roots and a nonmatching query each return exactly
`{files:[]}`. Sequential reuse is not an in-flight cancellation test and does not
establish a cancellation fence, operation deduplication or latest-request-wins.

The second case creates `λ_unicode.txt` in two roots and a real
`unicode_directory` in the first. Three independent root vectors must yield
exactly **3/2/1** results with prescribed root/path/file-or-directory triples.
Complete key sets, basenames, positive scores and exact character indices
**[2,3,4,5,6,7,8]** / **[0,1,2,3,4,5,6]** are checked, including reconstruction
of `unicode` through Unicode codepoints. No unsupported root tie-break ordering
or invented Unicode score is prescribed.

Ten one-shot calls have bounded unchanged-byte capture, exact request IDs,
method/parameter maps and matching response IDs. Input trees and configuration
remain unchanged, no thread is loaded, readiness/uncertainty/gap checks hold,
and checked owned shutdown confirms the stock process disappears. The retained
mixed fuzzy-search file and its other profiles remain intact and unrun.

The [processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/search.rs#L40)
uses a fresh flag for omitted/null tokens and conditionally removes supplied
token entries after completion. The
[native runner](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/fuzzy_file_search.rs#L21)
computes indices and sorts by descending score then relative path. The schema
permits `indices:null`; this public app-server path sets `compute_indices:true`.
These successes qualify the array form only. A real null-producing path and
its behavior remain unverified; none is invented or replaced with a mock.
Six upstream files, including the original test, match archive bytes in
`/tmp/samgita-v180-fuzzy-query-map/source-evidence.json`. The implementation and
source review are retained in `/tmp/samgita-v181-fuzzy-query-implementation/`
and `/tmp/samgita-v184-fuzzy-query-final-review/`.

## Observed setup failure and repair

The first v182 block at seed 501432 reports **22 tests / 2 failures**. Both new
search cases finish their search/file/state assertions, then fail at the final
`server/diagnostics` call with `experimental_api_required`. The new launcher
initialized with empty capabilities. Pinned
[declaration line 506](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L506)
marks diagnostics experimental, matching the working session fixture's opt-in.
The search method itself is stable.

The only repair sets `experimentalApi:true` as a fixed launch prerequisite for
that diagnostic. No rejection/gate scenario is selected, and no search assertion,
diagnostic, deadline or process-exit check is removed. The v182 runner stops
after the failure; its later seed and strict check are unrun there. Failure logs
and the unchanged 233-file source guard remain in
`/tmp/samgita-v182-fuzzy-query-checks/functional/`. Results/source SHA256:
`264d4bfedcdca38cb36e3ae03515f7dbde9e38022d1aec617f9ee8f451641279` /
`af0c7b7676ca800de08660cff26d1a0c30dd802af9ac1fb0a6f84f218ef781c3`.

## Final checks and exact owners

After the one-line setup correction, the focused new file passes **2/0**.
The complete ten-file block is the nine files in
[session qualification](fuzzy-search-session-qualification.md#exact-owners-and-final-checks)
plus `test/native_fuzzy_query_values_test.exs`. Both runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **22/0**, in
**40.716/39.936** command seconds. Format, warning-free compile, root strict
Credo and the **233-file** unchanged-source guard pass. Exact final commands,
logs and source: `/tmp/samgita-v186-fuzzy-query-checks/functional/`.
Results/source SHA256:
`8db92e2522ca2d910831ad61ea558c8e7e64e431817225d2fd322cfa80a6b91c` /
`38d59cfa5f4f922535f08521c7271cb38eb4c9bcec53b0473bfc7f783c03893e`.
The adjacent `manifest-binding.json` retains original/current records, the
initial failure and final test hash
`0ca4278311acfde51e7efda381029799f3000010894934f4bb529993a2fe37fa`.

Only **1794–1805**, twelve direct one-shot parameter/result owners, become
implemented. They cover token/query/roots; both match-type literals; the six
result fields and files wrapper. The nullable indices owner explicitly retains
its unqualified native-null limitation. Shared aliases, notifications, complete
branches, concurrent cancellation and other requirements do not inherit evidence.
Schema IDs/hashes and all requirement rows stay unchanged. Contracts become
**4,611 implemented / 1,951 missing / 59 blocked**; requirements stay
**462 implemented / 12 missing / 11 blocked**, zero verified in both.

The [v178 outside consumer](fuzzy-search-session-qualification.md#exact-owners-and-final-checks)
passed **1/0**; reusable runtime libraries, configuration and dependency sources
are unchanged by this test/document-only unit. It is not rerun or counted as
new evidence. Other transports, platforms/backends, real external services,
security/permission tests, A11, broad/hosted checks and full compatibility remain
incomplete. No tag, publication, production migration or deployment occurs.
