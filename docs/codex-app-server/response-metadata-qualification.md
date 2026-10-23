# Native Responses metadata notification qualification

Four local native cases pass with two seeds against the immutable target below.
All app-server notifications originate from native Codex; the provider is an
isolated deterministic Responses peer. This does not establish full Codex
compatibility, hosted qualification, real account/provider success, publication
or deployment. Sol repairs 1 / Astra repairs 0.

## Target and ownership

Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`; Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Initial source baseline: Samgita `e82f32f`. Independent work is in progress in
shared manifests and account-control files; this unit changes only:

- `apps/samgita_codex_driver/test/native_response_metadata_test.exs`
- `scripts/codex/response_metadata_fixture.py`
- This document.

The Python fixture is a Responses HTTP/SSE peer, not an app-server emulator.
Native Codex consumes its metadata and generates all app-server messages over
a borrowed Unix socket. Stdio owns only the fixture controller. Each scenario
allows exactly one fixed synthetic user input and one fixed assistant text
response. A second request or wrong synthetic input records a failure marker
and fails. No tool, hook, shell, MCP, credential, external model, paid request,
platform database or sibling-service integration is exercised.

## Cases and expected native evidence

| Case | Expected observations | Runtime |
| --- | --- | --- |
| Rich metadata | Correlated raw response/item; exact nonzero synthetic token breakdown; usage amount preserved and metadata replaced by original usage; model mismatch reroute; filtered/deduplicated verification; exact arbitrary moderation JSON; three safety updates covering explicit model, header fallback and explicit null | Passed both seeds |
| Null usage and invalid metadata | Explicit null usage/usageMetadata; assistant optional status/phase omitted; matching model case-folds without reroute; unknown verification, misplaced metadata and malformed/false safety payloads produce no corresponding notice | Passed both seeds |
| Nullable metadata | Null usage with a non-null usageMetadata object whose amount/metadata are explicit null; arbitrary moderation JSON explicitly null remains an actual native notification | Passed both seeds |
| Stable connection | Reroute, verification and safety notices remain; experimental moderation is suppressed when experimentalApi is false and raw notices are absent without thread opt-in | Passed both seeds |

The six target entries are `rawResponse/completed`, `rawResponseItem/completed`,
`turn/moderationMetadata`, `model/rerouted`, `model/verification` and
`model/safetyBuffering/updated`. All six were genuinely emitted; curated schema
assertion mappings remain the coordinating agent's responsibility. No entry is
claimed verified. The assistant message variant is the only raw response-item
variant targeted here; input/context raw items may also be observed and do
not qualify all other variants.

Model mismatch is a synthetic reported-model header differing from the owned
requested model. Native Codex hardcodes `highRiskCyberActivity` for this
mismatch. That value is protocol behavior, not evidence of actual account
flags, risk assessment or a real routing decision. Verification metadata is
synthetic; no human verification or entitlement is established.

The fixture sends two valid verification metadata events, with duplicates,
unknown strings and a non-string mixed into the first list. The parser removes
unknowns/duplicates; the core emits only once per turn. Safety buffering always
sets `showBufferingUi` true in the pinned parser. No false branch is claimed.
Explicit `retry_model` takes precedence over the response header, including
explicit null; only omission uses the header fallback.

Raw notifications additionally require `thread/start.experimentalRawEvents`.
The three experimental scenarios set it explicitly with experimentalApi true.
The stable connection omits it; the raw-event barrier is asserted only for
opted-in threads. This separates per-thread raw-event opt-in from outbound
experimental-notification filtering. Stable results prove neither raw success
nor moderation success.

For usage, native preserves the amount string but replaces
`usageMetadata.metadata` with the exact non-null upstream `usage` object.
Non-null token fields are independently mapped into camelCase wire fields.
With null usage, an absent metadata object becomes explicit null, while an
explicit object with null fields remains an object. No billing, cost accuracy
or production accounting is established by these synthetic numbers.

## Isolation, secrets and lifecycle

The fixture reuses the existing owned controller/configuration primitives.
Each case creates disposable HOME, CODEX_HOME, workspace, tmp and shell copy;
native/controller/provider live in a private Linux user/network namespace
with loopback only and no IPv4/IPv6 default route. An explicit environment
allowlist excludes existing credentials. All provider/account destinations are
the owned loopback peer; authentication is disabled. Shell tools, unified
execution, remote models/control, hooks, apps/plugins and shell snapshots are
disabled. A fixture text response cannot request a tool.

Unexpected native server requests fail. Item lifecycle assertions allow only
user/assistant message types. Completed native turn, response ID, thread/turn
correlation and, for opted-in scenarios, the actual assistant raw item are
required within unchanged five-second barriers. Cleanup closes the borrowed Session, stops the owned
controller, requires exactly one recorded provider request and no failure
marker, and proves recorded native/controller/namespace-owner PIDs disappeared.
No unrelated process is signalled.

A fixed private canary appears only in an owned configuration comment.
Every collected wire frame and recorded provider request is scanned to exclude
it. This is a bounded accidental-config-disclosure assertion, not proof of
credential redaction or closure of A11/telemetry/logging confidentiality.
No real credentials are used. Native standard output/error remain discarded by
the existing controller; no unsupported logging guarantee is inferred.

## Exact pinned source anchors

All paths are relative to the immutable `codex-rs/` tree.

| Contract | Source |
| --- | --- |
| HTTP model and safety headers | `codex-api/src/sse/responses.rs:37-79`; `codex-api/src/safety_buffering.rs:4-20` |
| Metadata kind checks, arbitrary moderation JSON and safety precedence | `codex-api/src/sse/responses.rs:221-265` |
| Verification filtering/deduplication and recognized value | `codex-api/src/sse/responses.rs:292-324` |
| Metadata dispatch before ordinary SSE processing | `codex-api/src/sse/responses.rs:605-639` |
| Raw usage metadata replacement | `codex-api/src/sse/responses.rs:450-466` |
| Core verification once per turn, moderation/safety dispatch | `core/src/session/turn.rs:3027-3060` |
| Native mismatch hardcoded reason and verification/moderation emitters | `core/src/session/mod.rs:4091-4149` |
| Raw item and raw completion core emitters | `core/src/session/mod.rs:4391-4400,4990-5008`; `core/src/session/turn.rs:3092-3098` |
| App-server metadata mapping | `app-server/src/bespoke_event_handling.rs:400-447` |
| Raw item warehouse metadata removal and optional media omission | `app-server/src/bespoke_event_handling.rs:1167-1194` |
| Experimental moderation declaration/filter | `app-server-protocol/src/protocol/common.rs:2035-2036`; `app-server/src/transport.rs:104-125` |
| Experimental raw thread opt-in and both raw-event filters | `app-server-protocol/src/protocol/v2/thread.rs:161-165`; `app-server/src/thread_state.rs:601-628`; `app-server/src/request_processors/thread_lifecycle.rs:340-357` |
| Native output schemas | `app-server-protocol/src/protocol/v2/model.rs:187-228`; `app-server-protocol/src/protocol/v2/thread.rs:1945-2020`; `app-server-protocol/src/protocol/v2/item.rs:1433-1437` |

Auth recovery is deliberately outside this unit. `core/src/client.rs:2746-2801`
requires provider lifecycle messages and a real recovered result; the default
trait returns no messages/NotConfigured (`model-provider/src/provider.rs:180-188`).
Only Bedrock's production override was found, gated on credential export or
configured AWS profile/SDK and a recovery helper
(`model-provider/src/amazon_bedrock/mod.rs:158-165,330-390`). Returning 401 from
a credential-free custom Responses peer cannot prove those notifications.

## Validation

The parent granted the exclusive runtime slot. CODEX_BINARY was the absolute
pinned binary path; namespace preflight and all Mix commands ran in the
verified Devenv environment with `MIX_ENV=test`. All owned processes were
reaped and the slot released after the commands completed.

```sh
python3 -c 'import ast; from pathlib import Path; p=Path("scripts/codex/response_metadata_fixture.py"); ast.parse(p.read_text(), filename=str(p)); print("AST parse passed; fixture not imported")'
python3 scripts/codex/check_namespace_prerequisites.py
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix credo apps/samgita_codex_driver/test/native_response_metadata_test.exs --strict
```

From the standalone driver directory:

```sh
MIX_ENV=test mix format test/native_response_metadata_test.exs
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test test/native_response_metadata_test.exs --seed 501432
MIX_ENV=test mix test test/native_response_metadata_test.exs --seed 987654
MIX_ENV=test mix format --check-formatted test/native_response_metadata_test.exs
```

Python non-importing AST, namespace preflight, driver/root warnings-as-errors
compile, scoped format and scoped positional strict Credo all passed. Both
seeds 501432/987654 passed four tests, zero failures, in 6.6 seconds each.
Every test's exact-one-request, unexpected-request, item-type, canary and owned
PID cleanup assertions passed. Source baseline remained `e82f32f` when work
began; shared HEAD advanced independently while this unit was uncommitted.

The initial run failed all four tests at the original five-second raw-event
barrier (25.1 seconds total): connection experimentalApi alone did not opt the
thread into raw events. Source review found the separate gate above. Repair
one enabled native thread opt-in only for the three experimental scenarios
and preserved the stable scenario as explicit absence coverage. No deadline
or positive raw-field assertion was weakened. The stable connection now
expects its actual three stable metadata notices and a completed fixed text
turn, while explicitly rejecting raw/moderation notices. No further repair
was needed.

Local logs: `/tmp/samgita-response-metadata-initial.log` and
`/tmp/samgita-response-metadata-repair1.log`. They are local evidence, not
published artifacts. No manifest, workflow, publication or deployment action
belongs to this unit.
