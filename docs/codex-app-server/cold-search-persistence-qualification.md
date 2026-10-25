# Native cold search without thread loading or execution

This adds one ordinary functional regression to the existing search case on
immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The base repository commit is `ee5eeb7`. Real native processes produce every
protocol frame; owned synthetic providers supply fixed assistant text only.
No Samgita platform, Repo, PostgreSQL, remote repository or paid provider runs.

## Persisted values and no-execution oracles

The warm native process completes two ordinary paginated turns with prescribed
distinct text and a common search marker. Each genuine completed history must
match the original generated turn/item IDs, content, ordering and completed
status. Each thread receives its own independently prescribed nonnull GitInfo
object. Warm search returns exactly those two IDs, snippets, original paths and
metadata, with configured low effort and the selected local environment.

Confirmed owned-process shutdown precedes a new explicitly initialized native
process using the same synthetic home and unchanged configuration. The new
Session is distinct. The complete native loaded-thread list must be empty
before search, after search and after public full-history reads. Actual cold
search must preserve both original IDs, exact snippets, previews, history mode,
paths, GitInfo and literal low effort, while environments is explicitly null
and status is exactly notLoaded. Full histories remain exactly equal to those
recorded after the original turns, and their files still exist.

The whole two-request provider journal remains byte-identical; request count
stays two. Configuration bytes, empty workspace, empty uncertainty, ready
phase, no pending calls and no gap remain checked. Capture still bounds frames
at 16/4096 bytes and requires exactly two metadata updates plus two searches.
Original request correlation, turn/request/init deadlines, event bounds and
owned-process cleanup remain. Both launches use the existing fixed yolo setup,
without permission assertions or an automatic recovery execution.

## Immutable production semantics

The
[search store](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/search_threads.rs#L101)
uses the native state database when available. Stored-row conversion preserves
persisted model/effort rather than treating an unloaded thread as unset. The
[public conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6400)
sets environments to None and status to NotLoaded, but copies stored effort.
Loaded-thread enrichment asks ThreadManager only for an existing entry; the
[lookup](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/thread_manager.rs#L1741)
does not restore a thread or start a turn. Cold search therefore must not infer
reasoningEffort:null from environments:null. No null-effort evidence is claimed.

The first focused run has **2 tests / 1 failure**, seed 501432, 3.717 command
seconds. Every cold content/history/no-execution check passes; the final cleanup
helper incorrectly expects a zero-valued live-thread gauge. Actual output has
no such gauge. The pinned
[registration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/diagnostics/src/lib.rs#L25)
occurs only on first track/increment, and snapshot includes every registered
gauge, including zero values. A new process which never creates a CodexThread
has no registration. The corrected helper requires that exact absence for the
cold process and preserves the exact one-gauge/value-2 oracle for warm processes,
plus native executable/PID/disappearance checks for both. Absence is not counted
as an emitted zero value. A subsequent format-only check fails on two required
blank lines and runs no native case; those lines are corrected without changing
assertions or bounds. Original logs remain in
`/tmp/samgita-v264-cold-search-focused/` and
`/tmp/samgita-v265-cold-search-focused/`.

All eleven inspected complete production files match the immutable source
archive; both exact existing field-node digests and exports match inventory and
provenance. Evidence is in
`/tmp/samgita-v266-functional-checks/source-evidence.json`, SHA256
`6ce23a5af705cbffbae917eb6c84f67cb59841475e20c831a020b8dca909d31b`.
Independent final source review finds no actionable issue. Runtime libraries,
shared helpers, dependencies and application configuration remain unchanged.

## Final checks and limits

The same twenty-five reviewed files as the
[snapshot unit](thread-runtime-projections-qualification.md#checks-on-final-source)
now contain 41 cases. Both explicit-file-list mix test commands with warnings
as errors, seeds 501432 and 987654, pass **41/0**, in **75.806/75.427** command
seconds. Scoped format, warning-free compile, root strict Credo on 477 files,
outside-umbrella actual-binary consumer **1/0**, three Python AST checks and the
**251-file** unchanged-source guard pass. All eight commands complete.

Exact commands/environment/logs/final-source hashes:
`/tmp/samgita-v266-functional-checks/functional/`. Results/source SHA256:
`57c74eab36c48222f11c5344fd8ab517f68f85cff60d3a5b0e9e74d163bbab11` /
`21c9bc5c4adbd3af5b8761df41db130be0fafd77c6e3c6e4319d0c4f14c87c87`.
Final owning test SHA256:
`c358b3ff76304668679d0dc89277becdb9739c7ef6f5a58f07c8cc73ba011385`.
The adjacent manifest-binding.json records original/current rows and their
source/test binding.

Only already-implemented owners **6130** (ThreadSearchResponse environments)
and **6151** (its nonnull reasoningEffort branch) gain supplemental evidence.
There are **no new owner promotions**. Inventory --check passes; contracts stay
**4,715 implemented / 1,847 missing / 59 blocked** and requirements stay
**462 implemented / 12 missing / 11 blocked**, with zero verified in both.
All schema identities and planned tests remain unchanged. Model/null-effort,
same-shaped aliases, enclosing response/method and other field owners gain
no evidence automatically.

The unchanged strict command
`python3 -B scripts/codex/inventory.py --check --require-verified` exits **1**:
unverified requirements remain. This is a failed full-compatibility gate, not a
passing result or an approved scope reduction; it executes no security tests.

This is orderly owned-process restart and read-only persisted search, not
power-loss durability, remote reconnect/replay, ambiguous mutation recovery,
platform Task acceptance or other OS/backend success. The original gauge/format
failures remain evidence. Prohibited security/permission tests, related audits
and broad/hosted workflows remain unrun. Full compatibility, A11, immutable
upstream-unreachable emission, real external/platform acceptance and release
remain incomplete. No publication, production migration or deployment occurs.
