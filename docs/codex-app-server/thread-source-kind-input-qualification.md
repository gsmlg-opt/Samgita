# Native thread-source filter unit inputs

Default validation accepts the twenty native unit-object forms of
`ThreadSourceKind` inside `sourceKinds` arrays, preserving original caller maps,
literal arrays, ordering and bytes. Base:
`481e2050e0ad0ca4af61429347f90b7766dbced7`.

| Request | Path | Availability |
| --- | --- | --- |
| thread/list | sourceKinds[] | Standard |
| thread/search | sourceKinds[] | Experimental method |

The exact keys are `cli`, `vscode`, `exec`, `appServer`, `subAgent`,
`subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`, `subAgentOther` and
`unknown`; each accepts null or an empty map as its unit payload. The explicit
`vscode` rename is significant; `vsCode` and `vs_code` remain invalid.
`unknown` is an actual enum value, not a wildcard.

## Reproduction and correction

Protocol RED reports **5 tests /2 failures**. The actual-binary regression
reports **1/1**, rejected locally before its first object-filter query. An
exact-copy wire-validation diagnostic passes **1/0** without altering any input,
oracle or deadline. Normal corrected validation passes **5/0 protocol and1/0
native**.

The first guarded matrix stops at strict Credo's nonempty-list predicate
warning. Replacing `length(lines) > 0` with `lines != []` retains the same
nonempty condition, the independent256-record bound and every other assertion.
The final helper passes a second exact-one-line wire diagnostic and normal
native GREEN, both **1/0**. The failed `final/` matrix remains separate from the
later `qualified/` matrix. Delivered tests use normal validation.

Target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Twelve complete protocol, dispatcher, filtering, producer and persistence
sources match their unique archive members. Existing serde source/license/origin
and Cargo.lock bindings remain exact.

`v2/thread.rs:1517–1533` declares the ten unit variants. The internally tagged
ClientRequest's buffered serde decoder accepts exactly one known key with null
or empty-map unit payload, including inside arrays. The fifteenth source-derived
input descriptor composes with the existing list/search sort corrections;
canonical string schemas and outputs remain untouched. The generator guards
five actual raw schema files, the exact property/array reference graphs, enum,
rename and request declarations. Provenance adds only this descriptor. All
fourteen prior descriptors, existing pins and770 official exports remain exact;
no physical schema owner is added.

Outer `sourceKinds` remains an optional nullable array with nonnullable elements.
Omission, null and an empty array retain their original representations. Native
defaults also include custom `atlas`/`chatgpt` sources; list with an explicit
relation and None has a separate source-filter exception. These are source
contracts, not newly qualified default/relation behaviors. A null payload inside
a unit object still selects a present source filter.

## Actual populated cold filtering

The stock app-server genuinely produces `vscode` sessions, as bound independently
to `cli/src/main.rs:1281–1291` and canonical persisted SessionMeta. Calling the
transport app-server does not make the source `appServer`/Mcp.

One owned native process creates a paginated thread and completes one ordinary
turn through the local deterministic model provider. Actual user/assistant item
IDs, content, original turn and item times, provider correlation, full history
and raw rollout/source records are retained. A synchronous native read observes
history; it does not claim to force an fsync.

After closing/reaping that PID, a distinct pinned cold process performs all
**forty discovery queries before any history hydration**: twenty singleton object
filters through each API. List explicitly uses the state database. Both
`vscode` forms return the one known persisted row with the prescribed eight-field
projection and exact search snippet. The eighteen other forms return empty
terminal pages, excluding that populated row. Independent list read receipts
remain preserved without gaining whole-response qualification.

The reader then returns the exact original full turns/items/timing, path and
preview. Discovery leaves loaded-list empty and introduces no inference, gap or
uncertain operation. Raw rollout/SessionMeta, config, catalog, provider journal
and support/test inputs retain their bytes/hashes. Both owned PIDs are reaped.
There are **42/48 captured frames**, each at most4KiB, and **one inference
request**. Existing60s case,20s turn,5s request/initialize,256-event/1MiB collector
and1MiB snapshots remain bounded.

The other eighteen forms prove accepted input and populated exclusion only.
They do not provide positive producers or distinguish matching among those nine
absent kinds. Object-specific warm discovery, custom/default/relation behavior,
mixed-OR effects, cursor continuation, other storage/history/transports/platforms
and cold resume remain unqualified. Prior canonical source tests retain their
own evidence without automatic promotion.

## Verification and rollback

All eleven final matrix commands pass: **87 schema /138 ordinary driver cases
at501432/987654**, outside native consumer **1/0**, compile/format, strict
Credo539 and inventory consistency. Native blocks take204.278/206.883 seconds.
The370-source guard stays exact, including363 unchanged other prior sources,
fourteen prior descriptors and770 official exports. Logs and source bindings are
under `/tmp/samgita-v368-functional-checks/qualified/`, with runner/binder
`/tmp/samgita-v368-{source,run-qualified,bind}.py`; the independent source review
is `/tmp/samgita-v368-final-review.md`. The earlier failed `final/` matrix is
retained separately.

Root warning-free compilation, format, assets, forced Dialyzer, both architecture
scanner commands and local production compile/assets/assembly also pass against
the unchanged sources. Assembly uses synthetic configuration without starting
the application or applying a database migration.

Only supplemental requirement evidence changes. Alternate input forms do not
promote complete requirements, physical owners or verified states. Counts remain
**5,038 implemented /1,517 missing /66 blocked** contracts and **462 implemented
/12 missing /11 blocked** requirements, zero verified. Inventory consistency
passes; `inventory.py --require-verified` still fails on unverified requirements.
Prohibited
tests/audits, mixed broad suites and hosted workflows remain unrun/incomplete.
A11, producerless legacy paths, unavailable external/platform success profiles
and full compatibility remain incomplete. No tag, publication or deployment.

Rollback removes this descriptor/provenance addition, derivation, input helper
and related tests/evidence together, preserving the fourteen prior corrections
and every native/platform history. No platform migration, redispatch or Task
acceptance is involved. Continue with a genuine tool-containing turn to qualify
the richer Summary-versus-Full filtering left open by the two-item fixture.
