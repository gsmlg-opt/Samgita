# Native retained-deny directory effects

`native_permission_effects_test.exs` passes **one test / zero failures** at both
seeds `501432` and `987654` (1.2 seconds each). Every app-server frame comes from
stock Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The local fixture supplies four prescribed model responses only.

## Discriminating behavior

One turn requests write access to an owned directory and deny access to its
`secrets` child directory. The explicit permission reply grants only the positive
write entry, deliberately omitting the deny. The native normalized tool output
must retain **both** requested entries. This adds physical effect evidence to the
earlier [conversion/intersection cases](permission-variants-qualification.md):

1. A public sibling patch completes without a file callback. Its native item,
   exact unified diff, actual file bytes and provider continuation all agree.
2. Updating the private child requires a new file callback before any effect.
   The callback's original thread/turn/item identity matches the exact native
   item containing the independent prescribed change; callback params have no
   invented paths or diffs. Public bytes are already updated; private bytes
   still match their original value.
3. Explicit decline leaves private bytes unchanged. The native declined item,
   request resolution, terminal turn, provider call counts 1/3/4 and persisted
   file items agree. Both handles become stale; no rule file or new workspace
   entry appears. The test checks regular-file types and complete listings.

The restricted read-only base policy, turn-scoped grant and explicit
`strictAutoReview: false` stay intact. No generic approval handler, policy
relaxation or unsandboxed fallback is introduced. The existing owned-process
guardian closes before provider/root teardown; Session DOWN, closed port and
completed cleanup are asserted. The 15-second event deadline is unchanged.

## Pinned source and scope

Paths below are relative to the immutable `codex-rs/` source:

- `sandboxing/src/policy_transforms.rs` 147-195, 310-358 retains requested deny
  constraints during intersection; 554-605 merges them into the effective
  restricted policy. `core/src/session/mod.rs` 3347-3410 stores the turn grant.
- `protocol/src/permissions.rs` 1008-1063 uses the most specific path root.
  Both the private target **and its parent** lie in the denied directory.
- `core/src/tools/handlers/apply_patch.rs` 225-260, 495-553 derives additional
  parent authority and prepares safety checks; `handlers/mod.rs` 289-390 does
  not treat the changed grant as preapproved. `core/src/safety.rs` 103-182,
  `core/src/apply_patch.rs` 23-56 and `tools/approvals.rs` 725-764 lead to the
  ordinary pending callback before execution.
- Native update diffs come from `apply-patch/src/file_update.rs` 172-207 and
  `app-server-protocol/src/protocol/item_builders.rs` 370-376. Before running
  this draft, the independently established one-line `@@ -1 +1 @@` oracle
  replaced its raw patch hunk expectation; no failing native result was hidden.

This result does **not** establish the same callback for an exact-file deny under
a writable parent, or a deny glob. `protocol/src/permissions.rs` 1987-1997 omits
globs from resolved write roots. Denied-read glob matching (1090-1180) and later
sandbox enforcement are separate from this preflight. `handlers/mod.rs` 532-575
even tests preapproval with relative deny globs; `tools/sandboxing.rs` 284-306
and `tools/orchestrator.rs` 465-472 can return sandbox failure before a retry
approval. No glob callback, glob runtime outcome or vulnerability is fabricated.
Its actual enforcement still requires an independent native effect profile.

## Reproduction and qualification boundary

In verified Devenv from `apps/samgita_codex_driver`, with `MIX_ENV=test` and
`CODEX_BINARY` set to the hash-checked pin:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test test/native_permission_effects_test.exs --warnings-as-errors --seed 501432
mix test test/native_permission_effects_test.exs --warnings-as-errors --seed 987654
```

Root strict Credo, in-memory Python fixture parsing and exact source guards pass.
Runner/artifacts: `/tmp/samgita-native-permission-effects-v1-20261024.py` and its
same-named directory. No native test failure or skipped assertion occurred.
Five existing permission/file/lifecycle entries gain supplemental evidence only;
no field/state promotion occurs and the broad approval lifecycle stays missing.
Other denies, arbitrary paths, symlinks/hardlinks, all grant lifetimes,
reconnect/remote environments, Guardian, other OS/services and A11 remain
unqualified. Final combination/hosted checks, publication and deployment are
separate; this record claims none of them.
