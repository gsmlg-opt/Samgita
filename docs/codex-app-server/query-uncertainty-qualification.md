# Query failure and uncertainty capacity

Lost native history/introspection responses no longer appear as possibly
executed work, and pending queries no longer reserve mutation uncertainty
capacity. This repairs two reproduced Session defects on base
`a8febb189d256bed70bcd5a2e1ae7076e32bce86`. It changes no protocol schema,
dependency, database model, authorization rule or process-cleanup implementation.

## Source-backed classification

The target remains Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Exactly six additional methods use the existing query classification:

| Method | Pinned native operation |
| --- | --- |
| `server/diagnostics` | Process and registered-gauge snapshot |
| `thread/search` | Stored content search with current metadata enrichment |
| `thread/searchOccurrences` | Stored visible-message matches, ranges and cursors |
| `thread/items/list` | Stored item paging |
| `thread/items/read` | Stored selection by thread, turn and item IDs |
| `thread/timeline/list` | Stored timeline and realtime boundary records |

The native handlers call diagnostics snapshots or ThreadStore query methods;
none submits a turn, command or realtime-session start. Ten complete files
match the immutable source archive, including the real query implementations.
Native reads can refresh internal projections/caches: this classification
concerns execution effects and does not assert zero internal writes.

The existing method list determines both pending effect classification and
admission under `max_uncertain`. Capacity now counts retained uncertain
operations plus **pending mutations**, rather than every pending call. The
separate `max_pending` still bounds all requests. Check and insertion remain
serialized by the same Session process. Unknown methods remain potentially
mutating; callers cannot redefine that classification. No retry, implicit
reconciliation, uncertainty eviction or request-ID reuse is introduced.

## Reproduction and repair

`query_uncertainty_test.exs` first runs against unchanged production code:
**25 cases / 21 failures**. Four loss modes for each initially identified query
produce `uncertain: true` incorrectly. A held, already-classified `thread/list`
also wrongly blocks the first mutation at `max_uncertain: 1`. The four existing
behavior controls pass: pending mutation reservation, retained mutation
uncertainty, unknown-method conservatism and the independent pending bound.

Adding the five query names and counting only pending mutations makes the same
25 cases pass. Source inspection then confirms `thread/timeline/list` is an
equivalent sixth query. Its four additional cases first fail (**29/4**) before
its name is added. No assertion or timeout is weakened. Logs are retained at
`/tmp/samgita-v349-query-before.log`, `-query-after.log` and
`-timeline-before.log`.

The final 29-case dedicated module exercises deadlines, disconnect/reconnect,
send failure and local abandonment for every new query. Query failures release
pending state without consuming uncertainty capacity; later explicit mutations
remain possible. Late responses stay observable. Reconnect requires explicit
initialization and never replays the old request. Genuine mutations retain
uncertainty and reservation; queries never clear those records. ScriptedTransport
injects driver faults into the actual Session; these are not native-backend
success or real-service compatibility tests.

## Final permitted checks

The final **nine-file, 43-case** functional matrix passes at both seeds
`501432` and `987654`, in **44.316/44.646 seconds**, with no exclusions. It
contains the 29 new driver cases and 14 retained ordinary actual-binary cases.
The latter use the pinned owned executable with synthetic local Responses;
they do not establish external-provider success. Four existing capacity cases
at `session_capacity_deadline_test.exs:7`, `:48`, `:65` and `:89` also pass at
both seeds. No permission/approval case in that file executes.

The first combined command uses line filters, causing Mix to exclude the other
files too: it discovers 50 cases but runs only those four, with **46 excluded**.
Those logs remain intact and are counted only as four-case capacity evidence.
The corrected separate whole-file commands execute all 43 ordinary cases at
each seed. This selection correction changes no source or assertion.

Scoped format, warnings-as-errors compilation, strict Credo on **510** sources,
two fixture AST checks and the outside-umbrella actual-binary consumer **1/0**
pass. A **312-source** before/after guard binds the final executions. Only
Session and the new test differ from the prior source set; all **310** other
previous sources, including protocol/transport/cleanup code, remain unchanged.
The earlier 14-case qualification was on the previous Session; this fresh
matrix supplies affected functional regression evidence for the changed code.

Exact environments/command arrays: `/tmp/samgita-v349-run.py` and
`/tmp/samgita-v349-qualified-run.py`. Source and final manifest checks:
`/tmp/samgita-v349-source.py`, `/tmp/samgita-v349-bind.py --verify`.
Artifacts are under `/tmp/samgita-v349-functional-checks/`:

| Artifact | SHA256 |
| --- | --- |
| Initial static/selected-capacity/consumer `results.json` | `74b57138f0aeb8e2fabadd7ce143aa26d24b42f08a1f456bd5c057d2dd028fc3` |
| Initial source guard | `2960e6e0ec93c64ce7c09c39c2d7c208f816e4b207005d1a8f95e1a24dff9e51` |
| Ten immutable source files and reproduction evidence | `4e51f7e79a8a5d77d03182fb641d23a5c8a93c4367fdb36da49cd6eb5d477084` |
| Final whole-file `final/results.json` | `5fbeabdbb1fdfe4bd1eb947b50728d32d13392c9536b817ca8ca13f8dcee9600` |
| Final source guard | `4dbc495ab55355c35f8d6dbe789bc53608bad116289c6cd51b93d4b9135b23c4` |

## Integration and limits

There is no database migration. Existing uncertain operations and durable
platform journal entries are not rewritten or automatically resolved. The new
classification applies to new submissions; previous pending entries retain
their recorded effect classification. Rolling back the driver restores the
earlier conservative query behavior and must preserve unresolved operations.
No rollback may clear uncertainty or redispatch possibly executed work.

Nine existing implemented requirements receive supplemental evidence: the six
client queries, deadline uncertainty, reconnect and bounded capacity. No state
or schema owner is promoted. Contracts remain **5,018 implemented / 1,537 missing
/ 66 blocked**; requirements remain **462 implemented / 12 missing / 11 blocked**,
zero verified. Inventory consistency passes; strict completeness exits **1**.

Prohibited security/credential/authentication/authorization/permission/approval
checks, audits, mixed/broad suites and hosted workflows remain unrun. Prior
platform/security results are not rerun or promoted on this changed Session.
A11, producerless legacy paths, unavailable external/OS/platform acceptance,
complete negotiation/default behavior and the full goal remain incomplete.
Pushes suppress CI; no release, publication, production migration or deployment
is established.
