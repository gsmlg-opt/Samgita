# Native detected connector facts and persisted candidates

One functional scenario qualifies eleven exact response owners on immutable
Codex `rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, executable
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official process reads six sanitized, owned foreign-source fixture files
through public detection APIs. No other Agent, model turn, remote connector or
actual session import runs. Samgita's database is not required.

## Independent source facts and native persistence

Two Claude JSONL sessions and their matching local metadata manifests name
Owned Atlas. One Cursor transcript and its metadata name Owned Echo. The
historical tool-use record in the Cursor file is parsed input data, never an
executed tool call. Independently prescribed source files establish the names,
per-source session counts and provenance before native detection:

| Native detection source | Expected candidate | Count | Detection source field |
| --- | --- | --- | --- |
| claude-code | Owned Atlas | 2 | remoteMcpServersConfig |
| cursor | Owned Echo | 1 | sessionToolUse |

Actual detected session paths and cwds must match those three prescribed source
files and the existing owned workspace. Fresh fixture file mtimes satisfy the
pinned detection age filter; parsed message timestamps are separate content.
No native database, ledger or rollout is edited to manufacture a result.

Nine exact captured public requests and their owning native response IDs cover
baseline history read, Claude detect/read, Cursor detect/read, successful repeated
Claude/Cursor detection and read, then a cold history read. Every
externalAgentConfig/import/readHistories request has params:null, matching the
pinned Option<()> contract. Capture remains bounded to 32 frames/4096 bytes;
request/initialization bounds remain 5 seconds. Repeated detection follows
confirmed success and tests per-source aggregation, not ambiguous-loss retry or
idempotent import execution.

The pinned processor persists detected candidate records before responding.
Its readHistories implementation merges detected records with actual imported
records and calls them ExternalAgentImportedConnectorCandidate. It also assigns
remoteMcpServersConfig to **every** candidate, including Cursor's sessionToolUse
candidate. The test explicitly requires this upstream projection: Atlas/2 and
Echo/1 both have the fixed remote source, while **data remains []**. This is
persisted candidate evidence; the API name supplies no evidence of actual import
or original Cursor provenance. Expected outputs are prescribed independently,
not copied from earlier responses.

After successful repeated detection, counts remain 2/1. The first native process
closes with confirmed disappearance. A distinct hash-checked native PID cold-reads
the same exact candidate projection without another detect or import request.
All six input byte strings/hashes, configuration and empty provider journal stay
unchanged. Loaded threads remain empty; no pending request, uncertainty or gap
remains. Existing captured-connection cleanup covers both owned sessions.

Eighteen full production-source files match pinned archive bytes. The
[detect processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/external_agent_migration/processor.rs#L133)
and native session ledger explain persistence; its
[history projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/external_agent_migration/processor.rs#L375)
explains the relabeling. Exact fixture/source/owner mapping is retained in
`/tmp/samgita-v213-external-candidate/`, implementation in
`/tmp/samgita-v218-external-implementation/`, and independent review in
`/tmp/samgita-v220-external-review/`. Review found no actionable functional defect.

## Exact owners and final checks

Only **3958–3963/3972–3976** become implemented: detection connector
name/sessionCount/source, its two source values and connectors array; history-read
candidate name/sessionCount/source, its one source value and connectors array.
Owners **3967/3968** remain incomplete. Empty actual history does not establish
completed/failure import records, and a separate record-only API cannot prove
actual import. No aliases, whole schemas, setter/import methods or other fields
inherit evidence. Schema identities/hashes and requirements remain unchanged.
Contracts become **4,671 implemented / 1,891 missing / 59 blocked**; requirements
stay **462 implemented / 12 missing / 11 blocked**, zero verified in both.

The final eighteen-file block is the seventeen files in
[native I/O qualification](native-io-values-qualification.md#exact-owners-and-final-checks)
plus `test/native_external_connector_values_test.exs`. Both complete runs with
`--warnings-as-errors --seed 501432` and `--seed 987654` pass **32/0**, in
**54.431/54.934** command seconds. Format, warnings-as-errors compile, root strict
Credo and the **241-file** unchanged-source guard pass. No runtime failure,
deadline increase or weakened assertion occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v219-external-checks/functional/`.
Results/source SHA256:
`3727be872b17871c875b112cb618d41a3cbe97dd36881cdcf026bc00543d5cdb` /
`bfc7028d926d4ea95ec386114391299c49479d92245d59327f8dcad21a6d7629`.
The adjacent `manifest-binding.json` retains original/current eleven rows and
final test SHA256
`a5d1bbc97d01520ee3ca269d51ac085eaad6c01e5ee210ba120bca49e146a9e7`.
Runtime libraries/dependencies remain unchanged; earlier outside-consumer
evidence is retained rather than counted as a new run.

Actual imports, completed/failure histories, live other Agents, remote connectors,
other source variants and other transports/backends/platforms remain unqualified.
Security/permission checks and related broad/hosted workflows remain unrun under
the user's restriction. Full compatibility, A11 and release remain incomplete;
no publication, production migration or deployment occurs. Continue source-backed
functional start/default/instruction-provenance mapping and ordinary local
collaboration-item reachability without manufacturing emitters.
