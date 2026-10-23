# Native feedback upload qualification

Six actual-binary scenarios passed locally on 2026-10-24 at seeds `501432` and
`987654`, 12.6/12.3 seconds. Source baseline was Samgita `403607c`. These tests
establish selected native behavior with an isolated synthetic HTTPS dependency;
they do not establish real Sentry storage or full compatibility.

The target is official Codex `rust-v0.163.0`, commit `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`. Both profile and controller enforce this binary hash. They do not modify Codex or produce app-server messages. Actual immutable Codex emits every response and notice; the owned peer supplies only HTTPS Sentry responses.

## Files and supported scenarios

- `apps/samgita_codex_driver/test/native_feedback_profile.exs`: six tests, one native process/private namespace per case, default Session deadlines preserved.
- `scripts/codex/isolated_feedback_fixture.py`: self-contained bounded CONNECT/TLS peer plus transparent native stdio bridge. No model, backend account, tool, shell command, turn or MCP endpoint.
- This document: provenance, bounds, observed validation and limits.

| Scenario | Native behavior under test | Request/effect bound |
| --- | --- | --- |
| `event` | includeLogs=false, no thread/account/files; successful HTTP acceptance returns generated no-active-thread UUID and null promptHash | Exactly one Event, no attachments |
| `extra` | Same plus one explicit owned small file despite includeLogs=false; attachment linked to core Event | One Event plus one exact-content attachment |
| `core429` | HTTP429 is an upstream error, never successful delivery | One Event, no retry or attachment |
| `core503` | HTTP503 is an upstream error; no automatic core replay | One Event, no retry or attachment |
| `partial` | Core200 then attachment503 exhaustion returns explicit partial-acceptance error | One Event plus three identical attachment attempts, same event ID |
| `held` | Three observed blocked upload HTTP requests consume three permits; fourth native RPC is overloaded; releasing three failed requests restores capacity | Three held Events, no HTTP for overload, one explicit recovery Event; four distinct event IDs |

Each call preserves the native request/response ID. These tests do not alter the default 30-second driver request deadline or native 300-second overall upload deadline. Five-second observation/shutdown bounds and the fixture's eight-second release barrier bound only owned test resources. The barrier waits for a journaled incoming upload and an explicit release file, not an assumed readiness sleep. Attachment retry timing remains native 250/500 ms.

## Isolation, transport and data limits

The controller enters `unshare --user --map-root-user --net --fork --kill-child=TERM`, brings up only loopback, verifies a different network namespace, and checks both IPv4 and IPv6 routes for no default/nonloopback route. Failure is BLOCKED_ENV; there is no fallback to the host network.

It generates an owned short-lived CA/server certificate for the exact hardcoded hostname using openssl. Only its child receives SSL_CERT_FILE and loopback HTTPS_PROXY/https_proxy. It neither changes system trust nor disables certificate validation. TLS minimum is1.2; server advertises only HTTP/1.1. The no-auth child env is built from an explicit allowlist and does not inherit real account/token/proxy/keyring variables. No auth.json is written. Primary/MCP credential storage is file-configured; gateway OAuth is not configured. All HOME/CODEX_HOME/TMPDIR/workspace paths are fresh synthetic directories.

The proxy accepts only `CONNECT o33249.ingest.us.sentry.io:443 HTTP/1.1`, never opens another network socket, and handles only the exact envelope POST path `/api/4510195390611458/envelope/`. The private network also prevents external egress if native code bypasses the proxy. Unexpected HTTP method, path, Host, proxy authorization, account headers, framing, item kind or attachment content fails the profile. Sentry's public DSN identifier is verified as source provenance; it is not an account credential.

Limits: 24 accepted connections, 16 uploads, 128 allowlisted journal events, 16 native input messages, 16KiB native JSONL and aggregate HTTP headers, 2KiB request/header line, 32 headers, 256KiB encoded body and512KiB decoded body. Gzip is decoded with an explicit output cap, complete-stream check and no concatenated/trailing streams. Exactly one length-delimited item is admitted per envelope, matching this pin's production event/attachment serializer. Request sockets have a five-second timeout. Shutdown signals only the explicitly owned process, reaps it, joins its stdio reader, closes/joins its peer, and records completion before temporary-directory removal.

The only allowed native methods are initialize, initialized, feedback/upload and thread/loaded/list. Feedback params must exactly match fixed synthetic classification/reason/includeLogs=false, with an extraLogFiles list only in extra/partial. That list must equal one explicitly created owned file; symlinks/content changes are rejected. Arbitrary filenames, tags, thread IDs, logs and account information are not admitted. The peer records allowlisted IDs, sizes, hashes, status, TLS version and verification booleans; it does not persist raw envelopes, headers, credentials or body contents. Native stderr is an owned scratch file; real credentials and private user input are excluded from this profile. Broader log/credential cases require separate review: this minimal fixture is not a general secret-redaction proof.

## Exact source provenance

