# Native future thread-settings qualification

Two cases pass twice against immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, over Linux stdio: **2 tests / 0
failures**, seeds `501432` and `987654`, 2.4 seconds each. Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This is selected native implementation evidence for standalone
`thread/settings/update`; full compatibility remains incomplete.

## Separate active and future settings owners

`apps/samgita_codex_driver/test/native_thread_future_settings_test.exs` reuses
the existing `scripts/codex/active_turn_settings_fixture.py`. That loopback
Responses provider advertises synthetic A/B models and returns one fixed
dynamic tool followed by assistant content. The real pinned executable produces
every app-server result, error, notification and tool request. No fake
app-server frame, external model/account, shell tool or generic approval handler
supplies the observations.

The positive case (test lines 64-105) starts A/low/concise in an owned original
workspace and holds the real turn at `item/tool/call`. It sends a combined
standalone patch for B/high/detailed and another owned cwd. The empty response
acknowledges queueing. Before dependent calls, lines 178-202 wait for the matching
`thread/settings/updated` notification and assert exact thread ID, B model,
fixture provider, high effort, detailed summary and new cwd.

Omitted fields and an explicit model/effort/summary/cwd null patch each return
an empty response. These default patches need not emit a notification. The
original native tool remains pending with exactly one provider request until
the test explicitly answers its fixed handle. The continuation still emits
A/low/concise and exactly the original model-visible environment. A normal
subsequent `turn/start`, with no settings overrides, emits B/high/detailed and
the new cwd/workspace root. This is behavioral separation between the active
turn's captured settings and the thread's future defaults, beyond field
forwarding or reading back an applied snapshot.

The negative case (lines 108-153) sends missing/null/numeric thread IDs, numeric
model/effort/summary/cwd and an unsupported summary enum through native-wire
validation. It requires -32600 with `Invalid request:`. Malformed UUIDs require
the native `invalid thread id:` prefix; an absent valid UUID requires exact
`thread not found: <uuid>`. The fixed tool and provider request count stay
unchanged. After the sole explicit response, continuation and future turn both
retain A/low/concise and the original environment.

Each case requires exactly **three provider requests**, six across the suite.
Lines 225-259 re-check handle ID, connection generation, reference and complete
thread/turn/call/namespace/tool/argument association immediately before replying
only to `fixture_lookup({"key":"synthetic"})`. Lines 261-275 require exactly
one start and completion for the original turn, inspect its native continuation
`function_call_output` and require no pending, uncertain or interactive work.
Unexpected native requests, event gaps or early completion fail the test.

## Pinned source boundary

Paths below are relative to the pinned checkout's `codex-rs/` directory.

- `app-server-protocol/src/protocol/v2/thread.rs:236-295` defines ordinary
  nullable Option model/effort/summary/cwd fields for subsequent turns. Null
  preserves these values. The distinct double-option service-tier clearing
  contract is outside this unit. Lines 303-333 define the applied public snapshot.
- `app-server/src/request_processors/turn_processor.rs:737-794` rebuilds default
  environment requests when cwd changes, replacing the old default cwd in
  fallback roots. No supplied environment fields means no environment change.
  Lines 826-834 explicitly require a notification barrier or combined fields
  because the response only acknowledges queueing. Lines 940-994 load the
  thread, build overrides, queue only a nondefault patch and return `{}`.
- `core/src/session/thread_settings.rs:33-94,119-132` applies standalone
  thread-owned settings and emits their snapshot.
  `core/src/session/mod.rs:1981-2071` saves environment defaults for future turns
  while the running turn keeps its own.
  `core/src/session/step_settings.rs:22-78` defines immutable captured settings
  and effective reasoning-summary values.
- `core/src/session/turn_input.rs:148-197,211-218` captures defaults for a new
  turn and retains the existing context when active input is steered.
  `app-server/tests/suite/v2/thread_settings_update.rs:230-469` independently
  exercises future provider settings, cwd/root retargeting and publication
  during an active turn.
- `app-server/src/message_processor.rs:112-116` wraps deserialization errors as
  native `Invalid request:` errors.
  `app-server/src/request_processors/thread_processor.rs:974-989` distinguishes
  malformed and unloaded thread IDs.
  `protocol/src/config_types.rs:54-73` defines the summary enum.
- `core/src/session/handlers.rs:605-639` can report semantic settings failures
  asynchronously after a queued acknowledgement. The negative cases deliberately
  cover malformed wire input and target lookup; they do not claim all semantic
  constraints are rejected synchronously by the RPC.

## Validation record and limits

Passing logs, captured commands and source hashes are in
`/tmp/samgita-native-three-units-v3-20261024/`. The coordinator ran driver
`mix compile --warnings-as-errors`, scoped `mix format --check-formatted`, and
`mix test test/native_thread_future_settings_test.exs --seed <seed>` serially for
both seeds. Namespace preflight passes. Integrated root `mix credo --strict`
checks **360 files / 69 checks**, finding no issues. This document records those
inspected results; its writer did not rerun executable checks. This family had
no observed native failure or behavioral repair: Sol repair rounds 0, Astra 0.

The final formatted test SHA256 is
`d94fb075b0d6cd11f2bc13591433e9e11cd221790228e9c77b97e2f27f4aaec3`,
matching the passing run's source snapshot. The existing provider and shared
helpers were reused without a fixture change for this unit.

**10 exact contracts now have selected implemented evidence in the manifest;
zero receive verified status.** Six
request candidates cover cwd, model, explicit-null effort and summary with its
nonnull/null branches. Four snapshot candidates cover cwd, modelProvider,
summary and its nonnull branch. Existing effort/model snapshot evidence is
exercised without a new nomination. A nonnull snapshot cannot qualify the
summary-null output branch. No method aggregate or unrelated generic schema
definition is promoted.

The positive scope is the owned Linux stdio process, fixed dynamic interaction,
local synthetic provider and default environment roots. Cold resume,
process-restart persistence, metadata projections, every summary/effort variant,
collaboration/personality, permissions/reviewer routing, service tiers,
concurrent publication/cancellation, managed constraints and external providers
remain unqualified here. This suite does not extend the separate
`turn/settings/update` qualification. Other platforms/transports, A11,
aggregate/hosted release checks, full compatibility, publication and deployment
remain independent and incomplete.

## Direct turn cwd inheritance and sibling isolation

An additive case uses the existing fixed assistant fixture without modifying its
provider or lifecycle helpers. Two native threads start in owned cwd A. Five
completed turns prescribe A for an omitted cwd, B for an explicit override, B
for a later omission, B for explicit null, and A for the untouched sibling.
Each completed turn must add exactly one provider request, with independently
expected environment cwd/workspace roots and original model/reasoning settings.
Configuration bytes remain unchanged; pending requests, interactions and
uncertainty stay empty before checked owned shutdown.

Pinned `v2/turn.rs:232-234` and
`request_processors/turn_processor.rs:631-659,737-792` define optional cwd and
sticky step-context capture. The exact primary owner is
`schema:v2/TurnStartParams.json#/properties/cwd`, SHA256
`74afb429559747df3a09611f5cc5bb55a50839f4a95f14886e83c47e9e1238de`.
Only this direct property gains scoped implemented evidence; no null alias or
whole default lifecycle is promoted. The complete nine-file native block passes
61/0 at501432/987654, with commands/source hashes in
`/tmp/samgita-native-stop-cwd-authority-v2-20261025/`. Concurrent changes,
cold default restoration, other stores/OS/services and full compatibility remain
separate requirements.
