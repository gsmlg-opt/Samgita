# Native content-search Git metadata projection

One functional scenario qualifies four exact response owners on immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official process completes two assistant-only turns in distinct persistent
paginated threads against a local synthetic model provider. Real local ripgrep
performs content search; no Git command, remote origin or external provider is
used. Missing ripgrep fails the prerequisite rather than substituting a fake.

## Independent object and content oracles

The two inputs have a common prescribed search marker and distinct text.
Correlated native turn/item completion frames establish exact generated IDs,
prescribed input/output and ordered items. Complete public history independently
matches those items before metadata/search operations. The control receives a
fixed full GitInfo object; each subject expectation is separately prescribed:

| Subject update | Expected object returned by actual search |
| --- | --- |
| Full sha/branch/originUrl literals | Three original nonnull strings |
| sha:null | Null sha; original branch/origin retained |
| branch:null | Null sha/branch; original origin retained |
| New sha and originUrl:null | New sha; null branch/origin |

The parent `gitInfo` remains an object throughout. Each field therefore has an
actual present-null observation as well as a nonnull value, rather than inheriting
evidence from a null parent. Every real search must return exactly both thread
IDs once, the correct distinct content snippets, original preview/path and each
independently prescribed GitInfo object. The control remains unchanged. The
expected search object is never derived from a mutation/read response.

All **5 metadata update + 4 search** requests have exact captured ID/method/params
envelopes and matching native response IDs. After each row, public reads preserve
the original completed history, preview, IDs, real paths/files and corroborate
the prescribed metadata. The two-request provider journal remains byte-identical,
configuration unchanged and workspace empty. A supported but deprecated
paginated complete-history read is an observation, not a general flush barrier.
There is no query-until-green loop, invented index record or restart claim.

The pinned metadata processor delegates durable field updates to the native
store; explicit null clears and omitted-field retention remain distinct. The
[search processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2765)
builds rows from stored threads, mapping commit hash/branch/repository URL to the
GitInfo fields at lines 6379–6383. Four inspected files match pinned archive bytes.
Source selection and implementation evidence are in
`/tmp/samgita-v200-functional-candidate-review/` and
`/tmp/samgita-v203-search-gitinfo-implementation/`. Earlier search tests prescribed
gitInfo:null; they do not supply this nonnull/child-null response evidence.

Capture stays bounded at 16 frames/4096 bytes; turn collection at 256 events and
20 seconds. Fixed experimental opt-in supports search/diagnostics. Executable
hashes, confirmed owned-process disappearance and retained failure cleanup
preserve prior lifecycle repairs. No pending request, uncertain operation or gap
remains after each matrix row. Independent review
`/tmp/samgita-v206-search-gitinfo-review/REVIEW.md` found no actionable findings
and binds the final test hash below.

## Exact owners and final checks

Only **6094–6096/6137** become implemented:
`v2/ThreadSearchResponse.json#/definitions/GitInfo/properties/{branch,originUrl,sha}`
and its `Thread.gitInfo/anyOf/0` nonnull object reference. No setter/read aliases,
parent-null branch, search envelope or unrelated fields inherit evidence. Schema
identities/hashes and requirements remain unchanged. Contracts become **4,637
implemented / 1,925 missing / 59 blocked**; requirements stay **462 implemented /
12 missing / 11 blocked**. Both inventories retain **zero verified** entries.

The final fifteen-file block is the fourteen files in
[turn-list qualification](turn-list-null-values-qualification.md#exact-owners-and-final-evidence)
plus `test/native_search_git_info_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **28/0**, in
**48.766/50.563** command seconds. Format, warnings-as-errors compile, root strict
Credo and the **238-file** unchanged-source guard pass. No runtime failure or
deadline/assertion weakening occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v205-search-gitinfo-checks/functional/`.
Results/source SHA256:
`85495d74ca6281ececf578607baf2f2cbd529cb70ba56068ab341f2d85af385f` /
`bcd4ec28d409dc66336238d891a91d5f7b4d31eef4715cfe733bf519bb33af1f`.
The adjacent `manifest-binding.json` retains original/current four rows and
final test SHA256
`7e920ac07056168c6470ab5f736cf29582ee929290d6fc930ca074041e262ee0`.
Runtime libraries/dependencies remain unchanged; earlier outside-consumer
evidence is retained rather than counted as new.

This proves registered metadata projection, not repository discovery, real Git
state or remote synchronization. Parent-null/all-null behavior, restart and
other transports/backends/platforms remain unqualified. Security/permission
checks and related broad/hosted workflows remain unrun under the user's
restriction. Full compatibility, A11 and release remain incomplete; no
publication or deployment occurs. Continue source-backed native local process
and filesystem value/lifecycle scenarios with independent child/file oracles.
