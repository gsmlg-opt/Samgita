# Native reasoning and checklist envelopes

This unit supplements the [implementation ledger](implementation-plan.md) and
[repair record](repair-qualification.md) on existing `main`, baseline
`a8ce1f99bdf923b0ed4bd876fb00d69134959ba2`. Only full notification roots
**2887/3011/3015/3019** are in scope; their twelve implemented method/literal/
params siblings remain unchanged. This is actual pinned Linux stdio behavior
against a local synthetic Responses provider, not a mock app-server or real
provider acceptance.

Pin: `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`,
executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

## Independent effects and original messages

`native_reasoning_checklist_envelope_test.exs` creates two isolated roots with
direct fixed-YOLO native stdio sessions. It uses no old mixed launch/thread
helper. Its provider imports only `ModelFixture` lifecycle primitives, implements
its own request/SSE handling, and never generates app-server messages.

The reasoning case independently prescribes seven notices: part0; summary0
`Synthetic summary ` then `λ🙂`; part1; summary1 `Synthetic second summary`;
raw2 `Synthetic raw ` then `α🙂`. Actual thread/turn IDs join the literal item
ID `owned-reasoning`. The exact empty started reasoning item and populated
completed item bracket the ordered notices; the final assistant item has an
independent ID/text and explicit null metadata. Exactly one provider request and
the complete prescribed provider SSE journal must agree.

The checklist case exercises the real default-mode `update_plan` tool. Its
complete notice preserves the Unicode explanation and ordered completed/current/
pending steps. Provider `in_progress` becomes native wire `inProgress`. Exactly
one checklist notice precedes completion, with no Plan delta. Request1 advertises
the real tool; request2 must contain the actual matching `Plan updated` result
before the provider returns the final assistant item. The exact four-field tool
result includes a native `fco_` UUIDv7 item ID. Exactly two model requests and both
full SSE journals are checked independently of the notification.

Capture retains original incoming JSONL before Session decoding and separately
records outgoing bytes. Each target notification equals its independently
prescribed complete method/params/emittedAtMs map, with notification kind,
current generation, schema validation and an independent host-clock bracket.
The raw selected stream equals the driver stream in order. Raw item lifecycle
and terminal records are checked as an ordered subsequence; final post-shutdown
capture cannot hide late target duplicates. Every RPC has a fresh ID and exact
original request/response pair. Client methods are exactly initialize,
initialized, diagnostics, thread/start and turn/start. Provider request bodies
independently identify the actual thread/turn. No clock uniqueness, durable
sequence, reconnect/replay or cancellation guarantee follows.

Pinned `codex-api/src/sse/responses.rs:378–405,490–496` and
`core/src/session/turn.rs:3168–3265` are the real reasoning ingress/producers;
`protocol/event_mapping.rs:380–406` in app-server-protocol maps their fields.
`core/src/tools/handlers/plan.rs:22–41,64–99` emits the checklist and actual
tool result; `v2/turn.rs:584–628` converts status spelling. Native session history
stamps the result identity, and the normal HTTP serializer preserves its prefixed
ID. `app-server/src/outgoing_message.rs:895–908` supplies native envelope time.
Seventeen complete producer/serializer files and four canonical schema nodes
are independently matched to the pinned source archive.

## Bounds, checks and limits

Capture and retained events are each capped at128/2MiB, with8KiB outgoing and
64KiB incoming frames. Provider bodies are at most1MiB; journals2MiB; SSE64events/
64KiB. RPC/startup deadlines are5s, turn20s and case60s. Success and failure
cleanup require native/provider owner completion, closed Ports and disappearance
of both recorded PIDs before deleting owned roots. No existing cleanup behavior
is replaced. Configuration/catalog/workspace bytes are not frozen by this unit.

Run the reviewed profile with `/tmp/samgita-v406-run.py`. Exact per-command cwd,
arguments, source list, exit status and log hashes are retained in
`/tmp/samgita-v406-functional-checks/final/`; it uses Elixir1.18.5/OTP27.3.4.17,
`MIX_ENV=test`, `ERL_FLAGS='+S 2:2'`, pinned `CODEX_BINARY`, no inherited Mix
build/deps/partition overrides and `PYTHONDONTWRITEBYTECODE=1`.

Focused **2/0** passes at501432 in4.276 command seconds. Final **37/0** at
seeds501432/987654 passes in69.381/65.716 command seconds without exclusions.
Five Python syntax checks, scoped format, warning-free driver compile, root
strict Credo and inventory consistency pass. All403 guarded sources are stable;
all401 prior source bytes remain unchanged. No runtime repair, assertion removal
or deadline increase was needed.

Independent source review of those exact test/provider bytes found no actionable
defect; `/tmp/samgita-v406-independent-review.md` SHA256
`192d60b963547da85f35c9e85ef04d3691fbf7610b2b46fbef2f397ecee50afc`.
It ran no tests and does not substitute for the parent-run evidence above.

Test/provider SHA256:
`1690af8c40532142dc3ab3b9fa3ee67ade2ff746c95b1de2750868d8dc9f697a` /
`9f4f818939a6409b31b8180524cbfd353b9aff8afe1a3e8a4ee42b8c2aa08ecc`.
Results/source guard SHA256:
`8e82f6674b1d15506f8efb8a59c5051ae3f8c7cab0443a7acdcebfa1f0587ed5` /
`3a1bd0f9853bea5713f97a704fccade12badf6edc66a5326d35f07b3cb40c0af`.
Archive binding `/tmp/samgita-v406-source-final/evidence.json` SHA256:
`b97ba42c4a6293d49757d60144049c784e0dca3aa7afeca5eedc74abc88a2306`.
Manifest binder `/tmp/samgita-v406-bind.py` and
`/tmp/samgita-v406-binding/evidence.json` SHA256:
`c5f175c39515b6cc78a7ad2c12e209d95c39b64bf9186e71bee282442dde4123`.

Only2887/3011/3015/3019 become scoped implemented: **5,140 implemented
/1,415 missing /66 blocked** contracts, with zero verified. Strict completeness
still fails; no broad requirement changes state.

Only the four named roots may become scoped implemented. Requirements stay
462implemented/12missing/11blocked, with zero verified. The full-goal completeness
gate remains incomplete. No aliases, every optional item branch, remote backend,
other OS/transport or Samgita Task acceptance is claimed. Security/permission
tests/audits, mixed broad suites and hosted workflows remain unrun; A11,
unavailable producers and real external/platform/full-goal/release gates remain
incomplete. No publication, deployment, production migration or sibling edit.
Rollback removes this fixture/test and its four mappings, preserving runtime
and historical records. Continue ordinary item/status/turn lifecycle envelopes.
