# Native proposed-plan notification fields

This unit qualifies exactly four canonical `ServerNotification.json` fields
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
