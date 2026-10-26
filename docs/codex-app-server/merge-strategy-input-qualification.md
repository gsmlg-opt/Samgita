# Native configuration merge-strategy unit inputs

Default validation accepts `{"replace":null}`, `{"replace":{}}`,
`{"upsert":null}` and `{"upsert":{}}` on both standard config-write paths.
Original caller maps/bytes and canonical output schemas remain intact.
Base: `bf11084ad201cdb25f85507cac5352168bed21ab`.

| Request | Required strategy path |
| --- | --- |
| config/value/write | mergeStrategy |
| config/batchWrite | edits[].mergeStrategy |

## Reproduction and correction

Protocol RED reports **5 tests /2 failures**; the actual-binary regression
reports **1/1**, rejected by local validation before its first mutation.
An exact-copy wire-validation diagnostic passes **1/0** with all eight genuine
writes. Normal corrected validation passes **5/0 protocol and1/0 native**.

The first guarded matrix stops at strict Credo: the test capture callback is
nested three levels, exceeding the existing limit of two. Extracting its exact
Agent.update body into a private helper resolves this without changing any
assertion, bounds or behavior. A second exact-one-line wire diagnostic and
normal native GREEN both pass **1/0** on that final helper. Earlier logs and the
failed `final/` matrix remain separate from the later `qualified/` matrix.
Delivered tests use normal validation; no runtime bypass or gate exemption.

Target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Seven complete protocol, handler and merge-consumer sources match their unique
archive members. Existing serde source/license/origin and Cargo.lock bindings
remain checked. Complete `v2/config.rs` is added verbatim as `source/config.rs`.

`config.rs:337–343,1101–1136` declares the camelCase unit enum and required
non-Option fields. The buffered ClientRequest decoder accepts exactly one known
key with null or empty-map unit payload, including within batch arrays. These
are present strategies; outer null or omission is invalid and has no default.
The arbitrary JSON `value` field remains required, including when its value is
explicit null. Native deletion semantics are separate from this fixture.

The fourteenth source-derived input descriptor wraps the unchanged canonical
string enum with only those disjoint object branches. Exactly two stable/full
request graphs reach it. Both methods remain standard, with no invented gate,
normalization, local default or new output representation. The generator guards
exact enum/params/method/buffering declarations, required fields, six raw files
and both array-aware property-reference graphs. Provenance adds only the new
source and descriptor. All thirteen prior descriptors, existing pins and770
official exports retain their bytes; no physical schema owner is added.

## Actual persisted merge behavior

The isolated fixture seeds an ordinary desktop table with theme dark and
preventSleep true. All eight original object requests target that table only:

| API | Object | Patch | Expected desktop |
| --- | --- | --- | --- |
| Single | replace:null | theme light | theme light |
| Single | replace:{} | preventSleep false | preventSleep false |
| Single | upsert:null | theme dark | theme dark, preventSleep false |
| Single | upsert:{} | theme light | theme light, preventSleep false |
| Batch, one edit | replace:null | theme dark | theme dark |
| Batch, one edit | replace:{} | preventSleep true | preventSleep true |
| Batch, one edit | upsert:null | theme light | theme light, preventSleep true |
| Batch, one edit | upsert:{} | theme dark | theme dark, preventSleep true |

Here theme is the existing `appearanceTheme` key. Each Replace removes a key
that was present immediately before it; each Upsert preserves a concrete other
key while adding/changing theme. Every request changes content. A decoder that
treats every object as one strategy cannot satisfy these independent expectations.

Every write supplies the immediately current native expectedVersion and must
return status ok, the owned config path and a new adjacent version. Its following
actual config/read must report that version and exactly the expected desktop,
with all original non-desktop user-layer configuration and metadata retained.
The owned config file must change after each write. Historical versions need
not all be unique: the final logical desktop returns to its initial value.

After closing/reaping the original owned PID, a distinct pinned replacement
reads the final configuration once. The entire user layer/version and final
file bytes/hash remain exact, as do catalog, support/provider/test sources and
the empty provider journal. There are exactly **ten config reads, eight writes
and zero inference calls**. Native layer reads follow the real disk-backed
configuration loader; this is not a claim of an fsync guarantee.

Original request maps, literal nested objects, bytes and correlation IDs are
checked after successful send. Capture is **8/12 write frames**, each at most
4KiB; the config-read counter is separately bounded at ten. The existing60s
case,5s request/initialize,1MiB snapshots and owned cleanup remain enforced.
No blind mutation retry or execution is introduced.

This qualifies the four shapes on an ordinary table in single/one-edit batch
writes. Arbitrary configuration keys, null deletion, mixed-edit atomic failure,
concurrent writers, overridden layers, hot reload, every transport/OS and
per-object cold writes remain unqualified. Canonical configuration behavior is
recorded separately in [configuration qualification](configuration-qualification.md).

## Evidence, limits and rollback

Final commands, logs and source bindings belong in
`/tmp/samgita-v367-functional-checks/qualified/`, with source/runner/binder
`/tmp/samgita-v367-{source,run-qualified,bind}.py`. The independent final source
review is `/tmp/samgita-v367-final-review.md`. All eleven qualified matrix
commands pass: **82/0
schema and137/0 ordinary driver cases at501432/987654**, outside consumer
**1/0**, compile/format, strict Credo537 and inventory. Native blocks take
206.753/194.110 seconds. The367-source guard stays exact, including359 unchanged
other prior sources, thirteen prior descriptors and770 official exports.
Root warning-free compile, format, assets, forced Dialyzer, both architecture
scanner commands and local production compile/assets/assembly also pass against
unchanged sources. Assembly uses synthetic configuration without application
startup, database migration, publication or deployment.

Only supplemental requirement evidence changes. Alternate input forms cannot
promote complete requirements, physical owners or verified states. Counts remain
**5,038 implemented /1,517 missing /66 blocked** contracts and **462 implemented
/12 missing /11 blocked** requirements, zero verified. Inventory consistency
passes; `inventory.py --require-verified` still exits1 on unverified requirements.
Prohibited
security/credential/authentication/authorization/permission/approval tests,
audits, mixed broad suites and hosted workflows remain unrun/incomplete. A11,
producerless legacy, unavailable external/platform profiles and full
compatibility remain incomplete. No tag, publication, service start or deployment.

Rollback removes this source/descriptor and their provenance additions,
derivation, input helper and related tests/evidence together. Preserve the prior
thirteen corrections and every native/platform history. No platform migration,
redispatch or Task acceptance is involved. Continue with the twenty source-kind
unit inputs and honest populated-filter evidence; positive producers for all
other source kinds remain separate qualification.
