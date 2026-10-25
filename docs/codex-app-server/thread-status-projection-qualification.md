# Native live status and search projections

Status: scoped implemented evidence; **full compatibility remains incomplete**.
Two added stock-native cases pass in the complete seven-file owning block:
**49 tests / zero failures**, no exclusions, at seeds 501432 and 987654.
Target: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Production code, fixtures, permissions, cleanup and existing deadlines are unchanged.

## Terminal error and explicit recovery

The new overload-terminal case in `native_provider_errors_test.exs` uses the
existing local provider and owned Unix WebSocket process. Its experimental
handshake enables the actual native `thread/search` gate. The first turn emits
active, turn-started, systemError, nonretryable error and failed completion in
that order, with the prescribed exact serverOverloaded error. Full read and
content search retain the same error latch, identity, path, snippet and failed
history. Repeated queries produce no new provider request, interaction or turn.

Only an explicit second turn recovers to idle and produces the fixed answer.
Exactly two captured provider requests retain the original and continuation
markers; both saved turns remain present. This qualifies six physical
systemError variant/type/enum owners: three in `ServerNotification.json` and
three in `v2/ThreadSearchResponse.json`. The live latch is not claimed to survive
native restart. Closing its borrowed Session alone would not restart the
fixture-owned native process, so no cold-error-persistence claim is made.

## Pending tool, completion and cold read

The added case in `native_turn_steering_test.exs` uses the existing dynamic-tool
fixture and owned stdio transport. The actual request remains pending while
two native searches and full reads report the same inProgress turn and
`activeFlags: []`. Queries preserve one generation-bound handle and one provider
request; they produce no completion, reply, uncertainty or implicit execution.

One explicit reply to the original handle continues the turn. The second
provider input contains the exact original function call and matching output.
All three completed items agree with their native item-completed events and
saved history. The native process is then confirmed closed and restarted;
cold search/read report notLoaded with identical completed turns, no loaded
threads and no third inference. Configuration bytes remain unchanged.

Four physical active variant/activeFlags/type/enum owners in
`v2/ThreadSearchResponse.json` gain evidence. Empty flags qualify no flag enum
leaf. The synthetic dynamic-tool response is not external tool execution.
The tests assert actual saved history and rollout bytes before search; legacy
`thread/read` itself is not a general recorder-flush contract.

## Verification and limits

Command:
`devenv shell --no-tui -- python3 -B /tmp/samgita-native-status-projection-v26-20261025.py`.
It runs namespace/native-sandbox prerequisites, warning-free driver compile,
format check, both complete native blocks and strict Credo. The seven files are
provider errors, turn steering, search projections, thread-search timeline,
thread-event lifecycle, session budget and process lifecycle. Both native runs
pass in 58.903/58.669 seconds. All 1,495 guarded source files and the pinned
binary match after completion.

Parent preflight checks 25 source preimages and all ten complete original
manifest rows/canonical nodes. The disjoint prior 140-owner promotion explains
the historical manifest hash change. Applied test preimages and virtual patch
hashes match independent review; two comments were corrected before formatting
to avoid claiming that a read flushes persistence. The exact complete resulting
manifest matches the generated expected JSON, changing only ten contracts.
Inventory consistency and all 37 tooling regressions pass.

Evidence is retained locally:

- `/tmp/samgita-native-status-projection-v26-20261025/{source.json,results.json,guards.json,*.log}`.
- `/tmp/samgita-v26-status10-parent-preflight-20261025.json`.
- `/tmp/samgita-thread-status-projection-review-20261025.json`, SHA256
  `7df86e7bee02de0039276cb92bf03a173b43ac1e935bbca7c1cb3be824ad7a8d`.
- `/tmp/samgita-v26-status10-owner-terminal-20261025.json`, SHA256
  `38861046b14d5190a4a187b26121767923444892294d633cc9deddab3cdef584`.
- `/tmp/samgita-v26-status10-owner-bound-20261025-index.json` records each physical
  owner, named case, test hash and transport. No equal-hash alias inherits proof.

The regenerated ledger is **3,791 implemented / 2,830 missing contracts** and
**462 implemented / 12 missing / 11 blocked requirements**, zero verified in
both sets. Final combined-source and hosted checks remain required. A11,
unreachable production emitters, external/backend/OS success, retained aggregate
failures and complete compatibility remain incomplete. No release, deployment,
real credentials or live provider acceptance is asserted.
