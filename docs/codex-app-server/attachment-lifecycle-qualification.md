# Native thread attachment lifecycle qualification

This scoped unit targets official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It uses the independently reusable stdio driver and private native SQLite. These
attachments are arbitrary native thread facts; they are distinct from Samgita
artifact references, GitHub authorization and project acceptance.

Status: selected actual-native Linux stdio evidence passed. All broader
transport/backend/lifecycle variants remain incomplete.

## Pinned source

Paths are relative to the pinned upstream `codex-rs/`:

- `app-server-protocol/src/protocol/common.rs:672-690,1962`: all four methods and
  the update notification are stable. Mutations serialize by thread; list and
  reverse lookup have no thread mutation lock.
- `app-server-protocol/src/protocol/v2/thread_attachment.rs:13-141`: arbitrary
  JSON payload, stable thread-local type/key identity, created/existing result,
  paginated current membership and nullable three-way archive filter.
- `app-server/src/request_processors/thread_attachments.rs:41-100,105-145,
  148-194,197-239`: creation/removal commit and respond before broadcasting.
  Existing identity returns the original row without overwriting payload or
  emitting another update; absent removal succeeds without another update.
- `thread_attachments.rs:243-288`: local-store capability rejection is
  `-32601`; invalid identity/cursor/missing thread is `-32602`, with internal
  and conflict errors preserved separately. The RPC list limit clamps to 1-100.
- `state/src/lib.rs:118-131`: payload 64 KiB serialized JSON, identity/type
  256 UTF8 bytes, 100 retained identities per thread and 100 rows per page.
- `state/src/runtime/thread_attachments.rs:71-146`: immediate SQLite transaction
  checks owner existence, then existing identity, then capacity. Duplicates do
  not consume capacity or replace payload, even when full.
- `state/src/runtime/thread_attachments.rs:151-181,185-316,351-369`: removal,
  owner cursor binding to exact identity/archive filter, attachment keyset order
  `(created_at, id)`, thread-bound cursor and validation. Read of an absent
  valid UUID returns an empty list; mutation requires an existing owner.
- `thread-store/src/local/thread_attachments.rs:35-98,102-131`: mutation/deletion
  lifecycle reservation and storage error translation; source-specific errors
  remain native errors rather than invented driver categories.
- Native upstream journeys are in
  `app-server/tests/suite/v2/thread_attachments.rs:47-590`.

## Eight executed cases

1. Arbitrary null, scalar/array/nested Unicode payloads and stable original
   identity/time/value across changed-payload duplicates and a cold unloaded
   read, without extra model work.
2. Clamped pagination, exact stable keyset order, continuation after deleting
   the anchor, malformed and cross-thread cursors, and empty missing-owner read.
3. Exact reverse identity, archived/null/omitted filters, cursor binding, owner
   ordering, pagination and cold persistence without loading native threads.
4. Idempotent removal, recreated identity with a new ID, exact created/deleted
   notifications and synthetic thread-deletion membership cleanup.
5. UTF8 identity/type limits and serialized JSON payload boundaries, including
   changed-payload rejection before an existing-row lookup and retained state.
6. Concurrent duplicate requests retain one original value; capacity counts
   distinct identities, permits duplicate lookup when full and frees a slot
   after explicit removal.
7. In-memory backend rejects all four methods explicitly without model traffic.
8. Stable nonexperimental negotiation, local schema rejection versus actual
   native malformed-input rejection, preserved state and missing-thread errors.

Each test owns disposable HOME/CODEX_HOME/workspace, loopback synthetic provider
and the hash-pinned process, with the existing confirmed shutdown barrier. Turns
materialize synthetic native history only. No Samgita Repo, remote GitHub/App,
external service, paid model, real credentials or production task is involved.
Deleting native fixture threads exercises the native contract only inside that
case's owned scratch directory; it cannot delete Samgita or historical user data.

Notifications are correlated by exact native thread, attachment ID, type/key and
operation, with a bounded observable event wait. The Session exposes RPC results
separately from notifications; these tests do not assert raw response-before-
notification wire ordering or prove absence of duplicate notifications. Multiple
clients, remote/nonlocal stores, fork copying, active-writer/delete races and
other transports/platforms remain unqualified. No mock peer is called a native
Codex server, and no partial behavior is marked full compatibility.

## Validation and preserved failures

The initial test invocation failed compilation because three new calls omitted
the fixture helper's required empty parameter map. This was a test-only helper
arity error, not an upstream/runtime regression. The corrected test then passed
all eight cases on its first actual-native run, seed `501432`, in 8.3s. A second
recorded run at `987654` passed **8/0**, 8.6s. No assertion, deadline, production
limit or cleanup protection was relaxed. No runtime repair was needed.

Commands ran serially through `devenv shell --no-tui --` with Elixir 1.18.5 /
OTP 27.3.4.17, from `apps/samgita_codex_driver`:

```sh
MIX_ENV=test mix format test/native_attachment_lifecycle_test.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_attachment_lifecycle_test.exs --include real_codex --seed 501432
MIX_ENV=test CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl \
  mix test test/native_attachment_lifecycle_test.exs --include real_codex --seed 987654
MIX_ENV=test mix format --check-formatted
```

The subsequent repository-root test-environment warnings-as-errors compile,
format and strict Credo passed, **313 source files, no issues**. These checks
include the separately documented dynamic-interaction driver repair. Logs:

- `/tmp/samgita-native-attachment-lifecycle-initial.log`: helper compile failure.
- `/tmp/samgita-native-attachment-lifecycle-first-native.log`: first native 8/0.
- `/tmp/samgita-native-attachment-lifecycle-repeat-static.log`: second native 8/0,
  independent compile/format and repository static checks.

Nine request/response/notification entries and 37 directly asserted field/variant
contracts receive only scoped `implemented` evidence. Exact remaining limits
above still apply; complete compatibility, A11, external integration, package
publication and deployed behavior are not established.
