# Native quota-read field qualification

Ten actual-binary cases pass at seeds `501432` and `987654`, 19.9/20.0 seconds
on final source. Python AST, namespace preflight, warnings-as-errors compile,
format and scoped strict Credo pass. This is selected read-result evidence
against an owned synthetic backend; real quota/account service and complete
compatibility remain unqualified.

The immutable target is official Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
`account/rateLimits/read` is stable in this pin. The profile initializes with
`experimentalApi: false`; the fixture rejects experimental initialization.

## Implementation

The installed files use these repository-relative paths:

| Draft | Intended destination |
| --- | --- |
| Test | `apps/samgita_codex_driver/test/native_rate_read_profile.exs` |
| Fixture | `scripts/codex/isolated_rate_read_fixture.py` |
| Qualification | `docs/codex-app-server/rate-read-qualification.md` |

The fixture deliberately reuses only the retained
`isolated_account_control_fixture.py` synthetic auth/configuration/close helpers.
It overrides that fixture's server and stdin allowlist. Importing the helper
does not instantiate its POST backend. Its known synthetic JWT reports `pro`;
the new plan matrix verifies that the read result instead projects the backend
quota SKU. The fixture cannot be run from the draft directory without placing
the retained helper on Python's module path; installation beside that helper is
the proposed integration. This is a test dependency, not a protocol dependency.

## Coverage added to retained profiles

The existing `native_account_metadata_profile.exs` already qualifies selected
primary/additional quota projection, primary minute rounding, available/unknown
reset-credit enums, invalid grant timestamps, HTTP failures, account/user
identity gates, omitted quotas, opt-out and reserve support. The separate
`native_account_control_profile.exs` already covers reset consumption outcomes
and mutation uncertainty. This draft preserves those tests and adds no
consumption/nudge/login/logout calls.

Ten proposed cases add these selected behaviors:

| Case | Added positive/fallback evidence |
| --- | --- |
| Codex API full snapshot | Exact `/api/codex/usage` and `/api/codex/rate-limit-reset-credits` GETs; secondary window, credits balance, spend limit, false ordinary-usage permission, Unicode quota key/name, model alias, missing additional quota, detailed count precedence; reserve header only on usage. |
| ChatGPT API full snapshot | Same semantics through `/backend-api/wham/...`, without assuming backend route style changes the native schema. Explicit false reserve and true exclusion are verified on a second read. |
| Plans | All 18 public SKU outputs plus backend `education -> edu`; guest/free_workspace/quorum/k12/future_plan -> unknown. No paid entitlement is obtained. |
| Reached reason | All five native snake_case reached-type values; future/nullable backend values become null. Missing rate-limit permission remains null despite a reached reason. |
| Windows and balance | Both quota windows remain distinct; zero/negative durations become null minutes, positive seconds ceil to minutes, zero/negative/i32-boundary reset timestamps and percentages are preserved. Explicit zero balance, nullable/omitted balance and both credit booleans remain data. |
| Duplicate limit ID | Singular `rateLimits` uses the first default codex snapshot; `rateLimitsByLimitId` retains the final duplicate codex value. This is observed mapping behavior, not a new policy favoring a duplicate quota. |
| Detailed credits | Four statuses including redeeming/redeemed; known/unknown reset types; Unicode opaque ID/title/description; offset and pre-epoch timestamps; nullable fields; backend count greater than returned row count. |
| Empty/unavailable details | Successfully fetched empty list differs from summary-only null. Details win over a different usage count or absent usage summary. A 404 detail read falls back to a present summary, or null when no summary exists. |
| Invalid expiry | A valid row followed by a malformed expiry rejects the entire details projection and preserves the usage count with null rows. |
| Actual details deadline | The immutable release's five-second details deadline returns the current usage summary while its held detail GET remains unfinished. Explicit release permits teardown; there is no redemption, replay or timeout override. |

The timeout case measures from request initiation and checks a bounded broad
window (4–15 seconds) around the official five-second details deadline while
preserving Session's ordinary request deadline. A native response plus an
unfinished owned HTTP request is the semantic assertion; elapsed time alone is
not sufficient. Its fixture release barrier is bounded to eight seconds and
can be interrupted by shutdown. No test-only debug environment variable is
used to change official timeout behavior.

