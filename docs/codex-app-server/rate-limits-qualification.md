# Native response-header rate-limit notification qualification

Six actual-binary cases passed locally at seeds `501432` and `987654` on
2026-10-24. They qualify native response-header parsing and notification
propagation from a fixed synthetic provider. They do not establish real account
quotas, rate enforcement, hosted conformance or complete compatibility.

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`; Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source baseline: Samgita `403607ca405702475c86e01840fe090bd23f4f53`.
The bounded implementation is:

- `apps/samgita_codex_driver/test/native_rate_limits_test.exs`
- `scripts/codex/rate_limits_fixture.py`
- This document.

The fixture is an HTTP Responses/SSE model-provider peer. It sends real HTTP
response headers and fixed assistant text; it never constructs app-server
notifications. Only the actual pinned binary emits `account/rateLimits/updated`
over the borrowed Unix socket. No live account, paid model, tools, shell action,
MCP, real credential, platform database or sibling-service integration is used.

## Source contract

Paths below are relative to the pinned `codex-rs/` source root.

| Contract | Production source |
| --- | --- |
| Default and additional-family parsing/normalization | `codex-api/src/rate_limits.rs:22–109` |
| Finite windows, empty-zero suppression and optional integer parsing | `codex-api/src/rate_limits.rs:195–220,237–275` |
| Two required boolean credit headers, string balance trimming | `codex-api/src/rate_limits.rs:222–235,252–263` |
| Header snapshots forwarded before SSE processing | `codex-api/src/sse/responses.rs:37–38,76–79` |
| Core records snapshots before token-count fanout | `core/src/session/turn.rs:3056–3061,3291–3297` |
| Latest snapshot and sparse account-metadata merge | `core/src/state/session.rs:351–362,439–467` |
| Token-count event production | `core/src/session/mod.rs:5155–5159,5180–5188` |
| Actual app-server notification emission | `app-server/src/bespoke_event_handling.rs:1589–1613` |
| Stable notification wire declaration | `app-server-protocol/src/protocol/common.rs:2020` |
| Sparse wire fields, optional unavailable values, native integer rounding | `app-server-protocol/src/protocol/v2/account.rs:650–696,752–792` |

Important pinned behavior: `parse_default_rate_limit` returns a codex snapshot
even if every header is absent or malformed. Empty inputs therefore permit an
actual all-null default update; do not assert notice absence or synthesize quota
values. Additional families, unlike the default, require real window/credit
data. Header-family names are normalized from hyphens to underscores in limitId.
All parsed snapshots are stored before the later token-count event, so multiple
families in one HTTP response do not promise a separate notice per family. The
alternate case asserts the final native snapshot, not a manufactured fanout.

Core window percentages are floating point, but the public wire rounds them to
signed i32. These cases expect 12.5→13, 99.49→99, 42.5→43 and 2.49→2. A zero
window with no reset/duration data is suppressed; a zero reset timestamp is
present data and keeps a zero-percentage window. Negative reset timestamps are
parsed native integers, not assertions about useful quota dates.

This route always leaves normalModelSlug, individualLimit, spendControlReached,
planType and rateLimitReachedType null in an isolated fresh session. Their
positive schema variants are **not reachable through these headers**. Unsupported
lookalike headers cannot invent them. Native nulls are sparse unavailable facts,
not instructions to clear previously known account values. WebSocket
`codex.rate_limits` parsing (`codex-api/src/endpoint/responses_websocket.rs:859`
and `rate_limits.rs:135–176`) is a separate unqualified producer path; putting a
fake event with that name into SSE would not qualify it.

## Six native cases

| Case | Assertions | Runtime status |
| --- | --- | --- |
| Named default windows, stable negotiation | Both windows, native rounding, trimmed quota name/decimal balance, true/false credits; unchanged account-only envelope | Passed both seeds |
| Alternate family, experimental negotiation | Normalized codex_other identity, default superseded before fanout, primary nullable duration with reset zero, secondary negative reset and rounding, invalid extra family omitted | Passed both seeds |
| Credits only | Absent windows, false/true credit booleans, blank balance becomes null | Passed both seeds |
| Sparse primary | Nonzero percentage with malformed duration/reset produces nullable metadata; fully zero secondary disappears; malformed credit boolean and blank name unavailable | Passed both seeds |
| Malformed/nonfinite | NaN/inf windows, malformed/overflow metadata and invalid booleans do not fabricate fields; default sparse-null notice remains; unknown account-like headers ignored | Passed both seeds |
| No rate-limit headers | Default codex identity and every nullable field explicitly null, with genuine native notice | Passed both seeds |

Each case owns one independent native process/session and exactly one fixed
text-only provider request. Request count must stay one in the test and cleanup;
a wrong input, Authorization header or second request records a failure marker.
The test collects through actual correlated completed turn, requires known-schema
notification kind, compares every received rate-limit update exactly, and checks
ready driver status with zero pending/uncertain calls or interactions. It does
not assume rate-limit notification cardinality: token-usage fanout can report
the latest snapshot more than once. No raw-event opt-in is required.

## Isolation and boundaries

The fixture reuses the reviewed owned-controller primitives without shared-file
edits. Each case owns scratch HOME/CODEX_HOME/workspace/tmp and a shell copy.
Native/controller/provider live in a private Linux user/network namespace with
loopback only and no IPv4/IPv6 default route. Explicit environment inheritance
excludes real credentials, provider auth is disabled, and the peer rejects an
Authorization header. Hooks, shell tools, unified exec, remote models/control,
apps/plugins, web search and shell snapshots are disabled. Unexpected native
server requests fail; item types are restricted to user/assistant messages.

The five-second startup, completion and cleanup barriers match existing native
profiles. Session closes its borrowed connection; Stdio owns only the fixture
controller, which terminates/reaps its native child. Cleanup verifies every
recorded native/controller/namespace-owner PID disappeared. No unrelated process
is signalled and no automatic resend follows a timeout/disconnect. A private
configuration-comment canary must be absent from collected native wire frames
and provider requests. This bounded scan does not establish logging/telemetry
confidentiality or close A11. Synthetic quotas prove decoding and propagation,
not real account entitlement, rate enforcement, billing, hosted conformance,
full compatibility, publication or deployed behavior.

## Validation and curated evidence

The coordinator installed the source-reviewed draft with an exclusive,
cryptographically random scratch root, then ran these commands serially in
verified Devenv. Nonimporting Python AST and namespace preflight passed:

```sh
python3 -c 'import ast; from pathlib import Path; p=Path("scripts/codex/rate_limits_fixture.py"); ast.parse(p.read_text(), filename=str(p)); print("AST passed; fixture not imported")'
python3 scripts/codex/check_namespace_prerequisites.py
```

From `apps/samgita_codex_driver`, with `MIX_ENV=test` and CODEX_BINARY set to the
absolute pinned binary (no model/provider credential environment inheritance):

```sh
mix format test/native_rate_limits_test.exs
mix compile --warnings-as-errors
mix test test/native_rate_limits_test.exs --seed 501432
mix test test/native_rate_limits_test.exs --seed 987654
mix format --check-formatted test/native_rate_limits_test.exs
```

At root in the same environment:

```sh
MIX_ENV=test mix credo apps/samgita_codex_driver/test/native_rate_limits_test.exs --strict
```

Both seeds passed **6 tests / zero failures**, 9.9 seconds each after the final
test-only refactor. Compile, format and strict Credo passed. Initial native runs
also passed 6/0, 10.0/9.9 seconds; strict Credo then reported complexity 10
(maximum 9). Extracting the unchanged completed-turn/item assertions into one
helper resolved it. Both native seeds and static checks were repeated on that
source. No runtime/deadline/assertion change or native repair was needed.

The notification entry gains `implemented` evidence, together with exactly
15 directly positive schema contracts: `rateLimits`; snapshot `limitId`,
`limitName`, `credits`, `primary`, `secondary` and the three non-null object
branches; credit `balance`, `hasCredits`, `unlimited`; window `usedPercent`,
`windowDurationMins`, `resetsAt`. The test's exact expected maps assert every
observed rate-limit update. Null-only account fields and null schema branches
remained missing at that checkpoint. The later
[fourteen-owner source-attribution index](notification-owner-supplement-qualification.md)
adds eleven exact explicit-null properties/alternatives from the unchanged full
native-map assertions; positive account variants remain missing and no entry is
fully verified. Other transport/OS/race/replay,
WebSocket rate-limit producers, real backend and gateway/user-verification
profiles remain incomplete.

Local runner: `/tmp/samgita-rate-limits-validation-20261024.py`; final command
log `/tmp/samgita-rate-limits-final-validation-20261024.log`, with per-command
`/tmp/samgita-rate-limits-*-20261024.log` files. The initial strict check is
preserved in `/tmp/samgita-rate-limits-credo-initial-20261024.log`. Exact-one
request, no unexpected input/tool, known notification, thread/turn/item,
canary and all owned-process reaping assertions passed in both final runs.
Subsequent full-source aggregate/hosted checks are recorded separately.
