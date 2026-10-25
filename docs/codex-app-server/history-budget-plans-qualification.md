# Native supplied history, session budget and account plans

Four added real-native cases pass in the complete five-file owning block:
**32 tests, 0 failures at seeds501432 and987654**, without exclusions.
Command durations are86.359/85.991s. Stock Codex is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Every app-server message is produced by that executable. Provider responses
and account identities are explicitly synthetic, isolated local inputs.
No Samgita application, database, real credentials or live inference is required.

## Behavior and independent evidence

| Owning test | New cases | Evidence |
| --- | ---: | --- |
| `native_session_budget_test.exs` | 1 | One explicit root turn consumes the configured30 weighted tokens:26 output plus7 input minus3 cached. The native error is exactly `sessionBudgetExceeded`, `willRetry:false`, followed by a failed completion and the same stored error in `thread/turns/list`. Exact usage, original IDs, raw provider SSE/request hashes and the native budget reminder are independently checked. |
| `native_account_metadata_profile.exs` | 2 | Seventeen explicitly prescribed known synthetic plan claims, plus future/omitted claims mapping to `unknown`. Actual native `account/updated` snapshots match independent expected literals; two `account/read` calls with `refreshToken:false` cross-check each snapshot and preserve synthetic auth/config bytes. |
| `native_default_gates_profile.exs` | 1 | Four client-supplied historical items: user input_text, plaintext agent_message, mixed reasoning_text/text, and assistant output_text with empty annotations/logprobs. Exact known IDs, item payloads and order survive native durable JSONL, occur once in the next actual provider request, and remain unchanged after an owned cold restart/read with no automatic turn or resume. |

The budget provider allows one request, returns ordinary fixed Responses SSE
and never sends a synthetic error. Goals, subagents, tools, retries and native
restarts are disabled. The same native PID remains, the completed Session is
ready with no pending interaction/uncertainty, and a one-second observation
detects any automatic continuation. This does **not** establish rejection of a
later caller-explicit turn or preservation of remaining budget across restart.
The new fixture retains evidence and verifies owned-process cleanup.

Account tests use deliberately unsigned synthetic identity tokens, never actual
authentication or entitlement. Native request and HTTP allowlists reject
refresh, model and mutation paths. Zero account-resource reads are checked at
the pre-close barrier; the post-close checks do not independently repeat that
zero-read assertion. File preservation covers auth/config, not a complete
workspace inventory. All observed account updates must match exactly, but an
exact notification count or general account-change lifecycle is not claimed.
The existing60000ms module deadline and cleanup helpers remain unchanged.

Supplied reasoning content uses a mixed array, matching pinned native filtering;
a text-only array is not qualified. `encrypted_content:null` proves only exact
nullable-field acceptance/retention. Empty summary, annotations and logprobs
prove only those empty arrays. No encryption/decryption, nonempty annotation or
logprob semantics, Agent registration/delegation, historical tool execution or
underlying model reasoning is inferred. Default transport limits are not tested
as buffer boundaries. The earlier supplied-history case remains intact.

## Exact ledger scope

Only52 still-missing physical owners receive scoped `implemented` evidence:

- 18 typed content owners in `ClientRequest.json`: output_text6,
  plaintext AgentMessageInputContent4 and the two ReasoningItemContent variants8.
- 15 outer ResponseItem owners: message ID1, agent_message7 and reasoning7.
- One canonical ServerNotification CodexErrorInfo enum leaf,
  `sessionBudgetExceeded`.
- 18 canonical ServerNotification PlanType enum leaves, each with its own
  independently prescribed observed result.

No equal-hash alias, referenced sibling, complete union or whole family gains
evidence. Account/read is a cross-check, not automatic promotion of its alias
owners. Each ID, pointer, schema subtree and test preimage is checked. The
complete resulting manifest matches the generated expected JSON and differs in
exactly these52 contract rows; all requirements and other sections are unchanged.

Requirements remain485:462 implemented/12 missing/11 blocked. Contracts remain
6621:3591 implemented/3030 missing. **Zero entries are verified.**
Inventory consistency and all37 pin/inventory/fixture tooling regressions pass. Complete final-source
local and pushed hosted matrices remain required.

## Commands and provenance

Runner `/tmp/samgita-native-history-budget-plans-v23-20261025.py` uses verified
Devenv, `MIX_ENV=test` and the hash-checked `CODEX_BINARY`. It passes namespace
and native-sandbox prerequisites, warning-free driver compile, full driver
format, both following commands and root `mix credo --strict` across442 files:

```sh
mix test test/native_session_budget_test.exs test/native_goal_budget_profile.exs \
  test/native_realtime_bem_profile.exs test/native_account_metadata_profile.exs \
  test/native_default_gates_profile.exs --warnings-as-errors --seed 501432
mix test test/native_session_budget_test.exs test/native_goal_budget_profile.exs \
  test/native_realtime_bem_profile.exs test/native_account_metadata_profile.exs \
  test/native_default_gates_profile.exs --warnings-as-errors --seed 987654
```

Frozen baseline is `c654265fbbcb5c65c52c901f393e1feb3ab35aed` plus the executable
changes in this unit. All1495 guarded source files and the binary match after
the complete run. Complete commands, logs and hashes are under
`/tmp/samgita-native-history-budget-plans-v23-20261025/`.
Terminal report `/tmp/samgita-native-history-budget-plans-v23-terminal-20261025.json`
has SHA256 `acc2c13be733dbe12d4fe7f9ff2ba3e111d39fab09710d102d64d84e573c89b3`.

| Source-only audit, bound by the parent to the passing source hashes | SHA256 |
| --- | --- |
| `/tmp/samgita-v23-history-budget-owner-review-20261025.json` | `dfd6482ee1dc846447efdfde988944c1f5b7fca435cba310a2e8e6b0b800e877` |
| `/tmp/samgita-account-plan-type-source-owner-audit-20261025.json` | `232edef92e6f34e71fbfdd2bcef9e25a2727b5f57ed6d63a6e735fd37479207c` |
| `/tmp/samgita-v23-history-outer-owner-audit-20261025.json` | `4b6ff7f354a2993bf8a6b89e9a7ce1188f509ab60876d700ddf42fc793c92acd` |

There is no v23 test failure, assertion removal, timeout increase or production
cleanup change. This is scoped evidence, not overall completion. A11,
upstream-unreachable production emissions, external/OS success, the retained
local aggregate GitHub-page failure and complete compatibility remain incomplete.
No tag, publication, production migration or deployment occurs.