Every request uses an exact response correlation ID. Every case checks no
loaded threads, no active interactions, ready Session state, an empty uncertain
ledger, no server execution requests/turn start, successful owned process
reaping, peer shutdown and synthetic-secret absence from native output,
stderr/journal. All app-server JSON lines are emitted by the official binary;
the HTTP fixture creates no app-server responses or notifications.

## Safety and bounds

The controller requires a distinct user namespace and network namespace, UID
mapping, loopback only, and no IPv4/IPv6 default route. There is no fallback to
host networking, no privileged namespace request and no nonlocal backend.
Only the owned pinned binary and fixed synthetic peer are started. Normal test
and assertion-failure cleanup use the retained Stdio process-group owner.
Scratch roots are random and exclusive; deletion waits for recorded owned
native/controller/namespace-owner PIDs to disappear. No unrelated process is
signaled or deleted. A native setup failure before PID journaling remains a
coordinator cleanup-review item, rather than a claim of proved failure teardown.

The native environment uses synthetic auth in an owned `0600` auth file, no
inherited account tokens, and a read-only model catalog. Configuration disables
hooks, apps, plugins, recommendations, shell snapshots, web search, analytics,
remote control and provider retries. Only initialize/initialized,
`account/rateLimits/read` and `thread/loaded/list` can reach native stdin. HTTP
accepts only bodyless GETs for usage, details and three narrow startup metadata
routes. Every POST/PUT/PATCH/DELETE/HEAD or unknown path is rejected. Header
values are journaled as booleans, never bearer strings.

Bounds per process: 64 native input messages at 16 KiB/frame, 96 native output
messages at 64 KiB/frame, 256 KiB stderr, 64 quota/detail HTTP reads, 64 KiB HTTP
response, 256 journal events, five-second socket deadlines and bounded owned
native/reader/server shutdown. The largest case is 24 quota reads, well below
these limits. Native output is passed through as original bytes and checked for
known synthetic secret strings; no fake compatibility frame is manufactured.

`supportsLunaReserve: true` is tested only against the synthetic usage GET.
Official source permits the real backend to record experiment exposure on this
flag; this profile makes no real account request, experiment or credit claim.
Quota/banner/credit text remains untrusted display data and grants no Samgita
Project authorization, execution authority, review or Task acceptance.

## Exact pinned source evidence

Paths below are relative to the pinned `codex-rs/` source tree:

| Contract | Source |
| --- | --- |
| Stable method and nullable/default params | `app-server-protocol/src/protocol/common.rs:1341-1346`; `v2/account.rs:315-356` |
| Auth eligibility, parallel read/detail lookup, singular/map projection and active identity | `app-server/src/request_processors/account_processor.rs:1192-1297` |
| Usage/detail GETs and reserve header | `backend-client/src/client/rate_limit_resets.rs:23-89,124-139` |
| Wrapper metadata, normal-model alias and credits detail structs | `backend-client/src/types.rs:23-73` |
| Additional quota, spend-control, credits, reached reason and plan conversion | `backend-client/src/client.rs:615-688,729-822` |
| Wire fields, enums and duration/reset projection | `app-server-protocol/src/protocol/v2/account.rs:315-397,664-810`; `protocol/src/account.rs:10-47` |
| Backend plan/reached enums with unknown fallback | `codex-backend-openapi-models/src/models/rate_limit_status_payload.rs:78-149` |
| Backend required quota/window/spend/credit fields | `codex-backend-openapi-models/src/models/{rate_limit_status_details,rate_limit_window_snapshot,spend_control_status_details,spend_control_limit_details,credit_status_details}.rs` |
| Fixed five-second details deadline, fallback and all-or-nothing timestamp conversion | `app-server/src/request_processors/account_processor/rate_limit_resets.rs:10-48,122-173` |
| Upstream native example, not this draft's executed evidence | `app-server/tests/suite/v2/rate_limits.rs:105-485` |

