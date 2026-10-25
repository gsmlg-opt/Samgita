# Native proposed-plan items and streaming

The native profiles cover done-only proposed plans and genuine streamed draft
deltas whose authoritative final content differs. The
[streaming continuation](#streaming-continuation) adds two physical branches
and supplements four existing delta fields; no other export is inferred.

## Done-only profile

The original unit qualifies exactly four canonical `ServerNotification.json` fields
**2591–2594**: Plan ID, text, type and the literal discriminator. It uses
immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The local provider supplies one completed Responses assistant message whose
text contains a proposed-plan block. The real executable owns all app-server
frames and history writes. The test starts ordinary, explicitly owned native
processes with fixed yolo settings; there is no scripted app-server peer,
edited rollout, real model service or paid inference.

The request selects plan collaboration mode. Independent literal expectations
require the following native values:

| Lifecycle | Expected item |
| --- | --- |
| Started | `type: plan`, ID `<returned turnId>-plan`, empty text |
| Completed | Same type/ID, `# Owned next plan λ🙂\n- first\n- second\n` |

The closing newline is significant. The native
[producer:2064–2118](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L2064)
derives the ID and emits both items. The
[done-only extraction:2420–2443](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L2420)
parses final assistant content; the
[parser:93–115](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/utils/stream-parser/src/proposed_plan.rs#L93)
preserves its extracted text. The
[v2 conversion:912–915](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L912)
retains native fields. This is an actual producer test, not generic JSON
forwarding or inference from schema shape.

Exact complete start/completion maps must be ordered and contain the native
thread/turn association and host-bounded timestamps. The turn completes, the
provider receives the prescribed user marker and metadata, and exactly one
inference occurs. Warm history retains the original user input and final Plan.
Selective reads check duplicate, absent and valid IDs without changing results.

After confirmed native shutdown, a distinct process performs selective read as
its first content operation. Final item/timestamps and full history remain
identical; the thread stays unloaded. Rollout, configuration, model catalog
and provider journal bytes remain unchanged, with an empty workspace and no
uncertain operations. This proves orderly process replacement, not power-loss
or production recovery. Existing 5-second request, 20-second collection,
256-event/1-MiB bounds and owned cleanup remain intact.

Seven complete producer/projection files byte-match the immutable source
archive. All four exact physical nodes and their export match pinned
provenance. Evidence and manifest binding are under
`/tmp/samgita-v296-functional-checks/`; branch2590, deltas, aliases and other
exports remain outside this unit. No equal-hash evidence propagation occurs.

Base commit: `5c983238`. The first implementation passes its owning test
**1/0** at both seeds501432/987654, with warnings as errors and no repair
rounds. Logs: `/tmp/samgita-v296-plan-{501432,987654}.log`.
The final explicit **38-file** matrix passes **64/0** at both fixed seeds in
**107.534/107.990** command seconds. Warning-free compile, scoped format,
strict Credo on489 sources, outside actual-binary consumer **1/0**, thirteen
provider AST checks and the **273-source** unchanged-byte guard pass. All
eight commands complete. Exact commands, environment and logs are in
`/tmp/samgita-v296-run.py` and
`/tmp/samgita-v296-functional-checks/functional/`. Results/source-guard SHA256:
`04d57476e658e353494ea397ca4edd35cad8ec1efa5f554c103272fad7964c01` /
`9b04826fc5846278ad54b39be677e7eec12471a9f2241f4cd54fa5ff15d7d854`.
Adjacent final-binding.json requires exactly four changed owners and unchanged
IDs, node hashes, planned tests, unrelated records and all requirements.

Only these four owners become implemented: **4,822 implemented / 1,740 missing /
59 blocked** contracts, unchanged **462 implemented / 12 missing / 11 blocked**
requirements and zero verified. Inventory consistency passes; strict
completeness exits **1** because unverified requirements remain. Required
broad/hosted checks, security and
permission tests/audits remain unrun. A11, unresolved legacy producers,
unavailable external/OS profiles, full compatibility and release stay
incomplete. No runtime, shared helper, dependency or application-configuration
changes occur. No publication/deployment.

## Streaming continuation

The second tagged profile retains every original done-only assertion and
reuses its independent lifecycle, history, first-cold selection, byte retention,
request budget, deadlines and owned cleanup. Its separate Responses-only
fixture adds an empty assistant message, four output-text chunks with split
opening/closing tags, and one finalized assistant message. No app-server
frame or rollout is supplied by the fixture.

| Stage | Independently prescribed value |
| --- | --- |
| First native delta | `# Draft λ🙂\n` |
| Second native delta | `- streamed\n` |
| Completed Plan text | `# Owned final λ🙂\n- accepted source\n` |

The exact lifecycle must be start, first delta, second delta, completion.
Each delta has exactly the requested native thread/turn IDs, turn-derived Plan
ID and literal text; its wire envelope has precisely method, params and
top-level `emittedAtMs`, bounded by host turn times. The completed text must
differ from concatenated draft deltas. Warm and first-cold full/selective API
history contain the final Plan, preserving the original user input, native
timestamps, rollout/config/catalog/provider bytes and one inference per case.
The original done-only profile additionally asserts no Plan deltas.

This behavior is required by the pinned
[PlanDelta contract:1450–1461](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1450),
which explicitly warns against assuming final text equals concatenated deltas.
Actual
[Responses parsing:362–365](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/sse/responses.rs#L362),
[native streaming:3120–3145](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L3120),
[final extraction:2416–2444](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/session/turn.rs#L2416)
and
[notification mapping:374–379](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/event_mapping.rs#L374)
establish reachability. The official
[Plan item test:35–96](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/tests/suite/v2/plan_item.rs#L35)
uses the same added/delta/done path; it is inspected as source, not run here.

Exactly two missing canonical branches **2590/2919** become implemented.
Existing `v2/PlanDeltaNotification.json` fields **4504–4507** gain scoped
supplemental evidence with unchanged state and no recount. Twelve complete
producer/parser/projection/test files match the immutable archive; all six
physical nodes match pinned provenance. Multiple blocks, interleaving,
reconnect and other exports/OS/transports remain unqualified.

Base: `362f6eeb`. Both owning cases pass with warnings as errors at seeds501432/
987654: **2/0 each**, zero repair rounds. Logs:
`/tmp/samgita-v298-plan-{501432,987654}.log`.
The final **38-file** matrix passes **65/0** at both fixed seeds in
**110.141/110.121** command seconds. Warning-free compile, scoped format,
strict Credo on489 sources, outside actual-binary consumer **1/0**, fourteen
provider ASTs and the **274-source** unchanged-byte guard pass. All eight
commands complete; exact environment/commands/logs are in
`/tmp/samgita-v298-run.py` and
`/tmp/samgita-v298-functional-checks/functional/`. Results/source-guard SHA256:
`4d2948f27b0062262a17c1579f139fb9086d62a49d54b2c5901da676dc07c7d2` /
`f62873df86e827b286a36d3e46f2c1459fa5abba2482a6a7d8458d51a331c352`.

Initial final-binding validation catches one misplaced evidence link at4000:
a generated three-context-line diff matches a repeated evidence array instead
of owner4504. Its state never changes. The correction uses complete records
including unique IDs, restores4000 and places the link at4504. The failed scope
report is retained as initial-manifest-scope-failure.json. Final binding now
requires exactly the intended six records, two promotions and four supplements,
unchanged identities/hashes/planned tests, unrelated rows, all requirements and
all274 tested-source hashes. No functional source/test result is changed or
rerun for that metadata-only correction. Evidence/owner binding:
`/tmp/samgita-v298-functional-checks/`.

Counts become **4,840 implemented / 1,722 missing / 59 blocked** contracts,
unchanged **462 implemented / 12 missing / 11 blocked** requirements and zero
verified. Inventory consistency passes; strict completeness exits **1** for
unverified requirements. Prohibited security/permission tests, audits and related broad/hosted
checks stay unrun. A11, unresolved legacy, unavailable external/OS profiles,
full compatibility and release remain incomplete. No runtime, shared helper,
original done-only fixture, dependency or platform configuration changes. No
publication/deployment.
