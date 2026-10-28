# Ordinary root inputs, quota error and cleanup evidence

This unit follows `d08fa36` on the existing `main` and continues the full
compatibility goal. Codex remains stock `rust-v0.163.0`, commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`, source
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

All owned launches use fixed `never` / `danger-full-access` configuration.
Only ordinary functional behavior is checked. Security, credentials,
authentication, authorization, permissions, approvals and sandbox behavior are
outside verification. Existing tests/gates stay intact; prohibited checks,
audits, broad mixed suites and hosted workflows remain unrun/incomplete.

## Exact physical contracts

Fourteen previously missing physical owners gain scoped `implemented` evidence,
with eleven existing requirement supplements. No entry becomes globally
verified and no equal-hash alias or neighboring field gains automatic evidence.

| Index | Physical contract | Actual behavior and independent oracle |
| --- | --- | --- |
| 83–87 | ClientRequest CapabilityRootLocation environment branch, environmentId/path/type/literal | Two original thread/start inputs select independently authored full/empty environment roots; executor discovery and actual provider input differ accordingly. |
| 592–594 | ClientRequest SelectedCapabilityRoot id/location/reference | The same original inputs bind the root's stable ID and actual environment location through the exact physical graph. |
| 1022 | ClientRequest oneOf147 params null | Existing ordinary profile reads send actual explicit null with typed request IDs across distinct native generations and independent scalar/daily data. |
| 1515–1516 | ClientRequest oneOf82 delete method/literal | Existing original delete input has the selected literal, an independent matching DELETE effect, mapping removal, retained edited files and final empty list. |
| 2048 | ServerNotification CodexErrorInfo anyOf0 | Actual terminal usageLimitExceeded scalar from one provider 429 is bound to the exact known-string branch, original incoming bytes and failed-turn effect. Other enum values/future errors are excluded. |
| 2351 | ServerNotification RateLimitReachedType enum0 | Native header parsing emits the exact rate_limit_reached value before the terminal error and failed turn. |
| 2372 | ServerNotification RateLimitSnapshot rateLimitReachedType anyOf0 | The actual notification contains the nonnull reference value; other reached types and account/credit/policy behavior are excluded. |

ClientRequest root SHA256 is
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`;
ServerNotification root is
`c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`.
The manifest retains every exact pointer and canonical node hash.

## Root capture

The retained environment-skills scenario now captures only its two genuine
thread/start exchanges, integer 3900 and string `3900`. It records original
driver JSONL bytes, bytes actually flushed to native stdin and original native
reply bytes. Capture registration is serialized with the native input write;
the real output recorder cannot overtake it. All other bootstrap exchanges stay
opaque. No app-server response is synthesized.

Both original inputs validate against their unique physical thread/start
branch and pinned root. The test separately prescribes the full and empty root
URIs, stable ID and environment. Existing executor fs/walk/fs/readFile,
namespaced-skill discovery, provider-input, two completed-turn, idle-state and
cleanup assertions remain. Capture is bounded to two typed requests, 8 KiB per
input, 64 KiB per reply, 192 KiB total raw bytes, the existing 160-entry/1 MiB
journal and unchanged deadlines.

Source consumption remains `capabilities.rs`, `thread_processor.rs`,
`environment_selection.rs` and `skills/loader/environment.rs` at the immutable
pin. Source-only recipe and exact owner hashes are in
`/tmp/samgita-ordinary-environment-root-next-gap-20261028.md`; runtime evidence
comes from the repository test, not that draft.

## Provider 429

The new standard-library-only synchronous loopback fixture serves exactly one
Responses POST, with an independently authored 429 body and seven ordinary
quota headers. It creates no fake Codex peer. The unchanged stock executable
produces one quota notification, terminal error and failed-turn completion in
that order. Snapshot percentages are integers (91/32), durations 60/1440 and
reset times 2000000100/2000000200. Original native error maps and wire bytes are
retained, with exact thread/turn association and emitted-time bounds.

The test requires one provider request containing the literal Unicode input,
six strictly correlated responses/seven outgoing frames, no assistant result,
no pending/uncertain work, unchanged request journals across idle reads/close,
and confirmed process/Port cleanup. Neither timeout nor failure replays a turn.
Identity/credit/entitlement fields and request headers are opaque setup.

