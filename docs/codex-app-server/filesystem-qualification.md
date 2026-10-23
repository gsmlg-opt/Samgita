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
