# Native reasoning-item notification fields

This unit qualifies exactly six physical `ServerNotification.json` owners
**2595–2600**: the reasoning item variant, content, ID, summary, type and its
literal discriminator. It uses the immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

The Responses-only fixture supplies four completed reasoning output items and
one final assistant message. The stock executable creates every native
notification and history record. There is no scripted app-server peer, edited
rollout, real model backend, or paid inference. The ordinary TurnFixture setup
uses explicitly owned processes with fixed yolo settings; the prior namespace
and isolation profiles are not invoked.

| Provider input | Independently expected native value |
| --- | --- |
| Two summary entries | Same two literal strings in order |
| Mixed reasoning_text/text content, including an empty string | Same three literal strings in order |
| Empty summary/content arrays | Two explicit empty arrays |
| Populated summary with omitted content | Literal summary and explicit empty content array |
| Empty summary with explicit null content | Two explicit empty arrays |

Pinned [protocol/models.rs:1070–1082](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/protocol/src/models.rs#L1070)
requires summary and makes provider content optional. The
[native conversion:201–227](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/event_mapping.rs#L201)
extracts both supported content variants and defaults omitted/null content to
an empty array. Native finalization at
[stream_events_utils.rs:359–397](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/stream_events_utils.rs#L359)
emits a genuine finalized start followed by completion for each done-only item.
[v2/item.rs:916–920](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L916)
retains all four native fields. This does not test omitted/null summary or
infer server default behavior from a generic decoder.

The test requires exact complete live maps, literal provider IDs, paired
start/completion order, native thread/turn association and timestamps bounded
by host-observed turn times. Exactly one inference must receive the prescribed
developer/user input. Warm full history and actual selective reads retain the
same four items, including duplicate/reversed and absent selection IDs.

After confirmed native shutdown, a distinct process performs selective read
as its first content operation; full history follows. Final items/timestamps,
rollout/config/catalog/provider-journal bytes and unloaded state remain
unchanged. Workspace and uncertainty checks remain intact. This establishes
orderly process replacement, not power-loss or production cutover. Existing
5-second request, 20-second collection, 256-event/1-MiB bounds and owned
cleanup remain intact.

Seven complete producer/conversion files byte-match the retained immutable
source archive. All six exact canonical nodes and their export match pinned
provenance. Source evidence and manifest binding are under
`/tmp/samgita-v294-functional-checks/`; no equal-hash, wrapper or other-export
promotion occurs.

Base commit: `ae7b617`. The first owning implementation passes **1/0** at
both fixed seeds 501432/987654, with warnings as errors and no repair rounds.
Logs: `/tmp/samgita-v294-reasoning-{501432,987654}.log`.
The final explicit **34-file** matrix passes **60/0** at both seeds, in
**100.596/100.776** command seconds. Warning-free compile, scoped format,
strict Credo on 485 sources, outside actual-binary consumer **1/0**, eleven
provider AST checks and the **267-source** unchanged-byte guard pass. All
eight commands complete. Exact environment/commands/logs are in
`/tmp/samgita-v294-run.py` and
`/tmp/samgita-v294-functional-checks/functional/`. Results/source-guard SHA256:
`dc1844b9ba60434299c572082f351f1e13be54cca3d2c0c00784ea4fa5feee51` /
`c3f9d8e9fa873b632ac5776cb343646c836a7360b2f6c973f9dd202dbd4b1643`.
Adjacent final-binding.json requires exactly six changed owners and unchanged
IDs, node hashes, planned tests, unrelated records and all requirements.

Only these six owners become implemented: **4,806 implemented / 1,756 missing /
59 blocked** contracts, unchanged **462 implemented / 12 missing / 11 blocked**
requirements and zero verified. Inventory consistency passes; strict
completeness still exits **1**. Broad/hosted checks, security/permission tests
and audits remain unrun; A11, unresolved legacy producers, unavailable
external/OS profiles, full compatibility and release remain incomplete. No
runtime/shared-helper/dependency/configuration source changes or failing check
in the permitted matrix. No publication/deployment.
