# Native filesystem and process values

Three functional scenarios qualify 23 exact owners on immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official process performs actual local filesystem and child-process
operations. No model turn, Samgita database, external provider or remote service
is used. Owned fixture journals remain empty and configuration unchanged.

## Actual filesystem and child effects

The filesystem case captures **25** exact native requests and matching response
IDs. Two owned Unicode directories contain distinct prescribed binary subject
and control files. Native reads/copy/list/metadata operations must agree with
independent host bytes, names and existence checks. A real watch returns the
exact requested directory; writing a new file produces an actual matching
watch-ID/path notification. Explicit unwatch and removal of owned files and
directories restore the empty workspace. Source/control remain intact until
their explicit removal. No quiet-window, duplicate-watch or post-unwatch fence
is inferred. Capture stays within 32 frames/4096 bytes and event collection
within 256 events/5 seconds, without sleeps or increased deadlines.

Two process cases capture **12** exact native requests across four owned Python
children. Each child reports its independently prescribed cwd. Two live PTYs
observe 24 rows/80 columns, one from an explicit size object and one from null.
Resizing only the selected handle to 40/120 changes its child-observed size;
the other live PTY still reports 24/80. The selected PTY exits 7 with prescribed
non-UTF8 stdout/stderr bytes merged onto the actual PTY stdout stream. Killing
the null-size PTY requires its real terminal event and child disappearance;
a different pipe remains usable afterward.

The pipe receives two binary writes, including final bytes together with
closeStdin:true. Its actual ACK contains exactly the concatenated accepted bytes,
with a distinct binary stderr EOF marker and exit 0. Another pipe closes with
explicit deltaBase64:null and reports empty input. Stream bytes are concatenated
by owning handle/stream without assuming chunk boundaries. Ordinary 5-second
I/O deadlines, 256-event/65,536-byte and 32-frame/4096-byte capture bounds remain.
Exactly one terminal event, actual delta timestamps and normal owned-child/native
process disappearance are checked. No pending request, uncertainty or gap remains.

Only pre-recorded owned handles and PID/start-time/script records participate in
failure cleanup. The existing Stdio cleanup remains, with a pidfd-bound fallback
for an owned detached PTY and a finite child failsafe. Linux/Python pidfd support
is an explicit fixture prerequisite. These cases do not qualify arbitrary child
trees or failure injection during live I/O; the failsafe cannot satisfy expected
normal exits. No borrowed service process is terminated.

## Initial failures and source-backed oracle repairs

The first integrated v210 block failed **31/3** at seed 501432. All process I/O
observations had passed, but both cases expected an incomplete empty loaded-list
response. The pinned producer returns data:[] and nextCursor:null. The repair
adds the required null cursor to the exact whole-map equality; it does not relax
the comparison. The first focused attempt then stopped at formatting before
native tests; formatting only was applied. The formatted focused rerun passes
**2/0** in 2.921 command seconds. Evidence remains in
`/tmp/samgita-v215-process-repair/{focused,focused-formatted}/`.

The filesystem case failed because its initial oracle equated GNU birthtime
with the native metadata API. A metadata-only syscall trace reproduces **1/1
failure** in 1.674 seconds: the native path uses lstat while GNU stat uses
statx(BTIME) on the same owned file. This is a false cross-producer test
assumption, not a Codex filesystem failure. The pinned native default route
reaches std::fs::Metadata.created(), then maps Unsupported to 0.

The binary identifies rustc 1.95.0, commit
`59807616e1fa2540724bfbac14d7976d7e4a3860`. Its immutable
[cfg_has_statx](https://github.com/rust-lang/rust/blob/59807616e1fa2540724bfbac14d7976d7e4a3860/library/std/src/sys/fs/unix.rs#L105)
requires Linux/gnu. The
[created implementation](https://github.com/rust-lang/rust/blob/59807616e1fa2540724bfbac14d7976d7e4a3860/library/std/src/sys/fs/unix.rs#L697)
therefore unconditionally returns Unsupported on this Linux/musl target. This
matches the actual trace and native zero. The corrected differential fixture
requires positive birthtime from GNU stat as an explicit host prerequisite and
requires native createdAtMs **exactly 0**. It accepts no arbitrary zero-or-time
alternative, skips nothing and changes no other filesystem assertion or bound.
The corrected focused filesystem run passes **1/0** in 2.068 command seconds.

Only owner 4016's unavailable native profile is qualified. Positive native
birthtime and other target/library/filesystem profiles remain unqualified.
Rust source SHA256 is
`77c6419ee048c348d9ed4bef226ce6ceb735d6077d0eb9f6bcac0ef46fa7b86d`.
Full compiler/source/route/trace evidence and original failures are retained in
`/tmp/samgita-v214-fs-creation-diagnosis/`. No Codex shim or upstream behavior
change is introduced. Final review `/tmp/samgita-v217-native-io-repair-review/`
supersedes the initial filesystem review's missed producer distinction.

## Exact owners and final checks

Only filesystem owners **4007/4010/4012/4015/4016/4022/4028/4032/4036/4039/4042**
and process owners **4911/4916–4919/4921/4924/4929–4930/4935–4937** become
implemented. These are the ten direct filesystem path references and creation
time field, plus the twelve direct process handle/stream/cwd/size/stdin fields
and alternatives. Their original/current records are bound individually; no
aliases, whole schemas, permission branches or unrelated fields inherit evidence.
Schema identities/hashes and all requirement rows remain unchanged. Contracts
become **4,660 implemented / 1,902 missing / 59 blocked**; requirements stay
**462 implemented / 12 missing / 11 blocked**, zero verified in both inventories.

The final seventeen-file block is the fifteen files in
[search qualification](search-git-info-values-qualification.md#exact-owners-and-final-checks)
plus `test/native_fs_path_values_test.exs` and
`test/native_process_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **31/0**, in
**53.801/53.813** command seconds. Format, warnings-as-errors compile, root strict
Credo and the **240-file** unchanged-source guard pass. The original failed
v210/trace/format blocks remain failures; only final v216 is the passing block.

Exact final commands/logs/source: `/tmp/samgita-v216-native-io-checks/functional/`.
Results/source SHA256:
`f844571791a4114ae156ccdbd3fdad4636f978f09214e25d0832c34752046d60` /
`dc5e95e3fbe286d32f24d1e80c58adaee98c6c8157cb4eb75ba6f131e7162eb5`.
The adjacent `manifest-binding.json` retains all 23 original/current rows and
final filesystem/process test SHA256:
`e4563be465b378dae2f0d4acbd49374476b84b240e59b49ddd85c6e9ec8b53a9` /
`1bcaa24647515b6e62bd3a4121879d7ff8a6971117362279a2a28fa3efb4a54a`.
Initial source mappings, implementation and reviews remain in v204/v207–v209/
v211–v212 artifacts. Runtime libraries/dependencies are unchanged; earlier
outside-consumer evidence is retained rather than counted as a new run.

Omitted stdin payloads, reconnect/concurrent ownership, general terminal/child
portability, remote backends, other transports and filesystem profiles remain
unqualified. Security/permission checks and related broad/hosted workflows remain
unrun under the user's restriction. Full compatibility, A11 and release remain
incomplete; no publication, production migration or deployment occurs. Continue
the source-backed external connector detection/persisted-candidate projection
with owned foreign-source fixtures; distinguish that API behavior from actual
history import.
