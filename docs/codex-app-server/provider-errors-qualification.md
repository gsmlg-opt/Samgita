# Native provider retry and terminal turn errors

The later [terminal-error continuation](managed-errors-qualification.md) adds
four real-native SSE error cases alongside all nine retained provider cases.
The complete ten-file block passes49/0 at both fixed seeds. Exact rich policy
details, context exhaustion, blank-message fallback and other classification,
failed history and caller-explicit recovery have scoped positive evidence;
no genuine provider enforcement or whole error lifecycle is qualified.

Stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
passes **3 tests / zero failures** at seeds `501432` and `987654`, in
6.0/6.6 seconds. The independent driver connects over a Unix socket to an owned
native app-server in a private network namespace. Fixed provider Responses SSE
data exercises actual native error classification, bounded sampling retry,
terminal completion and an explicit next turn. No running Samgita is required.
Six selected schema contracts gain scoped implemented evidence; **0 verified**.
The complete compatibility goal remains incomplete.

## Actual native behavior

Line references are in
`apps/samgita_codex_driver/test/native_provider_errors_test.exs` after formatting.
Request retries are disabled; stream retry budget is one. The synthetic provider
uses HTTP SSE rather than the provider WebSocket profile, and supplies no retry
advice. Test lines 138–199 compare complete native errors and turn outcomes:

| Scenario | Initial provider requests | Native error notifications | Initial turn |
| --- | ---: | --- | --- |
| `rate-recovered` | 2 | One `willRetry: true`, message `Reconnecting... 1/1`, `responseStreamDisconnected` with null `httpStatusCode`, original rate error in `additionalDetails`. | Completed with null error and exactly one final assistant item. |
| `rate-exhausted` | 2 | Same retry notice, then `willRetry: false` and `rateLimitExceeded`. | Failed; the exact terminal error also appears in `turn/completed`, with no assistant item. |
| `overload-terminal` | 1 | No retry notice despite available budget; `willRetry: false` and `serverOverloaded`. | Failed; native message is `Selected model is at capacity. Please try a different model.`, replacing the provider's arbitrary overload text. |

The terminal rate message is exactly
`rate limit exceeded: Owned provider rate limit.`. Terminal errors have explicit
null `additionalDetails` and `misalignment`; retry details contain the original
rate message. Every error is a notification with the original thread and turn
IDs. The first and second provider input arrays are identical in retry cases,
so retry does not append duplicate caller/tool/output content (lines 146–167).
The driver remains ready with zero pending, interaction and uncertain state
after each terminal result (line 202).

Each case then issues a **new explicit** `turn/start` with a distinct native turn
ID. Exactly one additional provider request completes that turn with null error,
no error notifications and one exact assistant answer (lines 204–225). The
fixture accepts the original plus explicit follow-up caller markers and rejects
extra or authenticated inference. This qualifies explicit recovery and no
driver-initiated replay within these assertions. It does not qualify protocol
reconnect, cancellation or cold history recovery. No tool executes.

## Exact candidate scope

Only these six IDs are mapped to the behavior above. The string enum as a whole
and other error families are not promoted:

| Candidate ID | Evidence |
| --- | --- |
| `schema:ServerNotification.json#/definitions/CodexErrorInfo/anyOf/0/enum/3` | Actual terminal `rateLimitExceeded`. |
| `schema:ServerNotification.json#/definitions/CodexErrorInfo/anyOf/0/enum/5` | Actual terminal `serverOverloaded` without retry advice. |
| `schema:ServerNotification.json#/definitions/CodexErrorInfo/anyOf/3` | Actual intermediate `responseStreamDisconnected` object. |
| `schema:ServerNotification.json#/definitions/CodexErrorInfo/anyOf/3/properties/responseStreamDisconnected` | Same native retry object. |
| `schema:ServerNotification.json#/definitions/CodexErrorInfo/anyOf/3/properties/responseStreamDisconnected/properties/httpStatusCode` | Explicit null only; no positive HTTP status profile. |
| `schema:ServerNotification.json#/definitions/TurnError/properties/additionalDetails` | Original underlying rate error on retry; explicit null on terminal errors. |

## Isolation, fixture and pinned source

The test hash-checks the binary, uses disposable roots and an empty inherited
environment, and asserts a distinct network namespace, only loopback, and no
IPv4 or IPv6 default route (lines 14–96). Owned controller, namespace owner and
native PIDs must be reaped on cleanup (lines 76–85). The separate namespace
prerequisite also passes. The read-only thread uses `experimentalApi: false`;
unexpected server requests fail the test (lines 115–129, 252–255).

`scripts/codex/provider_error_fixture.py:18–64` emits only provider Responses
events: `response.created`, then `response.failed` or fixed successful output.
It always returns HTTP **200** with `text/event-stream`. It never manufactures
app-server errors, thread IDs or turn completion. Codex owns classification,
retry policy and lifecycle output. **This is not an actual HTTP 429 test**, and
does not establish Retry-After handling, positive `httpStatusCode` behavior,
hosted-provider availability, authentication or account quota enforcement.

Relevant immutable paths, relative to pinned `codex-rs/`:

- `codex-api/src/sse/responses_error.rs:26–43,87–97` and
  `codex-api/src/api_bridge.rs:22–66` parse and map rate/overload failures.
- `protocol/src/error.rs:438–455,488–495` distinguishes bounded rate retry from
  overload without advice and maps terminal error classifications.
- `core/src/responses_retry.rs:87–91,120–176` bounds stream retries;
  `core/src/session/mod.rs:5277–5296` normalizes retry notices to
  `responseStreamDisconnected` while retaining the original display detail.
- `app-server/src/bespoke_event_handling.rs:1058–1075,1501–1532,1616–1640`
  keeps retry notices out of terminal error state, records terminal summaries
  and sets failed completion. Source corroboration does not broaden the tested
  Linux/Unix-socket/synthetic-provider profile.

## Reproduction and limitations

The coordinating agent ran these commands in verified Devenv, from
`apps/samgita_codex_driver`, with `MIX_ENV=test` and the hash-checked binary:

```sh
mix compile --warnings-as-errors
mix format --check-formatted test/native_provider_errors_test.exs
mix test test/native_provider_errors_test.exs --seed 501432
mix test test/native_provider_errors_test.exs --seed 987654
```

Root `mix credo --strict` passed across 361 files. Command results, durations,
namespace proof and executed-source hashes are recorded in
`/tmp/samgita-native-provider-errors-v2-20261024/`. Current test/fixture hashes
match `source.json`. The initial run failed all three cases before
`Session.initialize`: the draft UnixSocket option was `path` instead of the
documented `socket_path`. Correcting that key enabled the runs above; no runtime
implementation, assertion or deadline changed. This document's author reviewed
the final sources and logs; the coordinating agent ran executable checks.

Remaining error, retry, transport-loss, approval, OS, external-service and
platform profiles stay incomplete; A11 remains blocked. No row gains verified
status. No full compatibility, real provider/Sigma/Synapsis integration,
publication, release, production readiness or deployment is claimed.
