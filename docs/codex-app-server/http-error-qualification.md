# Native provider HTTP errors and explicit recovery

Six new cases send actual loopback HTTP failures to stock Codex
`rust-v0.163.0`; the native binary classifies the response and emits every
app-server error. This extends the three retained HTTP-200/SSE failure cases,
whose test bodies, startup/cleanup and deadlines remain unchanged.
The source pin is `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Fixed provider response | Native terminal info | Initial provider requests |
| --- | --- | --- |
| HTTP 429, generic code, no advice | responseTooManyFailedAttempts, status 429 | 1 |
| HTTP 429, insufficient_quota | usageLimitExceeded | 1 |
| HTTP 429, flex_unavailable | flexUnavailable | 1 |
| HTTP 503, server_is_overloaded | serverOverloaded | 1 |
| HTTP 500 | internalServerError | 2 |
| HTTP 403, generic code | httpConnectionFailed, status 403 | 2 |

`native_provider_errors_test.exs:220-356` requires exact native messages, error
maps and thread/turn identities, the actual provider HTTP-response journal,
request counts and retry flags. InternalServerError drops the original status;
its retry notice therefore has explicit null status. HTTP 403 preserves 403 in
retry and terminal errors and includes the exact owned provider URL. Failed
turns produce no assistant output and leave no pending/uncertain client state.

`request_max_retries=0` and `stream_max_retries=1` are unchanged. The two-request
cases are native sampling retries, not Session reconnect or replay of turn/start.
Only a new explicit caller turn succeeds, with exactly one additional HTTP 200
SSE request. Generic HTTP 429 is a failed turn, never successful delivery. There
is no Retry-After/advice or actual external quota/authentication acceptance here.

Pinned classification and native retry sources are
`codex-api/src/api_bridge.rs:22-47,95-122,181-258,343-355`,
`protocol/src/error.rs:164-188,406-455,486-555,604-657,684-701`,
`codex-client/src/retry.rs:88-117`, and
`core/src/responses_retry.rs:87-91,141-175`. Synthetic dependencies and the owned
native listener remain inside an isolated network namespace with loopback only,
no default IPv4/IPv6 route and no provider credentials.

All nine provider cases plus two persisted-tool cases passed both seeds
`501432` and `987654` in verified Devenv with the pinned CODEX_BINARY. The first
combined run also contains two independently failing MCP fixture drafts:
**13 tests / 2 failures** overall; none of these eleven cases failed. The second
run was **11/0**, 21.0s. Exact commands, complete logs and exits are retained in
`/tmp/samgita-native-followup-units-20261024/`. Compilation and scoped formatting
passed before the native run. Final combined/static/hosted checks remain required.

Only nine previously missing CodexErrorInfo contracts receive scoped implemented
evidence: the three new string alternatives and the two structured HTTP-status
branches with their member/status fields. Existing overload, disconnected status
and additionalDetails evidence gains the narrower HTTP explanation. No broader
error family, other deployment profile, real quota/security enforcement, A11 or
complete compatibility is qualified; no entry is promoted to fully verified.
