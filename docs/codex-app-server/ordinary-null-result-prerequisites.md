# Nullable results without a pinned native producer

Three exact output owners remain **missing**. This source investigation supplies
the upstream constructor evidence required before proposing more ordinary native
fixtures. It creates no runtime success, mock acceptance, transport coverage,
state promotion or exception to the full goal.

Target: official Codex `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The combined and separately declared standalone executable pins stay unchanged.
No security, authentication, authorization, approval, sandbox or permission test,
audit, broad suite or hosted workflow is run.

| Owner | Physical schema and pointer | State |
| --- | --- | --- |
| 3264 | `supplemental/v1/ConversationSummary.json#/properties/timestamp/anyOf/1` | missing |
| 3267 | `supplemental/v1/ConversationSummary.json#/properties/updatedAt/anyOf/1` | missing |
| 6028 | `v2/ThreadResumeResponse.json#/properties/collaborationMode/anyOf/1` | missing |

Each pointer independently resolves to `{"type":"null"}`, canonical SHA256
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
Equal node hashes do not transfer one owner's evidence to another.

## Legacy summary timestamps

The [real legacy dispatcher](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/message_processor.rs#L1543)
calls the production summary handler. Both
[conversationId and rolloutPath selectors](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L5720)
load a StoredThread and converge on the same production converter. That
[converter](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6450)
unconditionally wraps both formatted timestamps in Some.
[StoredThread](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/types.rs#L612)
stores concrete DateTime values rather than optional timestamps. Failed reads
return errors, not successful null summaries.

The tempting rollout helper that turns an empty SessionMeta timestamp into None
is explicitly [cfg(test)](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_summary.rs#L8).
Its related extraction/update helpers and the alternate state-metadata summary
converter are test-only too. They are not the shipped handler path. A malformed
rollout, direct store edit, fabricated empty timestamp, test-only converter or
scripted app-server response cannot establish native null-output acceptance.
Changing source selector, warm/cold state, included history or successful store
implementation does not make this production converter choose None.

The supplemental JSON is explicitly **locally derived, not an official JSON
export**. Pinned Rust v1 Option<String> and generated TypeScript string|null
establish representable protocol shapes. They do not select None in production.
Its complete root SHA256 is
`2ba2ae3981c856fc67be1fad93a6d7d38ef453db28aad663ceeab3dd10512a1e`.
The existing [ordinary summary evidence](ordinary-summary-git-qualification.md)
remains nonnull-only; no passing previous scenario is relabeled.

The source report `/tmp/samgita-legacy-summary-null-prerequisites-20261029.md`,
SHA256 `41359542cdc5b0d391c4e7db9fedd081954f35bbc08ece8a27c7a8b5c4ca920d`,
records the exact supplement provenance/node hashes and five complete source
archive matches. It proposes no actionable genuine null fixture.

## Resume collaborationMode

The complete pinned app-server production symbol census finds an import and
exactly two ThreadResumeResponse constructors. The
[cold/history/path constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L4402)
always wraps the concrete snapshot collaboration mode in Some. The
[loaded/rejoined listener constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_lifecycle.rs#L915)
does the same. Paging and included turns do not condition that Option. A fork
has a separate response type; a later resume uses these same two success routes.
Internal daemon recovery does not create another public client success.

The snapshot field is a concrete CollaborationMode. The
[nullable DTO](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/thread.rs#L466)
documents compatibility with an older server; ordinary serialization and the
outgoing sender preserve the supplied value. Protocol/TUI test constructors
containing None are not native producers. Invalid/missing rollouts, errors and
disconnects do not produce a successful explicit-null result. The existing
[nonnull Plan/Default qualification](native-context-settings-qualification.md)
keeps its exact scope.

Stable/experimental resume root SHA256 values are respectively
`3f19a9c3a9891526685b0f61ce781098ddd65bfa2aed8c24ba4722fef10e08fe` and
`3ea7c6d06bab091cea98431c72b644ac026492217842335fcc2105a472be4aa2`.
The complete symbol census, route mapping, node comparisons and eight causal
source archive matches are recorded in
`/tmp/samgita-resume-null-collaboration-20261029-report.md`, SHA256
`f64cdac1fb5f4d8276532c43ceb3ee652f2fab03685bf412fe7bcb1c34c0ee84`.

## Source integrity and remaining prerequisite

Selected complete causal source hashes, each matching the official archive:

| Source under codex-rs/ | SHA256 |
| --- | --- |
| `app-server/src/request_processors/thread_processor.rs` | `f98fdad7df37ad720e63b75488ffab99ae88f7de4578b280ab957a09f0a98153` |
| `app-server/src/request_processors/thread_summary.rs` | `97b66809247f5aa202e018717413c66814c03766325f9e566844542bbb009199` |
| `thread-store/src/types.rs` | `9ccaf27fdaeeb70cfdb374a3da8305a6cb573471636db07954d6deb17a3a0ca2` |
| `app-server-protocol/src/protocol/v1.rs` | `e0642bd1bc7dbe5e24d508420471d705d5688efe8df3a8b40e3af22be55d7754` |
| `app-server/src/request_processors/thread_lifecycle.rs` | `9878fc3f652ad2d916891de8c4c377c8290510e19a178b1951e1c520d77270eb` |
| `app-server-protocol/src/protocol/v2/thread.rs` | `8c10510bb88990aa0f0105e7a85c0bb7859db7232be29f84a6c66693600ef502` |
| `core/src/codex_thread.rs` | `de8c0c62510c6c5144bf48ec40039a75b5f05d0eb4d515afcc436caece2795ac` |

These are constructor boundaries for the complete inspected stock request paths
at the immutable pin, not claims about every external implementation or future
release. Representable nullable types remain supported by the decoder. Native
output acceptance requires a separately evidenced producer/version that emits
the null branch, or an explicit target/evidence-contract decision. No such
decision, waiver, producer modification, historical-data injection or mock
substitution is made. Repeating existing positive fixtures cannot change the
Some constructors. All three owners and the full goal stay incomplete.

This source-only unit changes evidence/limitations metadata and documentation;
it changes no behavior, test, schema, pin, state, coverage or test reference.

## Metadata-only qualification

The preceding functional source at
`a44799d1a315ef3f3a753fb0066e3cd5f801072b` passes all 17 reviewed steps:
main165/0 twice, extensions15/0 twice, three replay seeds, cleanup4/0, outside
consumer1/0 and static/build checks. Its exact
[notification qualification](standalone-source-notification-qualification.md#final-combined-source-functional-qualification)
is retained; this unit claims no fresh runtime run or nullable success.

The binder verifies that only owners3264/3267/6028 change, and only their
evidence/limitations lists gain one entry each. All requirement records, states,
node identities/hashes, tests, coverage and other manifest content stay exact.
All **1,761 other guarded hashes** match the preceding 17-step source; the
runner changes only its expected fingerprint literal, normalized by the existing
guard. Application code, tests, schemas, configuration and locks are byte-identical.
It rechecks eleven distinct complete causal source files against the immutable
archive and independently binds all three null nodes. Inventory consistency
passes, exit0; the 1,762-source snapshot stays unchanged during it.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-null-result-source-binding-20261029.py
```

Evidence `/tmp/samgita-null-result-source-binding-20261029/binding.json`, SHA256
`45139d1e4d84c9420b612f4539e57f736e86389d3c6fc193382461df3c5ba5b0`;
inventory log SHA256
`9b6361cfd6b98741c08a5dcfbf594ab664cb213ad0995f704848f849933ab7ce`.
Final reviewed fingerprint:
`8a8f460c176ed0546cfdc63f4955144f1fa55bc78f27f3330253b965a4d4ee57`.
The first binder compared dictionary insertion order with sorted-JSON key order
and stopped before inventory. Complete key sets/source hashes matched; using
key-set equality fixes the representation assertion without omitting any hash
check. The diagnostic remains at
`/tmp/samgita-null-result-source-binding-20261029-initial.txt`.

Totals stay **462 implemented /12 missing /11 blocked requirements** and
**5,748 implemented /737 missing /136 blocked contracts**, zero globally verified.
No additional runtime check, prohibited test, audit or hosted workflow is run.
The preceding assembly remains evidence for unchanged production inputs; no new
build, artifact startup, package publication, release or deployment is claimed.
Rollback removes only these three source evidence/limitations additions,
documentation and the corresponding runner fingerprint update.
