# Loaded search environment fields

This unit adds three assertions to the existing real-native search GitInfo
case. Its scope is exactly physical fields **6170/6171**, ThreadSearchResponse's
ThreadEnvironment.cwd and environmentId. The immutable target is Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

Two loaded native threads each complete a prescribed ordinary turn through the
assistant-only Responses fixture. Four actual content searches correlate every
returned thread with those known IDs, text, paths and independently updated
Git metadata. Every returned environment must be a nonempty singleton whose
cwd equals the independently owned fixture workspace and whose environmentId
is the literal local. Neither value is copied from an earlier response.
The real provider fixture supplies model text, not search or environment frames.

The pinned
[search handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L2802)
searches the store and enriches loaded hits from their actual configuration
snapshots. The
[live enrichment](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_enrichment.rs#L43)
uses the
[selected environment projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L620).
Five complete production files match the immutable archive, the experimental
export matches pinned provenance and both separate property-node digests match
inventory. Source and implementation evidence are in
`/tmp/samgita-v250-next-functional-candidate/` and
`/tmp/samgita-v251-search-environment-implementation/`.

The owning file changes only by the three assertions. Existing request/response
correlation, metadata mutation effects, full item/history/provider-journal
retention, configuration bytes, empty workspace, bounds/deadlines and checked
owned cleanup remain. There are no additional native requests, turns, fixtures,
runtime libraries or shared-helper changes. The retained mixed projection test
is source corroboration only; it is not loaded or represented as newly passed.

The focused permitted case passes **1/0**, seed 501432, in **1.8** test seconds;
log `/tmp/samgita-v251-search-environment-first.log`. The final block uses the
same twenty-five reviewed files as
[config qualification](thread-start-config-values-qualification.md#qualification-boundary),
including this strengthened existing search case. All **40 tests pass at both
seeds 501432 and 987654**, with warnings treated as errors, in **73.906/74.020**
command seconds. Scoped format, warning-free compile, strict Credo on **477
files**, outside-umbrella actual-binary consumer **1/0**, three Python AST checks
and the **251-file** unchanged-source guard pass. All eight commands complete;
there are no failures, changed deadlines or weakened gates in this unit.

Exact commands/logs/source: `/tmp/samgita-v254-functional-checks/functional/`.
Results/source SHA256:
`d776b3f6260f7f26d0815b51e51bc99843231e63e560aef9715f6e873b7fb54c` /
`2a968875eda5225c637580d12b1fde17ee93e2ab7126258183df95d692f479fe`.
The adjacent `manifest-binding-environment.json` binds the original/current two
rows to test SHA256
`e2b836d8c98449272f9e53334eb3fa8d00c627da44eb7e7043c3b4830c190372`.
Only **6170/6171** receive scoped implemented evidence. Inventory `--check`
passes; all 485 requirement records and schema identities/hashes are preserved.
Contracts become **4,709 implemented / 1,853 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both.

Only these two direct loaded-local child fields may gain evidence. No parent
environments array, runtimeWorkspaceRoots, same-shaped field in another schema,
whole response/method, unloaded/remote/multiple-environment case or other OS/
transport/backend is qualified. Security/permission tests, related audits and
broad/hosted workflows remain unrun. Full compatibility, A11, source-unreachable
legacy emitters, external/platform acceptance and release remain incomplete.
No publication, production migration or deployment occurs.
