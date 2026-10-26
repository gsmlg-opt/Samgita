# Inert native subagent configuration import

The reviewed success-only import profile drives actual `SUBAGENTS` migration
through pinned Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256: `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256: `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
This imports text configuration; it never invokes an imported agent.

## Independent native effects

Two inert Markdown documents in owned `HOME/.claude/agents/` supply only name,
description and body. Their filename stems (`alpha`, `beta`) differ from their
frontmatter names (`owned-alpha`, `owned-beta`). Real detection reports both
names and preserves the separate, untouched session transcript already present
in the fixture. Source/configuration bytes remain exact throughout the journey.

Actual import writes exactly `CODEX_HOME/agents/alpha.toml` and `beta.toml`.
Python's standard-library `tomllib` parses the complete native files against
independent three-key expected maps:

| File | Name | Description | Developer instructions |
| --- | --- | --- | --- |
| `alpha.toml` | `owned-alpha` | `Codex alpha helper` | `Owned notes from Codex in AGENTS.md.` |
| `beta.toml` | `owned-beta` | `Codex beta helper` | `Owned beta notes from Codex in AGENTS.md.` |

The source uses `Claude` and `CLAUDE.md`; these exact output strings prove the
native rewrite. No TOML dependency is added. Success records identify the
frontmatter names as both source and target, with null cwd/title; they are not
filesystem path records. No optional tool, model, hook or permission metadata
is supplied. No loaded thread, native rollout or model request appears.

## Advisory request details and lifecycle

After checking detection, the request replaces `details.subagents` with one
different string name, `owned-requested-hint`. The native scope importer still
imports both source documents. No file or success is renamed to that hint.
This demonstrates accepted/ignored metadata, matching the pin's call chain:
`service.rs` re-discovers the scope without consulting the supplied details.
It does not establish selective import or a rename API.

This category imports synchronously: both files already exist when its
correlated response is received. Exactly one progress notification and one
completion follow that response. Their full envelopes retain the operation ID,
complete two-success result, empty failures and `emittedAtMs`. Timestamps must
be integers within the observed call interval and ordered progress-before-
completion. The receipt is not evidence that filesystem effects started later.

The full durable success history is observed before an explicit second import.
It returns a distinct operation ID and empty successes, preserves exact native
file bytes, and records that second completed operation. Warm re-detection no
longer offers subagents, while the unrelated session remains offered. Normal
owned shutdown/reaping precedes a distinct cold native process. Both complete
history records, native files, source/configuration bytes and detection behavior
survive unchanged. This is completed-operation repetition, not ambiguous retry
or an exactly-once execution claim.

## Source and physical owners

Only these exact `ClientRequest.json` nodes become scoped **implemented**:

| Owner | Pointer | Meaning demonstrated |
| --- | --- | --- |
| 180 | `/definitions/ExternalAgentConfigMigrationItemType/enum/5` | Actual `SUBAGENTS` filesystem import |
| 260 | `/definitions/MigrationDetails/properties/subagents` | Accepted advisory collection, scope re-discovery |
| 606 | `/definitions/SubagentMigration/properties/name` | Accepted advisory name, no selection/rename effect |

The actual import request graph resolves all three nodes independently. Their
node hashes and exact pre-change owner records are bound; equal hashes do not
propagate evidence. Thirty-four whole files match the immutable archive,
including detector/protocol conversion, scope import, Markdown parsing/TOML
rendering, text rewrite, durable histories, ThreadListResponse and native
notification envelope definitions.

## Corrections and final checks

The first new-case failure exposed an incomplete empty-thread response oracle:
native `ThreadListResponse` includes `backwardsCursor:null` and `readStates:{}`.
The next exposed native notification `emittedAtMs`, omitted from the expected
full envelope. Source-backed corrections add all fields and independent timestamp
bounds/order. They do not strip response metadata, remove assertions, change
deadlines or modify production behavior. Both failures remain recorded in
`/tmp/samgita-v344-owning-{initial,corrected}.log`; the targeted corrected case
passes, with the other four cases excluded by location selection only.

Baseline: `c6d54beb55f0c58087c2ff5078c3d288a181f926`.
Final affected four-file functional checks pass **9/0 twice**, seeds `501432`
and `987654`, in 32.185s and 32.086s. Scoped formatting, warnings-as-errors
compile, strict Credo on 508 sources, outside actual-binary consumer **1/0**
and retained relay/inline Exec AST checks pass. All 310 guarded sources remain
stable through verification; all 309 unrelated sources and production driver,
protocol and owned-process cleanup stay byte-identical. The existing Claude,
Cursor and age/count journeys preserve their original bounds and assertions.

Commands/logs: `/tmp/samgita-v344-run.py` and
`/tmp/samgita-v344-functional-checks/final/`. Source/final bindings:
`/tmp/samgita-v344-source.py` and `/tmp/samgita-v344-bind.py`.

| Artifact | SHA256 |
| --- | --- |
| Functional results | `c9441c60bd98c8549addfd6ed457fcd1ad2e889a8093a4c8faa2c5b4de6624dc` |
| Source guard | `413de187c764334fd8d36efa84079967ba764f148e38f9d515a04cb712af04af` |
| Whole source/schema comparisons | `84ee05470d6c7134627e2af70260b8b03e2fb96749506f23233b2f5e58e202ca` |

Inventory consistency passes; strict completeness exits **1**. Contracts are
**5,005 implemented / 1,550 missing / 66 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. Actual subagent
execution, optional metadata, repository scope and full family/transport/OS
qualification remain incomplete. Fixed YOLO is ordinary setup. Prohibited
security/credential/authentication/authorization/permission/approval tests and
audits, mixed/broad suites and hosted workflows remain unrun. A11, unreachable
legacy, unavailable external/platform/OS success, full compatibility and release
remain incomplete. No real Claude service, package publication, deployment or
production migration is established.
