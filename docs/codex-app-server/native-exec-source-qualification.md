# Genuine Exec source discovery

The pinned combined Codex binary creates a persistent `exec` thread through
its ordinary `codex exec --json` entry point. The driver subsequently discovers
that actual thread through native list, search and paginated history APIs.
This strengthens the earlier exclusion-only evidence for canonical
`ClientRequest.json#/definitions/ThreadSourceKind/enum/2` (physical owner675).
It adds no new implemented or verified owner.

Pin: `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl/stdio.
Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256:
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Producer and driver observations

`native_exec_source_values_test.exs` starts the genuine CLI under the existing
owned Stdio process group. Exec reads piped stdin to EOF even with a positional
prompt. A small test-only Python `execv` launcher supplies empty stdin without
closing the owner's independent control pipe. It preserves the child PID/group
and writes a bounded PID/executable/argv sidecar. Exact pinned binary bytes,
native CLI thread output, provider metadata and canonical history establish
provenance; no short-lived `/proc` observation is assumed. Full bounded JSONL,
normal exit0, port closure, owner completion and native PID disappearance are
required. CLI JSONL is kept separate from app-server JSON-RPC.

The CLI makes exactly one ordinary assistant request to the existing local
Responses fixture. Its native `thread.started` ID equals the provider's thread
ID and canonical SessionMeta. The native turn ID comes from actual provider
metadata, then agrees with durable completion and paginated history. Session
source `exec` and attribution `thread_source:user` are independent fields.
An ordinary app-server control supplies a separate persistent `vscode` thread,
one more genuine assistant request, independent IDs and the shared search marker.
No SessionMeta/SQLite record is fabricated or rewritten.

After both producers close, two distinct fresh native readers each run positive
`exec`, `vscode` and mixed-OR list/search queries before hydration. All12 filter
requests must preserve their complete wire maps and original response IDs.
Independent eight-field projections, exact source/ID sets and literal search
snippets distinguish the two real producer kinds. Native `thread/read` uses
`includeTurns:false`; `thread/turns/list` requests `itemsView:full` and
`thread/items/list` must yield the same completed turn and user/assistant items.
Cold public item identities and full history maps remain stable. Loaded threads
stay empty, provider requests stay exactly two, and source/config/catalog,
canonical rollout, CLI output/sidecar and provider journal bytes remain frozen.

## Raw and public history identities

Two initial oracle failures exposed native representation distinctions. Initial
environment context is a separate classified user-role ResponseItem preceding
the real prompt. It is retained intact as opaque content; this profile does not
inspect or test the permission properties of that context.

Native user-input persistence creates a raw ResponseItem ID and a distinct
UserMessage TurnItem UUID. Paginated APIs project the durable `item_completed`
TurnItem, not the raw ResponseItem. The oracle therefore binds public user IDs
to the actual durable event and independently retains the raw message identity,
same native thread/turn, classified prompt content and cold byte stability.
Assistant IDs agree between raw fixture output, durable event and public item.
A subsequent assertion failure identified the native internal assistant-content
tag `Text`, distinct from public text tags. All failures remain in the local
qualification logs; corrections retain the complete observations and bounds.
No timeout increase, suppressed error or missing assertion substitutes for this
source-backed mapping.

## Pinned source and scope

Thirty-one complete Rust files match their unique immutable archive members.
Source closure includes real CLI dispatch/Exec startup, in-process session
source, native recording/materialization, filters/search, contextual user
classification and paginated item projection. Key boundaries are:

- `exec/src/lib.rs:729–753,1414–1465`: actual Exec session source and paginated start.
- `rollout/src/recorder.rs:948–977`: canonical first SessionMeta.
- `core/src/session/mod.rs:5235–5278` and `protocol/src/items.rs:513–536`:
  independently created raw and public user identities.
- `rollout/src/policy.rs:129–145,229–287`: durable paginated ItemCompleted events.
- `app-server-protocol/src/protocol/thread_history_projection.rs:78–108` and
  `protocol/v2/item.rs:873–909`: durable public item mapping; raw responses ignored.
- `app-server/src/filters.rs:6–81` and
  `request_processors/thread_processor.rs:2774–2835,5772–5864`: real selection.

Both typed list/search request graphs resolve to the exact canonical enum.
Its independently checked node SHA256 is
`c20d3fcfc0c2bd2a6ecb30670b66a69dce7b92ca87e3cefd922f3ec19b917e82`;
the unchanged export SHA256 is
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
Only owner675 receives supplemental behavioral evidence; equal hashes,
references and sibling exports inherit nothing. Other genuine source producers,
legacy production, remote providers/catalogs, other OS/transports and full
compatibility retain their separate incomplete profiles.

## Qualification

Base commit: `fbf0b36b842fed87890103f882c63ff36921d605`.
Elixir1.18.5/OTP27.3.4.17, independent driver build/config/dependency paths,
`MIX_ENV=test`, `ERL_FLAGS='+S 2:2'` and pinned `CODEX_BINARY`.
The owning functional profile passes1/0 at seed501432 after the documented
oracle corrections. The final reviewed **56-file matrix passes110/0 twice**,
seeds501432/987654, command times197.478/197.722 seconds. Scoped format,
warnings-as-errors compile, strict Credo on506 sources, outside actual-binary
consumer1/0,30 fixture ASTs plus the inline launcher's AST and the **307-source
guard** pass. All306 prior guarded sources remain byte-identical.31 complete
archive files, exact owner675 and both request graphs pass; final manifest
binding checks only that owner's evidence/limitations/test references change.

Commands, explicit functional allowlist and complete logs are retained in
`/tmp/samgita-v335-final-run.py` and
`/tmp/samgita-v335-functional-checks/functional-final/`. Source closure and
binding use `/tmp/samgita-v335-source.py` and `samgita-v335-bind.py`.
The three failed development oracles remain in
`/tmp/samgita-v335-owning-501432.log`,
`samgita-v335-owning-after-context-501432.log` and
`samgita-v335-owning-after-identities-501432.log`.

| Evidence | SHA256 |
| --- | --- |
| Final command results | `679323d7ccfacf2e6afb6761006dd676d1fcb55196a79644b94ff5c73d125bab` |
| Source guard | `8dab36044d9029e6da1187aad4040e2172373595f2cfbe5cd7773c06284c49fa` |
| Whole-source/schema closure | `0737b01d38e51ac73690cc6f1f7b524424424c2c4d270c7689cc13dc61b86a8e` |
| Manifest | `0eee0e39b1187ce12f867436b7454b1356028ef9fb3441c1774d945a218de70d` |

Inventory consistency passes; strict completeness still exits1. Counts remain
**462 implemented /12 missing /11 blocked** requirements and
**4,996 implemented /1,559 missing /66 blocked** contracts, zero verified.

Ordinary native starts use fixed yolo setup only. No security, credential,
authentication, authorization, permission or approval tests/audits are run.
Broad suites and hosted workflows remain unrun under the user's restriction.
A11, unavailable external/platform success, full-goal/release gates, publication
and deployment remain incomplete. This local fake-model qualification does not
establish a real provider integration or a released/deployed package.
