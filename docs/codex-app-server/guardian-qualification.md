# Guardian native behavior qualification

Three actual-binary cases pass at seeds `501432` and `987654`, 5.0 seconds each,
against official Codex
`rust-v0.163.0`, immutable source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl binary SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Python AST, namespace preflight, warnings-as-errors compile, format and scoped
strict Credo pass. These are selected native observations against a synthetic
dependency, not real risk assessment or complete Guardian qualification.

The missing methods/notices are real production paths at this pin. Existing
`approval_decision_variants_test.exs` and the approval cases in
`real_session_test.exs` exercise user command/file/permission request decisions.
They do not enable Guardian automatic review, observe its warnings/review pair,
or call `thread/approveGuardianDeniedAction`. This draft does not repeat those
user-approval cases.

## Contract and source reachability

All source anchors below are relative to pinned `codex-rs/`.

- `app-server-protocol/src/protocol/common.rs:744` declares the stable client
  method and correlated empty result. `:1987` declares the review-started/
  completed pair; `:1989` marks only the strict-review notice experimental;
  `:2039` declares `guardianWarning`. The review payload is still documented as
  unstable in `app-server-protocol/src/protocol/v2/item.rs:554`; a nonexperimental
  wire declaration is not a promise of future payload stability.
- `app-server/src/request_processors/thread_processor.rs:2596` deserializes
  the method's arbitrary JSON `event` into the **raw snake_case** core
  `GuardianAssessmentEvent`, loads the thread, checks direct-input eligibility,
  submits the core operation and returns `{}`. A nested malformed denial fails
  native deserialization; an unknown/restricted child thread fails its own
  authority boundary. This draft's positive case uses the actual native denied
  review identity/action, never a fabricated privileged command.
- `core/src/session/handlers.rs:757` ignores non-denied events. A denied event
  becomes a developer `GuardianApprovedAction` fragment containing the action
  and `outcome: allowed`. `core/src/session/inject.rs:174` inserts into active
  work or records it without starting a turn. This RPC does not validate a
  Samgita task transition, grant a project role, immediately reexecute the tool,
  or act as a durable idempotency receipt. The native response acknowledges core
  submission; it is not proof that execution happened. Native does not reconcile
  the supplied denial ID/action against prior denial history. Exact event matching
  in this fixture is its own safety restriction, not native authorization proof.
  Do not blindly retry it
  after an ambiguous disconnect.
- `core/src/context/guardian_approved_action.rs:42` renders the exact-action
  approval instruction. The test then explicitly starts a new text-only turn
  and checks that the real provider request contains that developer fragment.
  It asserts that no MCP tool call or implicit turn was launched by the RPC.
- `protocol/src/approvals.rs:206` defines the raw denial event; the public
  notification action and review fields use camelCase instead. The fixture and
  test explicitly translate those known fields, preserving actual review ID,
  target item, turn ID and timestamps. They do not assume the notification is
  itself the raw event representation.
- `ext/guardian-reviewer/src/routing.rs:55` selects automatic review only under
  the appropriate policy/reviewer; full access bypasses review. The fixture uses
  `on-request`, `auto_review`, read-only and one prompt-approved owned MCP tool.
- `ext/guardian-reviewer/src/review.rs:93` prepares and emits started, evaluates
  the bounded reviewer, emits a warning where appropriate, then terminal review.
  `completion.rs:121` maps cancellation to aborted/no warning; `:165` maps a
  valid denied result to the warning and denial. The owned provider returns the
  exact fixed JSON assessment with high risk and unknown authorization; this
  tests Codex routing/parsing/reporting, not real risk assessment quality.
- `app-server/src/bespoke_event_handling.rs:284` emits the warning.
  `item_builders.rs:270` creates started/completed public payloads from the same
  review identity. `bespoke_event_handling.rs:350` emits strict review only for
  ElevatedRisk, StaleScore, IncompatibleCompaction, ScoringFailure or
  AuthorizationChanged. Policy, MissingScore and FreshRequired are insufficient.

## Observed bounded strict-review fallback

The draft uses **ScoringFailure from an oversized action**, not a fabricated
classifier score. `ext/guardian-v2/src/async_scorer/extension.rs:118` installs
score progress. `approval.rs:169` obtains that progress; `:174` compares the
complete action against `max_action_tokens` and returns ScoringFailure if it
does not fit. `action.rs:21` also refuses to shorten oversized arguments into an
asynchronous classifier request. A 128-token cap and a roughly 2.4 KiB owned MCP
argument are sufficient to exceed that byte budget. The native full reviewer
still sees the action and returns the fixed denied result.