Pinned producers are `codex-api/src/{api_bridge,rate_limits}.rs`,
`codex-client/src/retry.rs`, `core/src/session/{mod,turn}.rs` and
`app-server/src/bespoke_event_handling.rs`. The source/archive handoff is
`/tmp/samgita-ordinary-residual-rate-metadata-next-gap-20261028.md`.
The first draft incorrectly expected float percentages; exact pinned native
encoding required integers. The correction retains strict equality and all
original bounds. No deadline or assertion was relaxed.

## Final-source functional qualification

Focused checks pass both seeds before final integration. A default-dev root
format attempt fails while checking retained Telemetry.Metrics dependency BEAM
types; it is not a passing format check. Formatting in the repository-required
verified test environment from the independent driver directory succeeds,
without dependency changes. Review also fixes the cleanup fixture's assertion
order before final checks; see [stdio diagnostics](stdio-cleanup-diagnostics.md).

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-roots-rate-diagnostics-final-20261028
```

All **17 reviewed steps pass**, with **1,747 identical guarded sources**,
fingerprint `6be3b3eb3da485b542bca50a789a6cc5fe9f070e333f0b4a9d371d3f65b228fc`.
This is a reviewed functional selection, not the complete required
security/hosted/release matrix. The runner retains
all 164 original cases at both seeds and their 320-second bounds, adds the
separately bounded five-case extension group and four cleanup regressions, and
checks three overflow/replay seeds including 455834, an isolated outside
consumer, inventory consistency, compilation, format, strict Credo, Dialyzer
and assets. It refuses changed source fingerprints and records actual counts.

| Final check | Actual result |
| --- | --- |
| Overflow/replay, seeds 455834/501432/987654 | Three selected cases per seed, zero failures (16 discovered /13 excluded) |
| Four cleanup phases, seed 501432 | 4/0, 2.908 s |
| Retained ordinary group, seed 501432 | 164/0, 283.701 s command time |
| Retained ordinary group, seed 987654 | 164/0, 298.895 s command time |
| Extended ordinary group, seeds 501432/987654 | 5/0 each, 9.171/8.217 s |
| Outside consumer | 1/0, actual immutable binary outside umbrella |
| Inventory, driver/umbrella compile, formats, strict Credo, Dialyzer, assets | All pass |

Evidence directory is the command's exact output path. Results JSON SHA256 is
`db7254f71830dfcc4915ad04c821e7fe18e17bb3bca8d50efb9c10de623946ab`;
source-guard JSON is
`b8ab73c2e40a3f23a45643d76ef91762de5cc96803cf91709aef3456a28cbfed`;
command-plan hash is
`ad257b33ec441d358c30160be1c7ca1009c94419af1f9bd6e2758b42ab64b762`.
The two retained native log hashes are
`9eb2425204f7772af84131b73d10a3acaf8ac3de1ccd69c6aab5277767ebae94` and
`97c1ecaf1afe023bbf5c4bd3ef3bde13d8d35b180e0b2ca2580cf8652bd41c19`.
All 1,736 previously guarded files other than the seven explicitly changed
runner/manifest/helper/owner/environment-test sources remain exact; four new
sources bring the prior 1,743 to 1,747. No prior assertion or command argument
is removed. This successful uninstrumented repeat does not establish the
earlier intermittent failure's cause.

## Continuing goal and blockers

Current manifest: 485 requirements (462 implemented /12 missing /11 blocked)
and 6,621 field/variant contracts (5,697 implemented /788 missing /136 blocked).
Globally verified count remains zero. These are generated ledger counts,
not a complete-compatibility percentage.

Existing Plug.Crypto 2.2.1 locks, deterministic overflow/replay barriers and
fail-closed populated-database fixture isolation remain intact. No database
recovery rerun or security audit is claimed for this unit. The original
intermittent stdio failure is still unexplained; successful repeats and newly
classified failure branches do not prove a repair.

[A11](a11-ingress-boundary.md) remains blocked on supported pre-emission
instrumentation/complete ingress prerequisites, with prohibited canary tests
unrun. [Legacy reachability](legacy-approval-qualification.md) retains exact
upstream declaration, dispatch and test-only construction evidence; scripted
messages are not real enabled legacy acceptance. External/OS success profiles,
native producer/precision gaps and the final full-source matrix remain open.

A source-only audit maps the preceding 802 missing owners in
`/tmp/samgita-ordinary-residual-next-gap-report-20261028.md` and its exact JSON
owner/source bindings. Its working allocation is not exhaustion: 129 owners
remain unresolved and ordinary summary/Git original-wire work continues.
No branches/worktrees, sibling-service edits, paid/live tasks, production
migrations, publication, release or deployment occur. Pushes suppress automatic
CI while the user's test restriction applies.
