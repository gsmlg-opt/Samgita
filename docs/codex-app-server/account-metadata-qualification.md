# Native account metadata reads

The later [history/budget/account-plan continuation](history-budget-plans-qualification.md)
adds actual startup account notifications and explicit non-refreshing account
reads for synthetic plan claims. Its separate limits and two-seed evidence
supersede the original unit's no-notification scope for those added cases.

This explicit profile qualifies bounded read behavior for `account/rateLimits/read`,
`account/usage/read` and `account/workspaceMessages/read` against immutable Codex
`rust-v0.163.0`. The real executable produces every app-server response; only its
account backend is synthetic. This is not live ChatGPT authentication, production
billing or external account-service acceptance.

The pinned source commit is `83086188ae0614bd882818ff1aa23f3194962012`; executable
SHA256 is `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Run from `apps/samgita_codex_driver` in the verified Elixir environment:

```sh
MIX_ENV=test CODEX_BINARY=/absolute/path/to/pinned/codex \
  mix test test/native_account_metadata_profile.exs --seed 501432
```

The explicit filename avoids default test discovery because Linux, `unshare`,
`ip` and permitted private user/network namespaces are required. Missing
isolation fails; there is no skip, host-network fallback or elevated permission.
The native environment is allowlisted, with disposable home/config/auth/tmp and
a synthetic model catalog. Its namespace differs from the caller, permits only
loopback interfaces/routes and has no default route. The fixture reuses the
metadata profile's configuration and synthetic-auth helpers without editing it.

The native bridge permits only initialization, the three account reads and
loaded-thread discovery. HTTP permits the corresponding account GET routes,
reset-credit detail GET and narrow startup metadata. The only POST is the
source-defined read-only `/backend-api/wham/usage/thread_usage/query`, requiring
one canonical, fixed synthetic thread ID. Every other route/mutation is denied.
No login, logout, credit redemption, email, turn, model, command, tool or other
execution is authorized. Synthetic auth headers enter journals only as verified
booleans. Tests check canary secrecy and reaping of owned native, controller and
namespace-owner processes before deleting fixture directories.

Ten native cases cover:

- Rate-limit quota/multi-limit mapping, window rounding, reset-credit details,
  timestamp conversion and unknown credit enums.
- Detail-request failure and malformed timestamp fallback to the usage count,
  explicit exclusion of the detail lookup, and reserve-support header selection.
  The reserve header reaches only the synthetic peer; no real experiment,
  billing event, reserve application or credit redemption occurs.
- Account/user identity checks on backend-owned banners and ordinary-usage
  permission; missing quotas remain null and never imply permission to recover.
- Native errors for rate-limit 429, 500, 403, 401 and malformed backend data.
- Profile-stat/daily-bucket projection, nullable statistics and fresh repeat
  reads; profile errors remain explicit rather than becoming zero usage.
- Canonical thread IDs and filtered thread usage fields; 403/404 make thread
  usage unavailable, while 429/500 and omitted requested rows remain errors.
  Invalid IDs reject before backend access.
- Known/unknown workspace-message types, untrusted text preservation, RFC3339
  timestamp conversion, nullable dates, empty responses and fresh repeat reads.
- Workspace-message 404 alone means unavailable feature; 401/403/429/500 and
  malformed timestamps remain errors. Requests explicitly carry `no-store`.
- Missing-account authentication rejects all reads before account-backend access.
- API-key-only authentication rejects all hosted-account reads before access.

The selected native read paths do not emit account lifecycle or rate-limit
notifications. This unit claims no notification qualification. Repeated reads
observe current fixture data and HTTP counts; it invents no account cache or
retry behavior. Account snapshots and backend banners confer no Samgita Project
authorization, work acceptance or Task acceptance.

Pinned source references relative to `codex-rs/`:

| Contract | Source |
| --- | --- |
| Authentication, quota projection, identity restrictions and reset-detail policy | `app-server/src/request_processors/account_processor.rs:1192-1297` |
| Profile/thread usage, canonical IDs and route-unavailable handling | `app-server/src/request_processors/account_processor.rs:1301-1395` |
| Workspace reads, 404 feature handling and projection | `app-server/src/request_processors/account_processor.rs:1397-1478,1536-1580` |
| Best-effort reset-credit details and enum/timestamp projection | `app-server/src/request_processors/account_processor/rate_limit_resets.rs:10-48,114-184` |
| Native account wire types | `app-server-protocol/src/protocol/v2/account.rs:315-509,664-797` |
| Usage/reset-credit reads and explicit reserve-support header | `backend-client/src/client/rate_limit_resets.rs:23-89,124-139` |
| Profile URL, workspace `no-store`, route construction and snapshot projection | `backend-client/src/client.rs:412-426,567-580,615-688,729-755` |
| Strict bounded thread-usage read query | `backend-client/src/client/thread_usage.rs:61-123` |
| Upstream native rate-limit examples | `app-server/tests/suite/v2/rate_limits.rs:45-485` |
| Upstream native thread-query examples | `app-server/tests/suite/v2/account_thread_usage.rs:30-122,193-264` |

Validation on 2026-10-24 used `main` at
`4171dfe0a6dcf3b5e85fb5eca08da6d56431aefb` plus these three new files. Commands
ran serially in `devenv shell --no-tui --` from the driver directory:

```sh
mix format test/native_account_metadata_profile.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  mix test test/native_account_metadata_profile.exs --seed 501432
MIX_ENV=test CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  mix test test/native_account_metadata_profile.exs --seed 987654
mix format --check-formatted
```

Warnings-as-errors compile and format passed. Both native runs passed **10 tests,
0 failures**, with no skips. Python AST parsing and `git diff --check` also
passed. Logs are `/tmp/samgita-native-account-metadata-501432-initial.log` and
`/tmp/samgita-native-account-metadata-987654.log`. No repair rounds were needed.
Every test confirmed owned native/controller/namespace process reaping before
removing its synthetic credential directory. No platform/database or external
service was required or contacted.

This establishes the scoped native read behaviors above. Live account/backend
changes, FedRAMP/alternate authentication, timeout timing, other transport/OS and external
service profiles remain unqualified. A11 remains a separate platform blocker.
No publication, deployment or full-compatibility claim is made.
