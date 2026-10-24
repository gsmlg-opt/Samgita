# Native permission variants and strict turn review

Stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **11 tests / zero failures** at seeds `501432` and `987654`, in
12.1/12.0 seconds. The independent driver uses the actual Linux stdio app-server
with `experimentalApi: true`; no running Samgita or real provider is required.
These results index 26 exact schema contracts as scoped implemented
evidence, **0 verified**. They do not complete the approval lifecycle or full
compatibility.

## Behavior and candidate mapping

Line references below are in
`apps/samgita_codex_driver/test/native_permission_variants_test.exs` after
formatting. The 26 candidates are grouped **1 + 15 + 9 + 1**:

| Group | Count | Actual evidence and boundary |
| --- | ---: | --- |
| Legacy read | 1 | Lines 98–128 compare the exact read-only callback, canonical read entry and model-visible read root, with no write widening. Covers `AdditionalFileSystemPermissions.read`. |
| Canonical filesystem | 15 | Lines 131–185 compare read/write/deny path entries, a deny glob and depth 2. A reply omits both denies and requests depth 3; native intersection retains both denies and depth 2. Covers `entries`, `globScanMaxDepth`, the three access modes, entry path/access and path/glob tagged branches. This proves conversion/intersection, not OS deny/glob enforcement or glob expansion. |
| Network | 9 | Lines 54–94 exercise true, false, null, omitted and requested-false/granted-true replies. Only requested true plus granted true yields network enabled; all other grants yield null. Exact null filesystem and turn scope are compared. Covers `AdditionalNetworkPermissions.enabled`, request/grant network object/null branches and request/grant null filesystem branches. No network tool runs; OS network enforcement is untested. |
| Strict turn review | 1 | Lines 222–297 exercise `strictAutoReview` true allow/deny and false control through a real safe command, correlated native review notices and exact command outcomes. Covers the response property for this nonempty turn-grant profile. |

The empty-grant case (lines 188–219) adds a control: `permissions: {}` produces
null authority, then an actual patch independently requests file approval.
Declining leaves `must-not-exist.txt` absent and the file-change item declined.
This control adds no separate candidate claim. Existing session-lifetime and
session-plus-strict rejection tests remain separate evidence.

For strict true, the fixed model requests `printf samgita_strict_turn` with
`login: false`. Both allow and deny have exactly one Guardian provider request
and four total provider requests. False control has zero Guardian and three
total. Guardian identity comes from native
`client_metadata.x-openai-subagent == "guardian"`, not a request index. Allow
and control complete with exact stdout `samgita_strict_turn` and exit code 0;
deny is declined with null output and exit code. There is one user callback,
with no second manual approval. Started/completed notices share exact
thread/turn/item/review identities, have valid ordered timestamps and report
approved/denied; the false control has neither notice. This establishes an
actual review-dependent command outcome, not just an echoed flag.

Every case checks completed-turn history, zero pending interactions and
uncertain operations, stale callback rejection and no persisted policy file or
workspace writes (lines 361–394). Provider counts are bounded per scenario.

## Native and fixture boundary

`scripts/codex/permission_variants_fixture.py:15–51` supplies fixed Responses
model output and fixed Guardian assessment JSON only. It never supplies
app-server frames. Actual Codex generates callbacks, intersects grants,
dispatches the command/patch, emits review notices and stores turn history.
The fixture config selects reviewer `user`, enables request-permissions and
Guardian, disables Guardian v2 and uses the inherited read-only sandbox
(lines 83–90). Strict turn review therefore exercises the native forced-review
path despite reviewer `user`.

The fixed allow/deny assessments do not establish real Guardian classification
quality, all approval policies, scoring, cache behavior or provider integration.
These tests use explicitly owned temporary roots, hash-check the binary and
start with empty inherited environment (test lines 14–49, 301–325). Their
inference endpoints are loopback fixtures. The separate namespace preflight
passed; this suite itself does not use the private-network-namespace execution
profile and does not establish that isolation boundary.

Immutable source explains the tested behavior, relative to pinned `codex-rs/`:

- `app-server-protocol/src/protocol/v2/permissions.rs:56–193` converts canonical
  and legacy permissions, including null legacy roots for deny/glob entries.
- `sandboxing/src/policy_transforms.rs:19–76,147–254,264–358` intersects network
  grants, preserves constraining denies and bounds deny-glob scan depth.
- `core/src/session/mod.rs:3310–3401` intersects grants, leaves empty grants
  without authority and records strict review for nonempty turn grants.
- `core/src/tools/orchestrator.rs:141–225` forces approval for an otherwise-safe
  command; `core/src/tools/approvals.rs:437–450,571–587` requires Guardian.
  `ext/guardian-reviewer/src/routing.rs:86–91,130–141` honors that requirement
  with reviewer `user`. These source paths do not expand the tested OS profile.

## Reproduction and retained limits

The coordinating agent ran these commands in verified Devenv, from
`apps/samgita_codex_driver`, with `MIX_ENV=test` and the hash-checked
`CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_permission_variants_test.exs --seed 501432
mix test test/native_permission_variants_test.exs --seed 987654
mix format --check-formatted test/native_permission_variants_test.exs test/native_thread_future_settings_test.exs
```

Root `mix credo --strict` passed across 360 files; the namespace prerequisite
also passed. Logs and source hashes are in
`/tmp/samgita-native-three-units-v3-20261024/{results.json,source.json}` and the
corresponding command logs. The test hash matches that run. The only later
fixture change replaces its draft module documentation; executable Python is
unchanged. Final combined validation covers that delivered source separately.
The initial v2 attempt failed compilation because the test lacked the
`notification: 2` import; zero native cases ran. Adding that import enabled the
v3 runs above. No assertion or deadline was weakened. This document's author
reviewed the recorded results and final sources; the coordinating agent ran the
executable checks.

Remaining approval, race, loss, restart, remote-environment, OS and external
service profiles remain incomplete; A11 remains blocked. No row gains verified
status. This is neither full compatibility nor real Sigma/Synapsis/provider
integration, package publication, release, production readiness or deployment.