Anchors below are relative to `tmp/codex/0.163.0/codex-83086188ae0614bd882818ff1aa23f3194962012/codex-rs/`.

- `app-server-protocol/src/protocol/common.rs:1371` and `protocol/v2/feedback.rs`: stable feedback/upload method and params/result fields. includeLogs defaults false; threadId/tags/extraLogFiles are optional. The draft intentionally covers only a strict subset of accepted inputs.
- `app-server/src/request_processors/feedback_processor.rs:58`: enabled-config gate, three-upload semaphore, thread validation, real prompt metadata; `:223`: explicit extraLogFiles are added independently of includeLogs; `:275`: spawn_blocking retains permit through real upload even if RPC waiter is canceled; `:310`: response follows actual uploader completion.
- `feedback/src/lib.rs:61`, `:613`: hardcoded production Sentry DSN, no supported RPC/config DSN override; private upload_feedback_with_dsn is not a production injection mechanism. `:284`: no-active-thread generated identity. `:534`: actual Event fields/tags. `:650` and `:758`: core first, then attachment loops and explicit partial-acceptance failure. Source documentation says success means HTTP acceptance, not durable attachment storage.
- `feedback/src/upload.rs:27`: actual envelope POST with X-Sentry-Auth and optional gzip; `:55`: never replay Event, at most two eligible diagnostic retries, 429 handling; `:185`: separate one-item attachment serialization.
- `app-server/tests/suite/v2/feedback.rs:103`: official test uses private HTTPS CONNECT/TLS termination to capture actual native Sentry envelopes without forwarding; `:225`: child HTTPS_PROXY and SSL_CERT_FILE overrides. `:16`: held-three-upload overload reference. Tests read as source, not executed by this worker.

No upstream app-server notifier or fake native response has been introduced. The positive response follows real production HTTP upload handling, so this differs from merely encoding a schema or injecting a fake app-server frame.

## Validation and curated evidence

After source/security review, the coordinator installed the draft with an
exclusive random scratch root and serialized all validation in verified Devenv.
The actual fixed executable performed TLS certificate validation through its
child-only CA and production CONNECT/upload path. Python AST, namespace
preflight, compile, format and scoped strict Credo passed without repair.

At root, `python3 -B scripts/codex/check_namespace_prerequisites.py` and
`MIX_ENV=test mix credo
apps/samgita_codex_driver/test/native_feedback_profile.exs --strict` passed.
From `apps/samgita_codex_driver`, with `MIX_ENV=test` and the absolute pinned
`CODEX_BINARY`, every command below passed:

```sh
mix format test/native_feedback_profile.exs
mix compile --warnings-as-errors
mix test test/native_feedback_profile.exs --seed 501432
mix test test/native_feedback_profile.exs --seed 987654
mix format --check-formatted test/native_feedback_profile.exs
```

Both native runs passed **6 tests / zero failures**, 12.6/12.3 seconds. Counts,
exact attachment bytes/hash, event identity, HTTP errors, response-sent barriers,
bounded overload, recovered capacity, no turns/server requests, empty uncertainty,
TLS/path/auth-header and owned-process shutdown checks passed. No failure,
deadline inflation, weakened assertion or replay was needed.
Local runner and results are `/tmp/samgita-single-native-unit-validation-20261024.py`,
`/tmp/samgita-feedback-validation-20261024.log` and per-command
`/tmp/samgita-feedback-*-20261024.log`. CI explicitly selects this six-case
profile; final-source hosted and aggregate results remain separate.

The request/response entries and five positive fields gain scoped `implemented`
evidence: request `classification`, `reason`, `includeLogs`, `extraLogFiles`
and response `threadId`. Null `promptHash`, omitted tags/thread input and
unexercised field/behavior variants remain missing. No entry is fully verified.

## Explicit limitations and integration questions

- Native feedback success is HTTP acceptance by a private synthetic peer, not real Sentry storage, published behavior, provider compatibility, account authorization, paid execution or deployment.
- An upstream error after core acceptance is partial-effect uncertainty for the caller even when the driver received a definite error frame. The profile asserts the real message and absence of core replay; it does not change Error.uncertain semantics or promise external rollback/exactly-once execution.
- This profile does not cover includeLogs=true, real account tags, real thread/rollout promptHash, automatic diagnostic sources, arbitrary classifications/tags/paths, huge payloads, malformed wire validation, active local deadline/disconnect cancellation, process restart mid-upload, or all attachment cooldown variants. Do not mark their field/behavior contracts passed.
- Raw telemetry A11 remains a separate blocked gate. Synthetic feedback content intentionally crosses the upload boundary; this event-only profile is not a confidentiality closure.
- No external repository/service change is needed for these six private scenarios. A future production DSN override would be a separate upstream/product request, not something this fixture silently adds.
- The source-derived envelope/header, child CA/proxy and semaphore assumptions
  passed both native seeds. Other platform and deployment profiles remain
  incomplete. Runtime Sol repair rounds 0 / Astra 0.
