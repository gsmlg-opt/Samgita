# Native current-turn settings qualification

Status: selected native implementation evidence, with full compatibility still
incomplete. Seven cases passed twice against the immutable Linux executable.
This qualifies the settings subset below over stdio with synthetic dependencies;
it does not qualify every method variant, transport or external backend.

The bounded unit targets `turn/settings/update` against immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012` and binary SHA-256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The test owns only disposable local Codex sessions and a loopback Responses
provider. The provider is not an app-server emulator. Every app-server result,
error, tool request and turn notification must come from the pinned executable.

## Three-file scope

- `apps/samgita_codex_driver/test/native_active_turn_settings_test.exs`
- `scripts/codex/active_turn_settings_fixture.py`
- `docs/codex-app-server/active-turn-settings-qualification.md`

The fixture reuses the existing owned stdio lifecycle and loopback Responses
provider. Shared fixture/runtime, schema and configuration sources are unchanged.
The provider returns one fixed dynamic tool and assistant output; it starts no
command or second Agent. Disposal closes the owned native process and provider
before removing the synthetic workspace.

## Native contract and source anchors

Paths below are relative to the pinned source's `codex-rs/` directory.

- `app-server-protocol/src/protocol/common.rs:1063-1069` declares the experimental
  method. `protocol/v2/turn.rs:40-91` denies unknown fields, requires thread/turn
  IDs, defines nullable sparse model/effort/summary selections and a double-option
  service tier, and distinguishes `applied` from `targetUnavailable`.
- `app-server/src/request_processors/turn_processor.rs:215-261` checks thread
  access, submits the update and returns the core outcome. Its effort conversion
  preserves public null-as-unchanged semantics.
- `core/src/session/step_activation.rs:228-383` requires
  `features.step_model_switching` for this settings subset, captures an exact
  active task, prepares a candidate, rechecks task identity and cancellation,
  validates constraints, and publishes only `next_step_settings`. It does not
  retarget a replacement task. An `applied` response does not promise another
  inference or change an already captured request.
- `app-server/tests/suite/v2/turn_settings_update.rs:43-275` provides the upstream
  A-to-B-to-A current-turn reference and distinct nullable semantics. Lines
  280-423 cover unavailable targets and the feature-disabled error; lines
  555-585 configure A/B model metadata and reasoning defaults. Reviewer-routing
  tests in the same file are intentionally outside this unit.
- `protocol/src/openai_models.rs:199-205,230-234,415-506,1004-1018` defines
  supported reasoning levels, summary support and advertised tier filtering.
  `core/src/client.rs:934-946,1055-1083` resolves the actual provider request
  reasoning and tier. The synthetic catalog explicitly supports low/high,
  summaries and `priority`; a silently omitted field cannot pass the positive
  priority assertion.
- `protocol/src/openai_models.rs:135-169` accepts nonempty custom reasoning
  efforts and rejects an empty string. The synthetic catalog additionally
  advertises `fixture-effort`; its exact value must reach the next native
  provider request.
- `app-server-protocol/src/protocol/v2/item.rs:1663-1677` defines all dynamic-tool
  request associations and the explicit response. The test checks threadId,
  turnId, callId, namespace, tool and arguments again immediately before replying
  to its one native request handle. No generic approval policy is installed.

## Seven native cases

| Case | Required observation |
| --- | --- |
| Current-turn publication | Initial captured request is A/low/concise; update and omitted sparse patch each return applied without consuming the pending native tool; continuation is B/high/detailed with positive priority; future turn is A/low/concise without a tier. |
| Nullable semantics | Explicit model/effort/summary null preserves B/high/detailed while serviceTier null clears priority; continuation checks actual tier key absence; next turn returns to A defaults. The separate first case requires priority to be emitted positively. |
| Custom effort | The advertised fixture-effort is accepted and emitted exactly with B/detailed/priority; the first and future turn retain A/low/concise. |
| Target identity | Idle, mismatched active and completed IDs return targetUnavailable without added inference; wrong active ID leaves the exact tool pending, then a matching update and fixed tool response complete that same turn; future settings stay A. |
| Native validation | Unknown fields and malformed IDs/model/effort/summary/tier reject through validation:wire, preserve the pending tool, and leave both continuation and future request at A defaults. |
| Feature flag | step_model_switching=false returns the exact native -32600 feature error, keeps the tool pending and preserves A for continuation and future request. |
| Experimental negotiation | With experimentalApi=false the driver rejects locally and the wire request receives the exact native capability error; neither creates inference. An independent valid stable turn still emits A defaults. |

Each active case requires one recorded provider request until the explicit fixed
tool response, two after continuation, and three after the future turn. Turn
start/completion notifications must retain the original thread and turn identity.
The tool result's call_id and fixed output are inspected in the continuation
request, and all pending interactions must settle. Unexpected native requests,
gaps or early completion fail the test. None is automatically approved.

## Evidence and limitations

Validation ran from source baseline `b592e829149bde647f9953c8950f91d289b38455`
plus the three scoped files, using `devenv shell --no-tui -- env MIX_ENV=test
PYTHONDONTWRITEBYTECODE=1 CODEX_BINARY=<pinned-musl-binary> python3
/tmp/samgita-active-settings-check.py`. That serialized runner invoked independent
`mix compile --warnings-as-errors`, focused format/check, `mix test
test/native_active_turn_settings_test.exs --seed 501432` and the same command
with `--seed 987654`, followed by root positional `mix credo --strict
apps/samgita_codex_driver/test/native_active_turn_settings_test.exs`.

The initial six-case run was **6 tests / one failure / 4.2s**: it incorrectly
classified an arbitrary nonempty effort string as malformed. The native server
returned `applied`, matching the pinned custom-effort deserializer. One repair
round changes the malformed cases to numeric and empty-string effort, and adds
the separate positive custom-effort capture test. No deadline, validation path
or production code changes. The corrected runs passed **7/0 at 501432, 5.2s**
and **7/0 at 987654, 6.0s**. Compilation, formatting and strict Credo passed;
Credo actually checked **one file / 69 checks**, with no issues. Logs are
`/tmp/samgita-active-turn-settings-initial.log` and
`/tmp/samgita-active-turn-settings-repair1.log`. Sol repair rounds: **1**;
Astra recoveries: **0**.

Two request/result entries and fifteen direct field/variant contracts receive
selected `implemented` evidence. The mapping uses positive model/effort/summary/
tier captures, explicit sparse/null behavior, exact thread/turn associations,
and both response statuses. The null effort/summary branches have deliberate
null-as-unchanged proof following a positive update, rather than an incidental
null default. No approvalsReviewer, unrelated dynamic-tool field or generic
schema definition is promoted. None receives full `verified` status.

Not covered: approvalsReviewer routing, reviewer preservation for approvals
already pending, child/frozen sessions, model safety-policy transitions, a
concurrent cancellation/publication race, managed-policy changes, unsupported
provider tiers, future-only thread/settings/update, every effort/summary variant,
background terminals, real provider/service success, package publication or
deployment. A11 and the overall full-compatibility gate remain independent and
incomplete. No external network/model/account task, service configuration,
production data, credentials or sibling repository is involved.

Final package/consumer/platform, populated recovery, static/assets/assembly and
hosted checks remain required on the integrated source. These passing selected
cases do not replace those gates.