The fixture config enables Guardian V2 for all tool scopes only in this case.
It supplies no classifier responses. The optional native classifier WebSocket
prewarm receives an explicit local HTTP 426; the peer never forwards traffic or
pretends to establish a classifier session. The test requires the actual native
strict notice and correlates its thread, turn and timestamp with review-started.
If the pin does not reach that reason under the supplied configuration, the test
must fail; a generic policy review does not satisfy it. Both native runs produced
the required notice from the oversized-action path. The upstream reference
`app-server/tests/suite/v2/guardian_action_budget_tests.rs:128` uses the same cap
and all-tools scope for overflow behavior; its execution is not claimed here.

Elevated-risk success scoring, score reuse, classifier WebSocket completion,
stale score, incompatible compaction and authorization-change triggers remain
separate, unqualified branches. The previous broader audit's WS-based high-risk
proposal remains valid for that branch but is unnecessary to test this narrow
overflow fallback.

## Supplied scenarios and isolation

All three native tests pass:

1. Synchronous denial emits one started/completed pair and an explanatory
   warning, never executes the owned MCP action, and does not emit strict review.
   Reporting the actual denial as explicitly approved returns a correlated empty
   result, launches no implicit turn, and is visible as developer context only
   when the test separately starts a text-only follow-up turn.
2. A held reviewer request is interrupted: terminal review is aborted, parent
   turn interrupted, held HTTP transport released, and no warning/tool effect or
   retry occurs.
3. Bounded action overflow with experimental negotiation emits one strict notice
   and a denied full-review lifecycle. No classifier score is synthesized.

The fixture enters a private Linux user/network namespace, verifies loopback
only and no IPv4/IPv6 default route, and opens one loopback-only peer. Only fixed
`/v1/responses` provider and `/mcp` inventory routes exist. MCP has **no execution
implementation**; any native `tools/call` is recorded as forbidden and fails the
test. There are no shell, exec, patch, hook, plugin, account, auth or external
service operations. The child environment is explicit, with no inherited
credentials/proxy endpoints, and file-based credential stores are selected.
All three `/etc/codex/{config,requirements,managed_config}.toml` files cause a
closed failure instead of being inherited or modified.

App-server input is allowlisted, approval input must exactly match the observed
native denied event, wire frames are bounded at 256 KiB, HTTP bodies at 1 MiB,
native input at 24 messages, peer Responses requests at four and journal history
at 180 records. Parent/reviewer request counts, native review IDs/timestamps,
normal Session deadlines, absence of server interactions/uncertain operations,
namespace proof, private canary exclusion and owned native/controller/HTTP
cleanup are asserted. A canary in an owned config comment is scanned against
wire, peer requests, stderr and journal; no real credential is created.

## Reproduction, repair and validation

The first three native cases all timed out waiting for review. A separate owned
native diagnostic established the preceding failure: every dependency reply
raised TypeError, and native turn completion reported `error sending request`.
The fixture's Handler.responses method shadowed BaseHTTPRequestHandler.responses,
the status-code table used by send_response. Renaming the fixture-only method to
model_response fixes MCP initialization and Responses serialization. Native
protocol, configuration gates, assertions and deadlines remain unchanged.
Initial failures are preserved at
`/tmp/samgita-guardian-first-native-failure-20261024.log`; allowlisted diagnostic
events are at `/tmp/samgita-guardian-diagnosis-20261024.log`.

From the independent driver directory in verified Devenv, with `MIX_ENV=test`
and the pinned `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_guardian_profile.exs --seed 501432
mix test test/native_guardian_profile.exs --seed 987654
mix format --check-formatted test/native_guardian_profile.exs
```

Both native runs pass **3 tests / zero failures**, 5.0s each. Root scoped
`mix credo apps/samgita_codex_driver/test/native_guardian_profile.exs --strict`
passes. AST and namespace preflight pass. Final scoped logs are
`/tmp/samgita-guardian-*-20261024.log`. Cleanup fits the unchanged stdio owner
grace by releasing held sockets before native termination and bounding explicit
waits to 0.75s; PID, canary and teardown assertions pass on success and the initial
failed assertions. No production process-cleanup code changed.

Six entries and 39 positive contracts gain scoped implemented evidence. Only
the MCP action, inProgress/denied/aborted review states, high/unknown assessment
and ScoringFailure strict fallback are mapped. Null-only metadata and other
variants remain missing. CI explicitly selects this profile. Full-source
aggregate/hosted and isolated consumer checks remain separate.

These tests cannot establish live provider integration, real risk quality,
all Guardian action variants, managed enterprise policies, circuit breaking,
score caching/recovery, high-risk classifier behavior, publication or deployed
behavior. Samgita project/task acceptance remains outside this Codex UI approval
context operation.
