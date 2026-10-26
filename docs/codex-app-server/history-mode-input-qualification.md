# Native history-mode input repair

`thread/start` now accepts the pinned native decoder's four history-mode objects:
`{"legacy":null}`, `{"legacy":{}}`, `{"paginated":null}` and
`{"paginated":{}}`. The original caller values reach Codex unchanged; native
creation snapshots and stored histories retain the selected canonical strings.
Base: `0ad376d10478547fb8cb80a0b7d4f425d900644f`.

## Reproduction and cause

The new protocol regression first reports **5 cases /3 failures**; the new
default-validation native case reports **1/1**, rejected locally before the first
object reaches Codex. Logs: `/tmp/samgita-v360-{protocol-red,native-red}.log`.

A separate temporary comparison changes exactly the request helper's validation
to `:wire` and its unchanged fixture path to an absolute path. The actual pinned
native then passes **1/0**, 2.0s, including all four inputs, four ordinary turns
and cold reads. Source binding checks both exact differences. This diagnostic
does not replace the retained default-validation regression; no bypass enters
the committed test or production behavior.

The official JSON describes `ThreadHistoryMode` as a string enum. The real
`ClientRequest` internally tagged input path buffers nested params through
lock-pinned serde 1.0.228. Its enum decoder accepts one known map key, and its
unit decoder accepts null or an empty map. The lowercase Legacy/Paginated
declaration therefore accepts these four additional input forms. Only
thread/start reaches that definition in the actual full request graph.

`thread_data.rs:75–100` declares/converts the enum; `common.rs:225–289` supplies
the buffered request path. `thread_processor.rs:1160–1187,1248–1264,1476–1522`
passes the selected mode through to a genuine native session. Present legacy
cannot be replaced by the store's default paginated mode. The snapshot, real
first-message persistence and public page readers expose the selected contract.

## Scoped correction

A seventh locally derived descriptor wraps the complete original definition
with two disjoint single-key object branches on thread/start only. Each requires
its known key, rejects additional keys, and permits only null or an empty map.
Canonical strings, outer null/omission, ordinary enclosing constraints and the
experimental field gate remain intact. The existing dynamic-tool, compaction,
ModeKind, MultiAgent, summary and Personality corrections retain their bytes.
Responses and notifications keep their canonical output contracts.

The package includes the complete archive-verbatim `source/thread_data.rs` and
an explicit inventory-generation copy before input derivation. The generator
checks exact enum/field/buffered-request declarations, complete source hashes,
canonical schemas and the singleton request graph. Provenance adds exactly two
entries: the source file and generated descriptor. All previous pinned artifacts
and **770 official JSON exports** remain unchanged.

Target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Eleven complete source files byte-match archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The existing serde source/license/origin and native lock are bound again; no new
crate-download verification is claimed.

## Actual native evidence

Five structural cases assert original literal bytes, all four forms, retained
canonical/null/omission behavior, malformed objects, field negotiation,
enclosing constraints and composition. The original full export still rejects
the object forms. After correction these cases pass **5/0**.

The dedicated default-validation native case passes **1/0**, 2.6s. Four original
object starts precede every inference. Actual sent frames and response RPC IDs
are checked; genuine creation notices independently assert the prescribed mode,
model, cwd and native identity/path, with full-root validation and codec checks.
The provider journal stays empty through creation.

Exactly four explicitly initiated assistant turns then produce fixed answers.
Each real provider request contains its original marker, native thread/turn IDs
and prescribed instructions. Public metadata and full native turn pages contain
the expected canonical mode and exact user/assistant history. A checked distinct
owned process starts unloaded and reads all four original IDs/histories without
loading or reinferring. No cold resume or replay is requested.

The unchanged 32-frame/4KiB/128KiB capture, 256-event/1MiB/32-method collection
and finite deadlines remain asserted. Config/catalog/provider bytes, empty
workspace, no retry, and existing owned PID/Port completion barriers are retained.
No fake app-server response, native ID or history record is constructed.

## Final permitted checks and limits

All eleven final commands pass at seeds `501432` and `987654`:

| Check | Final result |
| --- | --- |
| Ten reviewed protocol modules | **47/0 twice**, no exclusions |
| Twenty reviewed ordinary driver modules | **122/0 twice**, 171.297/171.081s |
| Driver composition per seed | 93 actual-binary cases and 29 scripted fault cases |
| Outside-umbrella native consumer | **1/0**, including local validation of the four forms |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **522** sources |
| Python AST/inventory | Eight files parse; inventory passes |
| Executable source guard | **342** stable files; all **333** other prior sources unchanged |

The consumer retains its native list-only journey; its new local validation does
not qualify native history-mode execution independently. Final arrays/logs are
in `/tmp/samgita-v360-functional-checks/final/`; runner and binding are
`/tmp/samgita-v360-{run,source,bind}.py`. Independent final source/test review:
SHA256 `66eb1e5bd385c24860b94628524a80b1d75708b2247fe890b2646831b71a736b`.

| Artifact | SHA256 |
| --- | --- |
| Source evidence | `4f2857adacca9dfb87380e044e4fd007199d12eed3f6b795f702a89c1e8c3afe` |
| Final results.json | `99e9f3aa8e97395723cd30a6ae537d2971be73e37c167cfe39c55f41d3fa365e` |
| Final source.json | `e4e91f2cbe578654c13149e3ae4d86ede54bd21073b1e9bb64fa3fe5ebe5af24` |

No requirement state or physical owner is promoted. Counts remain **5,033
implemented /1,522 missing /66 blocked** contracts and **462 implemented /12
missing /11 blocked** requirements, **zero verified**. Canonical owners618/619
already have their own evidence; no new exported object owner is invented.
Strict completeness still exits **1**. Outer-null native defaulting, native
malformed-input errors, all history lifecycles, other OS/transports/providers and
complete compatibility do not follow from this scoped repair.

Rollback removes the input correction, descriptor/source/provenance additions
and generator copy together. Existing native histories remain canonical and are
never rewritten, deleted or redispatched. No platform database migration occurs.
Prohibited security/credential/authentication/authorization/permission/approval
tests, audits, mixed broad suites and hosted gates remain unrun/incomplete. A11,
producerless legacy and external/OS/platform/final aggregate gates remain open.
No tag, publication, deployment or live-credential change occurs.