The no-snapshots error is source-defined but the valid generated usage decoder
always creates a default codex snapshot. The fixture does not invent an empty
snapshot path to manufacture that error. The response map is native HashMap
projection; map iteration order is not asserted. Quota arrival order is not a
task or remote execution ordering contract.

## Scoped manifest links

The following **28 existing schema contract IDs** have direct positive value
assertions in the passing profile, with existing metadata tests retaining
identity/error branches. They gain `implemented` links with the above
restrictions, not `verified` complete-contract claims. Existing request/response
entries gain this additional evidence without being counted as new entries:

```text
client_request:account/rateLimits/read
server_response:account/rateLimits/read
```

```text
schema:ClientRequest.json#/definitions/GetAccountRateLimitsParams/properties/excludeResetCreditDetails
schema:ClientRequest.json#/definitions/GetAccountRateLimitsParams/properties/supportsLunaReserve
schema:v2/NullableGetAccountRateLimitsParams.json#/anyOf/0
schema:v2/NullableGetAccountRateLimitsParams.json#/anyOf/1
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/description
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/expiresAt
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/grantedAt
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/id
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/resetType
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/status
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCredit/properties/title
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditStatus/enum/0
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditStatus/enum/1
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditStatus/enum/2
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditStatus/enum/3
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditsSummary/properties/availableCount
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetCreditsSummary/properties/credits
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetType/enum/0
schema:v2/GetAccountRateLimitsResponse.json#/definitions/RateLimitResetType/enum/1
schema:v2/GetAccountRateLimitsResponse.json#/properties/accountId
schema:v2/GetAccountRateLimitsResponse.json#/properties/ordinaryUsageAllowed
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimitResetCredits
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimitResetCredits/anyOf/0
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimitResetCredits/anyOf/1
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimitUpsell
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimits
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimits/allOf/0
schema:v2/GetAccountRateLimitsResponse.json#/properties/rateLimitsByLimitId
```

The response schema contains shared `PlanType`, `RateLimitReachedType`,
`RateLimitSnapshot`, `RateLimitWindow`, `CreditsSnapshot` and
`SpendControlLimitSnapshot` definitions. The current manifest deduplicates their
field IDs into notification schemas. This profile exercises those native
**read-result** shapes, but does not cause a rate-limit notification. Do not
bulk-promote `ServerNotification` or
`v2/AccountRateLimitsUpdatedNotification.json` emission/field contracts from
these reads. Record shared type evidence with its actual read-result context;
retain notification emission requirements until their own paths are qualified.

## Validation and limitations

Source review tightened cleanup before execution: active HTTP workers/sockets
are owned explicitly, held work is released on shutdown, server polling is
bounded, and all explicit teardown waits share 0.75s inside the unchanged stdio
owner grace. The fixture rejects all three host system config files and disables
the source-defined hooks key. The first two native runs already passed **10/0**,
20.1/20.0s. Strict Credo then reported one test helper above its complexity bound.
Extracting its unchanged namespace/backend assertions resolved lint without
altering any behavior or deadline; final native repeats pass as stated above.

From the independent driver directory in verified Devenv, with `MIX_ENV=test`
and pinned `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_rate_read_profile.exs --seed 501432
mix test test/native_rate_read_profile.exs --seed 987654
mix format --check-formatted test/native_rate_read_profile.exs
```

Root scoped `mix credo
apps/samgita_codex_driver/test/native_rate_read_profile.exs --strict` passes,
as do AST and private-namespace preflight. Logs:
`/tmp/samgita-rate-read-*-20261024.log`. Owned native/controller/backend/readers
and canary checks pass. Deliberately interrupted assertion teardown is not
separately qualified here. CI explicitly selects the non-default profile;
final aggregate/hosted and independent-consumer checks remain separate.

Real ChatGPT/AWS/external quota service, FedRAMP/alternate auth, live auth change
while reads are in flight, whole-usage timeout/retry scheduling, other OS and
transports, real reserve experiments, reset redemption, notifications, paid
tasks, platform integration, A11, hosted aggregate checks, publication and
production readiness remain unqualified. This draft neither shrinks the full
compatibility goal nor claims any of those gates passed.
