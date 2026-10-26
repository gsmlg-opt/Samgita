# Native partial import and durable completion

A real session import now has same-operation success/failure and durable
completion evidence. The request's UUID response precedes processing; separate
progress observations merge into one completed result retaining both outcomes.
The driver runtime and protocol schemas are unchanged.
Base: `4f9f7219e1aa3b02694c1591e84a3789817c0494`.

## Genuine producer and independent oracle

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Seven complete source members freshly match the pinned archive.

`external-agent-migration/src/service.rs:175–192` returns None when a selected
source no longer exists. `app-server/src/external_agent_migration/processor.rs:
448–517` records the exact `session_not_detected`/`session_missing` failure and
continues other valid sessions. Its importer creates the actual native target;
`external_agent_migration/protocol.rs:278–325` merges repeated same-type progress
into one completion group. The processor persists completion before publishing
it; `state/src/runtime/external_agent_config_imports.rs:47–81,109–143` stores and
publicly reads the native operation time/results.

The existing ordinary session-import fixture gains one test and one helper;
its previous six cases and oracles are unchanged. Two tiny supported transcripts
are genuinely detected under the owned source tree. Only the new second source
is then renamed to a non-jsonl sibling, preserving every original byte. The
single import uses those original selections. Its exact literal failure and
successful target appear in separate progress notices, then together in one
completed SESSIONS group. The captured native UUID response must precede all
three notices. This is real import processing, without a recordHistory call or
a manufactured app-server response.

Public history must contain exactly this operation/provider, the independently
expected failure and genuine success, with `completedAtMs` inside host UTC
readings around the import/completion observation. Native emitted timestamps
are also independently bounded; equality with completion time is not assumed.
The one successful target has the real imported canonical rollout, original
source chronology/text and complete Legacy history including the import marker.
The vanished source creates no second thread.

After confirmed native shutdown, a distinct pinned native process performs
public history/thread reads before any resume or new import. The complete
history record, native timestamp, target, full native history and raw rollout
remain exact. Valid/held source bytes, configuration/catalog/support inputs and
the empty model-provider journal survive final close. No model turn or cold
import retry is issued.

The new inventory requires18 original outgoing messages, at most24/4KiB each,
exact method counts and exactly three import notices total. Existing complete
bidirectional capture256frames/4MiB and262KiB frame limit stay unchanged. New
event/input/rollout observations are additionally checked at1MiB. Existing60s
case,5s request and10s event deadline and strong owned native/provider cleanup
remain; no timeout extension or skipped assertion is used.

## Verification and limits

Initial **7/0**, final ordinary import group **7/0 at501432 and987654**, driver
compile/format, strict Credo543 and inventory consistency pass. All374 guarded
sources remain stable through final checks, with all373 other prior sources
unchanged. All770 exports and15 input descriptors remain exact. Prior unrelated
full-matrix/consumer/root/static/assembly evidence retains source equivalence;
those checks were not rerun for this addition.

Commands, logs and guard: `/tmp/samgita-v373-run.py`,
`/tmp/samgita-v373-functional-checks/final/`. Source investigation and parent
review: `/tmp/samgita-v373-ordinary-gap.md`,
`/tmp/samgita-v373-final-review.md`. The final binding records exact hashes and
owners3967/3968: `ExternalAgentConfigImportHistory.completedAtMs` and `.failures`.
Their earlier record-only/mixed evidence remains historical; only these owners
gain the scoped actual-processing evidence.

Contracts: **5,044 implemented /1,511 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
continues to fail. Other transcript formats, changed-source append, concurrent
imports, arbitrary failure variants, external services and other platforms/
transports remain unqualified. This ordinary fixture varies no source-root or
permission condition and does not execute the prohibited mixed import suite.
Prohibited tests/audits and hosted workflows remain unrun; A11 and
legacy/external/platform gates stay incomplete. No publication or deployment.

Rollback removes only the added test/helper and exact supplemental evidence.
Keep the six original cases, runtime, prior evidence and history. Continue the
remaining reachable ordinary functionality.
