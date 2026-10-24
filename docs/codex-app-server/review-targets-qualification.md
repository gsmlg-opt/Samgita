# Native review targets and complete history

Eight cases qualify selected `review/start` targets against stock
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both fixed seeds pass **8/0** with strict checks. A fixed no-tool model supplies
one assistant message; Codex produces all app-server frames, target normalization,
prompts and history. This proves routing/lifecycle, **not** diff inspection,
actionable findings, review quality or real-provider integration.

The six positive targets are uncommitted changes, divergent local `main`, and a
non-HEAD commit with trimmed Unicode, omitted, null or blank title. The fixture
creates only its private Git graph: root A, main B and feature C, with distinct
staged/unstaged/untracked sentinels and no remotes. Base review must resolve A as
merge-base, distinct from both branch tips. Request targets, immediate native
hints and full core prompts have independent exact expectations. The provider
holds its response until explicit release, so the test also requires pending
review before completion. Blank branch/SHA fail with exact native `-32600`
messages, zero model requests, no review/turn/item traffic and unchanged loaded
thread. Before and after rejection, the history API must return its exact
unmaterialized-thread error.

Exact original parent/marker IDs, root/delegate linkage, item maps and complete
warm/cold history are checked. Semantic Git snapshots compare HEAD, refs, index
entries, files/paths/digests, status, staged and unstaged diffs throughout pending
review and restart. No source tree, index or history is rewritten to obtain a
pass. Native processes use private loopback-only namespaces, offline model data,
fresh environment and the retained ownership/reaping guards. No tools, live
account, real credential, remote Git operation or paid request is involved.

## Retained initial failures and exact native history

The first runner passed compile/format/strict Credo then failed **8/8**:
six parent-only history assumptions and two empty-thread history assumptions.
The latter now require the documented error from immutable
[`thread_processor.rs:6248`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6248).
The second runner passed the rejection cases but failed the six cold-history
status comparisons. Both directories retain their logs:
`/tmp/samgita-native-review-targets-20261024/` and
`/tmp/samgita-native-review-targets-v2-20261024/`.

The initial single-turn assumption was incorrect. Immutable
[`review.rs:136`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/review.rs#L136)
creates a one-shot delegate;
[`codex_delegate.rs:243`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/codex_delegate.rs#L243)
links its turn to the parent. Review forwards delegate start/items while
[`consuming its completion`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tasks/review.rs#L167).
The native history therefore contains **exactly two** turns: the completed
parent with original review markers, then the linked delegate with two prescribed
user prompt items and one assistant item. The warm legacy projection reports
the delegate as `inProgress`, without completion time/duration. After restart,
[`thread_processor.rs:6097`](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6097)
normalizes its stale status to `interrupted`. The test requires that **single
explicit status change and otherwise full list equality**. It never filters out
the delegate, fabricates completion or interprets that projection as fresh work.
No timeout, permissive fallback or original guardian changes.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-native-review-targets-v3-20261024.py
```

Final Python AST, compile, format and root strict Credo (417 files) pass.
Seeds501432/987654 each pass **8/0**, no exclusions, 21.9/22.1s (runner
22.361/22.634s); executable-source guard matches. A required explicit hosted
profile step is added; final combined-source qualification remains pending.

| File | Final SHA256 |
| --- | --- |
| `native_review_targets_profile.exs` | 457874009cd66c46e37f0b77326615f35e39e529a02e47444cb2163a34274769 |
| `isolated_review_targets_fixture.py` | 604a50804e4ecb9e8996a7cb9447e3b120e5ec27eb4acafe6d45eab355d67a8f |

Twelve direct physical owners in `ClientRequest.json#/definitions/ReviewTarget`
gain scoped implemented evidence: branches0/1/2, their respective type properties
and literals, base branch, commit SHA and commit title. Test104–148 asserts
dispatch, independent prompts/markers and history;193–248 prescribes each target;
344–386 checks exact retained parent/delegate content. The pinned owner IDs and
subtree hashes are in the manifest. No equal-hash alias or complete union/method
promotion follows. Uncommitted/commit handling renders prompts; it does not
resolve the supplied SHA or inspect files. Invalid nonblank branch fallback,
other delivery/mode variants, all OS/backend profiles, A11 and full compatibility
remain outside this evidence.

Regenerated totals: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,033 implemented / 3,588 missing**.
No release, publication, production migration or deployment occurs.
