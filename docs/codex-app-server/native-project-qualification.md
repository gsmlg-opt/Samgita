# Codex-native project behavior

These are **Codex's native Projects**, stored in the owned Codex home. They are
separate from Samgita Projects, repository associations, Agent membership and
Task acceptance. Native `project/*` IDs never replace Samgita Project UUIDs or
confer platform authorization. The native driver preserves the upstream payload;
Samgita's ordinary native-operation authorization and fencing still apply.

The reference is Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All twelve scenarios drive that real app-server through independent Session
stdio. A loopback Responses fixture supplies only synthetic model responses for
persisted thread history; it does not emulate the project API or SQLite store.

## Persisted operations and notifications

`native_projects_test.exs` contains five scenarios:

| Operation | Required observed result |
| --- | --- |
| `project/create`, `project/read` | Trimmed name, metadata, canonical roots, timestamps and empty recency persist across process restart. Reusing a key with a different valid payload returns the original project and emits no duplicate change. Empty names/keys, overlong keys, duplicate roots and symlink aliases fail without changing state. |
| `project/import` | Duplicate, nonexistent and ephemeral thread IDs reject the entire import. Successful import associates the existing durable thread; key replay does not reassign it. Membership remains visible through cold resume and native thread filters. |
| `project/update` | Omitted/null fields preserve values; explicit empty roots/metadata clear them. Changed and repeated no-op updates have distinct notification behavior, preserving membership and creation/recency data. |
| `project/list`, `project/move` | Position-based pages contain each project once after movement. Recency excludes archived members. Invalid sort-direction and cursor combinations fail explicitly without changing ordering. |
| `project/delete` | Project membership clears while thread turns and a synthetic workspace file remain unchanged, including cold resume. Reading the deleted project fails. |

Both `project/changed` and `thread/project/updated` retain exact IDs and change
types. Assertions establish their buffered notification order and association;
they do **not** infer RPC-versus-notification wire order from Session's separate
RPC return and drain interfaces. Ordinary/cold reads never dispatch another turn.
Native idempotency is evidenced for these specific upstream methods, not inferred
from driver request IDs or generalized to other mutations.

## Capability, storage and key profiles

Seven cases in `native_project_profiles_test.exs` add:

- Absent and explicitly false experimental negotiation: every one of the seven
  project methods returns native `-32600`, naming its experimental capability
  requirement. The request uses wire-only local validation to actually reach
  upstream. No project notification or state change occurs; a later enabled
  connection sees no project created by the rejected calls.
- Explicit in-memory thread store: all seven project methods return native
  `-32601`, `unavailable without sqlite state`. Ordinary unassigned threads still
  work. This tests an actual unsupported backend, rather than substituting a
  disabled method error for enabled SQLite success.
- `sqlite=false`: the pinned feature flag is removed and defaults to true.
  Projects and keys still persist in the default local store across restart.
  Calling this flag a supported SQLite-disable switch would be incorrect.
- A 512-byte UTF8 key succeeds; 513 bytes fails with the exact native limit.
  Create/import share the durable key namespace. Valid cross-method replay,
  including a supplied nonexistent thread, returns the original before trying
  assignment; cold replay returns that same project without a new notification.
- Omitted/null/empty import collections and metadata use the evidenced native
  defaults. A deleted project's key remains reserved after restart: create and
  import fail instead of silently recreating it.

Pinned references, relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Seven experimental declarations | `app-server-protocol/src/protocol/common.rs:778-819` |
| Native negotiation rejection | `app-server/src/message_processor.rs:977-981` |
| Validation, import, notifications, unsupported storage mapping | `app-server/src/request_processors/projects.rs:75-401` |
| Unsupported store defaults | `thread-store/src/store.rs:385-440` |
| Removed SQLite flag | `features/src/lib.rs:1273-1278` |
| Durable key replay | `state/src/runtime/projects.rs:140` |
| Official storage/profile scenarios | `app-server/tests/suite/v2/projects.rs:892-1030` |

## Verification and remaining scope

The initial five cases passed at seeds `501432` and `987654`. The seven profile
cases passed at seed `501432`; both files together passed **12 tests** at each
of seeds `513498` and `987654`. Independent driver compile with warnings as
errors and scoped formatting passed. Logs:
`/tmp/samgita-native-projects-validation.log`,
`/tmp/samgita-native-project-profiles-initial.log` and
`/tmp/samgita-native-project-profiles-regressions.log`.

From the independent driver directory, with the pinned `CODEX_BINARY` in the
verified Elixir/OTP environment:

```sh
mix test test/native_projects_test.exs test/native_project_profiles_test.exs --seed 513498
mix test test/native_projects_test.exs test/native_project_profiles_test.exs --seed 987654
mix compile --warnings-as-errors
```

The fourteen request/response entries and two native notification entries are
recorded as **implemented**, with these specific tests and Linux/stdio coverage.
No field contract or requirement is promoted to **verified** by this unit.
Remaining fields/variants, concurrent clients, RPC wire-order proof and the
other required transport/backend/OS profiles remain incomplete. These local
results do not clear A11, prove real-service integration, publish a package or
establish full compatibility. Final-source aggregate/hosted results belong in
[qualification](qualification.md).
