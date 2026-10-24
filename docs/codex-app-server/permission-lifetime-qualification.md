# Native permission authority across turns, threads and restart

Stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **5 tests / zero failures** at seeds `501432` and `987654`, 6.4/6.5 seconds.
The independent Session talks to the actual native process. The fixed loopback
Responses fixture supplies model data only; it never emits app-server frames.

## Actual authority and effects

The model requests write permission for the owned workspace, then a fixed
apply_patch operation. Explicit `scope: turn` permits the same-turn patch but
requires a new file approval in the next turn. Explicit `scope: session` permits
the next-turn patch in the same thread. A different thread in that app-server
does not inherit the grant. A confirmed native process shutdown followed by a
different instance/port and explicit cold resume preserves the original file and
completed-turn history, but does not restore session permission authority.

The fifth case interrupts an unanswered permission request, requires the exact
request resolution and interrupted turn in either notification order, and proves
no automatic continuation or file effect. A fresh explicit turn still prompts
for its patch; declining leaves the workspace empty. Old handles stay stale while
new prompts are pending. Every case asserts provider counts, exact file bytes,
completed history, zero pending/uncertain operations and absence of policy files.

Requests contain the exact nonnull `environmentId: local`, owned normalized
write root, cwd, reason, thread/turn/item IDs and positive timestamp. Replies use
explicit `strictAutoReview: false`; the complete model-visible result is compared
with its actual scope and root. Success is actual native patch application, not
an echoed approval value. No command, paid provider or running Samgita is needed.
Production cleanup and all original deadlines remain unchanged.

## Immutable source

Paths below are relative to the pinned `codex-rs/`:

- `core/src/tools/handlers/request_permissions.rs:67-127` resolves the environment,
  normalizes requested roots and returns the permission result to the model.
- `core/src/session/mod.rs:3190-3225,3310-3401` emits the request, retires cancelled
  callbacks, intersects granted authority and stores turn versus session grants.
  `app-server/src/bespoke_event_handling.rs:941-974,1799-1918` preserves identities,
  maps replies and rejects the separate session-plus-strict-auto-review case.
- `core/src/session/turn_context.rs:473-522,1131,1333` keeps a fresh turn grant map
  while merging the per-thread session map. `core/src/state/service.rs:113-132`
  accumulates session grants by environment; `session/session.rs:1720-1745`
  initializes a new map instead of restoring it from rollout history.
- `core/src/tools/handlers/apply_patch.rs:495-553` and
  `core/src/tools/handlers/mod.rs:289-337` merge actual grants into the effective
  filesystem policy before patch safety/approval. Upstream turn/session precedent
  is in `core/tests/suite/request_permissions.rs:1754-2003`; those source tests
  are guidance, not a local run of another OS's execution profile.

The separate file `grantRoot` populated branch has no ordinary production
producer in this pin: the two calls in
[approvals.rs](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/approvals.rs#L725-L763)
both pass `None`. A nonnull file reason is potentially reachable only through a
real approval/retry path; these tests do not manufacture one. Retained schemas
and codec behavior do not establish either runtime branch.

## Reproduction and limits

In verified Devenv, from `apps/samgita_codex_driver`, with `MIX_ENV=test` and the
exact hash-checked `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_permission_lifetime_test.exs --seed 501432
mix test test/native_permission_lifetime_test.exs --seed 987654
mix format --check-formatted test/native_permission_lifetime_test.exs
```

AST, namespace prerequisite and scoped strict Credo also pass. Logs:
`/tmp/samgita-permission-lifetime-initial-*-20261024.log`. The default conformance
driver suite includes this file. Only `PermissionGrantScope/enum/1` and the actual
local environmentId newly gain scoped implemented evidence. No row is verified;
the broad approval lifecycle remains missing. Strict auto-review true, remote
environments, network/deny/glob grants, remaining policy/race/loss/OS/service
profiles and A11 remain incomplete. No publication or deployment is claimed.
