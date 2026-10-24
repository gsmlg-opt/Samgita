# Native approval validation, nested grants and duplicate replies

Seventeen additional cases use the immutable stock Linux Codex
`rust-v0.163.0` executable, SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
source `83086188ae0614bd882818ff1aa23f3194962012`. Local deterministic model
fixtures supply tool requests and final responses. Actual Codex emits the
app-server approvals, intersects permissions, executes or declines the selected
owned effects and persists history. The model fixture never emits app-server
frames. These cases require no Samgita service, real credentials or paid task.

## Behavior and authority

- Six `native_approval_validation_test.exs` cases send malformed local reply
  envelopes/schema variants before explicit command/file accept or decline,
  and turn-write or empty permission grants. Every rejected reply preserves the
  exact original handle, timer and token, with no response outcome, uncertainty,
  extra model call, policy rule or workspace effect. The subsequent explicitly
  authorized valid reply must produce the exact native result and history;
  the old handle then fails as stale.
- Eight `native_permission_nested_test.exs` cases exercise `enabled: null`,
  null/empty legacy filesystem roots and canonical entries, empty-entry
  precedence, null-entry fallback and constrained `project_roots` special paths
  with string/null/omitted subpaths. The exact model-visible intersection is
  asserted. A sentinel remains unchanged. This is conversion/intersection
  evidence, not actual read, network, deny/glob or cross-platform enforcement.
- Three `native_approval_duplicate_replies_test.exs` cases release two callers
  only after both have captured the same fresh command/file/permission handle.
  Exactly one local reply succeeds and one fails as stale. There is one
  correlated response outcome/digest, followed separately by actual native
  resolution, completed history, exact command output or owned file bytes and
  bounded model-request counts. No arbitrary sleeps establish the race.

A successful local write is `sent_unconfirmed` until native resolution is
observed. The tests do not equate a transport return with processing completion
or promise exactly-once external execution. No timeout/reconnect triggers
automatic approval, replay or another turn. Native resolution, execution
completion and project/task acceptance remain separate. Unexpected subsequent
requests fail the relevant collector unless explicitly expected and answered.
Owned-process guardians and provider shutdown precede filesystem cleanup.

Pinned source explains these boundaries:

- `app-server-protocol/src/protocol/v2/permissions.rs:56-193` converts legacy
  and canonical permission representations; `sandboxing/src/policy_transforms.rs`
  intersects grants with requested authority.
- `core/src/session/mod.rs:3310-3401` intersects permission replies and records
  turn-scoped authority. An empty grant leaves a later patch requiring its own
  file approval, which is explicitly declined in the control case.
- Driver `Session.respond` validates before removing its generation-bound
  interaction. Serialized handling rejects the second reply after settlement.
  The barrier exercises two competing callers against an actual pending native
  request rather than fabricating one in a scripted app-server peer.

The three existing client-response entries gain selected evidence; the broad
`lifecycle:approval-decisions` requirement remains missing. No additional schema
contract is promoted here: shared nested definitions are inventoried under
`CommandExecutionRequestApprovalParams.json`, while these new nested cases
exercise permission responses. They cannot qualify unobserved command-request
owners merely because types are shared. All legacy approval entries keep their
[source-proven unreachable boundary](legacy-approval-qualification.md).

## Executed checks

From the independent driver package, using the verified Devenv and pin:

```sh
mix test test/native_approval_validation_test.exs test/native_permission_nested_test.exs --seed 501432
mix test test/native_approval_validation_test.exs test/native_permission_nested_test.exs --seed 987654
```

Both passed **14 tests / zero failures**, 12.3/12.5 seconds. Results and logs:
`/tmp/samgita-native-approval-adoption-v1-20261024/`. The three concurrent cases
passed in the combined **18/0** run at both seeds documented in
[thread qualification](thread-settings-read-state-qualification.md), with
formatting, compile and strict Credo passing in its final v3 runner. The earlier
combined runner failures belong to thread draft expectations; they are preserved
in that record. No native approval failure was suppressed or deadline enlarged.

These ordinary `_test.exs` modules join the required default suite. Final-source
full-package, preserved-platform and hosted checks remain required. Other
approval branches, transport loss/recovery variants, OS/backend success, A11
confidentiality and complete compatibility remain incomplete. No release or
deployment follows from this checkpoint.
