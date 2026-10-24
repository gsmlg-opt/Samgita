# Native filesystem lifecycle

Six cases in `apps/samgita_codex_driver/test/filesystem_lifecycle_test.exs`
use the actual immutable Codex `rust-v0.163.0` app-server over stdio and owned
temporary paths. The source and binary hashes are in
[qualification](qualification.md). Every case requires zero model requests.
Codex handles filesystem operations and watch notifications directly.

| Profile | Required result |
| --- | --- |
| Watch identity and release | Duplicate watch IDs fail without replacing the original subscription. Unwatch returns a barrier; a separate live control watch demonstrates delivery while the old watch remains quiet. Explicit reuse of the released ID works. |
| Atomic replacement | A watch on a missing target observes both creation and repeated atomic replacement. Closing the owned process and opening a fresh connection permits the same explicit watch ID. |
| Bytes and metadata | Binary/empty writes truncate exactly; invalid base64 fails without corruption. File/directory/symlink metadata retains the native shape. |
| Presence and protection | Omitted/null recursive/force defaults and explicit false protections have distinct, asserted effects for directory creation/removal. |
| Copy and symlinks | Nonrecursive directory copy fails; recursive copy preserves source and relative symlink behavior. Removing a copied link preserves target data. |
| Absolute paths and correlation | Every relative path position, including both copy arguments, reaches the actual upstream validation boundary. Exact native errors retain alternating integer/string request IDs, leave data unchanged and settle pending calls. |

Notifications require exact watch IDs/changed paths, the official envelope key
set and a positive `emittedAtMs`. The initial run failed two assertions because
the fixture omitted this upstream timestamp; adding its explicit validation
retained the original identity/path requirements. No timeout increase, readiness
sleep, skipped assertion or retry-until-green was introduced.

Pinned source references, relative to `codex-rs/`:

- `app-server-protocol/src/protocol/v2/fs.rs:11-205`: native contracts/defaults.
- `app-server/src/fs_watch.rs:27,76,146,166`: debounce, ownership, duplicate IDs,
  unwatch barrier and connection cleanup.
- `app-server/src/request_processors/fs_processor.rs:64-220`: bytes, defaults
  and errors; `app-server/src/outgoing_message.rs:907`: emitted timestamp.
- `exec-server/src/local_file_system.rs:678,865,906`: symlinks, remove/copy guards.
- `app-server/tests/suite/v2/fs.rs:401,525,580,684-846`: upstream profiles.

The six corrected cases passed seed `501432`. With the three plugin cases,
**9 tests passed** at each seed `513498` and `987654`. Driver warnings-as-errors
compile and scoped format passed. The integrated 22-case run and strict Credo
also passed, seed `501432`. Logs:
`/tmp/samgita-fs-lifecycle-{initial,repair-1,regressions}.log` and
`/tmp/samgita-operation-profiles-static-check.log`.

The nine filesystem methods' request/response entries and `fs/changed` are
implemented with this selected Linux/stdio evidence. Field contracts remain
incomplete. Sequential close/restart does not establish simultaneous ownership
across multiple clients of one persistent server; other transport/OS/backend
profiles remain unqualified. Native filesystem access does not grant Samgita
Project authorization or Task acceptance. Final aggregate/hosted evidence is
separate from these local scenarios.

## Physical-field evidence

The later source-reviewed indexing adds **25 exact physical fields** from these
unchanged tests: 11 response/notification fields and 14 request parameters.
The manifest records precise input/assertion ranges and limits for each owner;
no whole method, schema alias, nullable branch or verified promotion follows.

| Exact owners | Independent data and effects |
| --- | --- |
| FsGetMetadataResponse isDirectory/isFile/isSymlink | Known regular file/directory and independently created symlinks produce four prescribed type combinations |
| FsReadDirectoryResponse entries and nested fileName/isDirectory/isFile | Owned tree and recursive copy produce the exact sorted two-entry directory/symlink result; empty directory is explicit |
| FsReadFileResponse dataBase64 | Prescribed NUL/invalid-UTF8 bytes, truncation and empty content equal physical and native readbacks |
| FsWatchResponse path; FsChangedNotification watchId/changedPaths | Known Unicode/missing paths, explicit subscription IDs and actual writes/atomic replacement correlate to exact notifications |
| FsCopy/CreateDirectory/ReadFile/Remove/Unwatch/Watch/WriteFile params | Prescribed paths, bytes and false/default controls produce observed copy guards, source preservation, creation/removal, selected release and exact readback effects |

Timestamps remain withheld: their retained type/range assertions are not an
independent accuracy oracle. Directory entry booleans cover the selected
directory-resolving entries, not a regular-file entry; sorting claims no native
directory order. Returned watch paths qualify only the selected absolute paths,
not arbitrary normalization. Sequential restart does not prove simultaneous
persistent-server clients or other transports/OSes.

The test-file SHA256 remains
`bb63b9a6ab70e47bfaa1190ff038ff5e9d7e6ce8d0bef0c7e398f287a2a1d9e9`.
It does not hash its executable internally; binary identity is supplied by the
immutable acquisition/workflow and parent validation environment. These retained
tests passed in the exact `e39ca5f` driver run, **611/0**, and current source
hashes match. See [hosted evidence](repair-qualification.md#combined-source-platform-checkpoint-at-e39ca5f).
The indexing itself executed no native test; subsequent final-source evidence
must include these tests. No Task acceptance, A11 or complete compatibility
claim is made.

## Prescribed timestamps and directory selection

`native_filesystem_projections_test.exs` adds two stock-native cases. Two
ordinary files receive independently prescribed positive whole-second mtimes,
checked with `File.stat!(time: :posix)`. Alternating their requested paths must
return the exact corresponding millisecond values. Changing only one mtime
must change only its native result. This supplies an accuracy/selection oracle
for `modifiedAtMs`; `createdAtMs` remains withheld.

Two selected directories contain disjoint ordinary-file names and a nested
directory. Exact direct-child maps before and after an owned cross-directory
rename prove path selection and ordinary-file flags. Sorting makes no directory
order claim. Contents remain exact; no thread or model request is created.

Pinned producers are `exec-server/src/local_file_system.rs:657-703,1257-1262`
and `app-server/src/request_processors/fs_processor.rs:115-153`, relative to
the immutable source in qualification. The new cases pass in the **17/0**
combined block at seeds `501432` and `987654`; commands/source hashes are in
`/tmp/samgita-native-followup-projections-v3-20261024/`.
Only three new physical owners gain scoped implemented evidence: metadata path,
directory path and modifiedAtMs. Fractional/negative/unavailable creation or
modification timestamps, path aliases, other transports/OSes and full method
verification remain unqualified.
