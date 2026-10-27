# Real filesystem and paginated-read deprecation envelopes

Combined V411/V412 starts from `main`
`ab7bfec88ba408bd9aa856994316996df4d485e7`. Scope is full fs/changed root3007
and deprecationNotice roots3063–3066 (whole wrapper, method, literal, params).
The three implemented filesystem siblings stay unchanged. Other legacy or
unavailable producers gain no evidence from this unit.

Pin: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Ordinary owned launches stay fixed YOLO. No permission behavior is tested.

## Actual filesystem effects and unwatch barriers

New `native_fs_notification_envelope_test.exs` starts one owned native stdio
process, no thread, provider, model turn or command execution. Two independently
named Unicode files exist before subscription. Host writes/readbacks supply
prescribed bytes, with original unchanged control content checked first. Actual
native notices must carry the independently prescribed watch ID and absolute
path, complete method/params/emittedAtMs, current generation and pinned schema.
No server emulator or synthetic native event satisfies the predicate.

After the first file notice, the original fs/unwatch response fences that watch.
A later mutation of the retired file plus the live control file must yield a
real control notice. After the second unwatch, both files change again and the
existing500ms quiet observation runs. All captured notices must precede their
own original unwatch response. Original native frames before Session decoding
equal the collected driver sequence after checked shutdown. Multiple exact
notices per write are allowed within fixed finite caps; there is no one-notice-
per-write or arbitrary future silence claim.

Selected notices have pre-write/post-receipt host-clock brackets. Any permitted
additional batch has its watch's pre-write/post-unwatch bracket. No uniqueness
or global monotonic wall-clock assertion is made. Final diagnostics, ready/
pending/interaction/uncertain/gap state, two final host file contents, frozen
configuration and exact workspace contents stay checked. All seven unique RPC
pairs are matched to original final capture, plus initialized; methods are
initialize, diagnostics, two watches, two unwatches and final diagnostics.

Pinned `fs_watch.rs:77–167` is the real debounced producer and unwatch task fence;
`file-watcher/src/lib.rs:385–405,675–705,793–929` bridges actual OS mutations and
maps existing-file paths. Outgoing connection writer completion precedes unwatch
return. `v2/fs.rs:160–204` defines the wire shapes. Backend debounce is200ms.
The official `app-server/tests/suite/v2/fs.rs:708–720` permits optional kernel
notification absence on unreliable environments, and `fs_watch.rs:56–60` can
fall back to a noop watcher. This qualification requires actual notices within
5s; absence fails and leaves acceptance incomplete. It never adopts optional
success or a synthetic sender. The initial focused real-native case passes
**1/0** at501432 in1.9 ExUnit seconds.

## A real ordinary legacy trigger

The retained input-wait case already makes three successful paginated full
history reads: warm initial, warm final, cold restored. Pinned
`thread_processor.rs:819–830,870–887` emits one targeted deprecationNotice for
each such read, before its response; it has no once-per-thread/connection flag.
`message_processor.rs:1518–1519,1897–1902` returns the actual RPC response only
after this awaited send. This provides upstream and native evidence of a real
legacy trigger without another turn, RPC, provider request or process.

Each existing read is bracketed by host epoch-ms/current-session generation and
followed by immediate bounded drain after the actual response. The complete
wrapper has the literal full-history hydration summary and explicit detailsnull.
Params contain no invented thread/turn/request identity. Actual paginated read
results and serialized per-read capture growth associate the notice with its
cause. Read-response bytes are not captured; no raw read-response ordering claim
is made. Same-channel source order and the read-return/drain barrier are the
evidence. Three notices mean this finite three-read profile, not exactly-once
transport delivery or a global count across other operations.

The selected original incoming ledger grows explicitly: initial notice; held
ordinary request; actual resolution; second warm notice; cold read notice.
Each prefix and encoded-byte count is preserved, including the original request/
resolution tuples. Warm shutdown retains four records; cold shutdown retains
all five. The existing selected five outgoing search/reply frames remain exact;
this is a selected capture inventory, not every native RPC. Actual provider
answer/count3, reply digest/outcome, persisted two-turn history, unloaded cold
state, frozen file bytes and checked cleanup remain. Deprecated methods lacking
a reachable producer remain incomplete; this path proves no other legacy cause.

## Bounds, source and final checks

Filesystem capture/events stay128/2MiB, frames64KiB,5sRPC/required notice,
500ms quiet and60s case. The input-wait raw/event/file limits and existing
5sRPC/20s collection/60s case stay unchanged. Checked shutdown requires owner
completion, closed Ports and absent owned PIDs before root removal. No old
cleanup fix, driver runtime, shared helper, protocol core or provider changes.

Ten complete source files and five exact canonical nodes match the immutable
archive in `/tmp/samgita-v411-v412-source/evidence.json`, SHA256
`c33abbae52823ce909f7d0cf8b71ae16d69d75b18531ba603ca115ad800598a0`.
Runner `/tmp/samgita-v411-v412-run.py` retains the established pinned
Elixir1.18.5/OTP27.3.4.17 test environment, two schedulers, no inherited Mix
build/deps/partition overrides and pinned executable. Exact commands/cwd/status/
log hashes and full guarded membership are in
`/tmp/samgita-v411-v412-functional-checks/final/`.

Focused **2/0** passes at501432 in4.625 command seconds. Final **38/0** at
501432/987654 passes in68.828/68.077 command seconds without exclusions.
Six Python syntax checks, scoped format, warning-free driver compile, root
strict Credo and inventory consistency pass. All404 sources stay stable;
402other prior paths remain unchanged, with one existing module strengthened
and one new native watch module. No runtime repair, missing-event bypass or
timeout increase was needed. Prior changed owning-source runs remain historical.

FS/input-wait test SHA256:
`4e0a710f3b778d4624afc3fb70478135118fb7e167147274c53de8388203683c` /
`b7a531e67fd6d78bc99667bdfcb8e01ebaae233ee99c609ddf0fd6b8a5d06a18`.
Results/source guard SHA256:
`95286837d8da24e7b8bb55b4f809a1a2096aa6ce4c61570b22787cc5a03948d7` /
`b850717db2d3e57cac33b5a5e5abc99ef1ddb71b40661030d08bfd32f3626a6d`.
Manifest binder `/tmp/samgita-v411-v412-bind.py` and
`/tmp/samgita-v411-v412-binding/evidence.json` SHA256:
`cad208c5d7defdb57de6c0a079d893e6adfda2207840d62a016b6e88f0de0d9b`.
Independent source review of FS changes found no actionable defect:
`/tmp/samgita-v411-independent-review.md` SHA256
`3166f795c3858bdd678b151a92b0cdc26af4335bd1d2cf9d5b5606ef8aa70eab`.
That review excludes V412; parent reviewed the deprecation patch and ran checks.

Only3007/3063–3066 become scoped implemented: **5,152 implemented /1,403 missing
/66 blocked** contracts. Requirements remain462implemented/12missing/11blocked,
with zero verified in both; strict completeness remains red.

No recursive/symlink/missing/atomic/remote filesystem, other OS/transport,
global upstream backpressure, other deprecation causes/nonnull details, failed
reads, false/omitted controls or multi-client routing is qualified. Security/
permission tests/audits, mixed broad suites and hosted workflows remain unrun.
A11, unavailable producers, real external/platform/full-goal/release gates stay
incomplete. No publication, deployment, production migration or sibling edits.
Rollback removes this new test, additive read assertions and five mappings;
preserve runtime/historical records. Continue reachable ordinary warning paths.
