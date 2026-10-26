# Native turn-items view unit inputs

Subsequent [rich canonical projection](rich-item-view-qualification.md) qualifies
Summary-versus-Full filtering with a genuine tool-containing turn. The object
fixture below retains its original two-item and cold-resume limitations.

Default validation accepts six native unit objects: `notLoaded`, `summary` and
`full`, each with a null or empty-map payload. Original values and bytes remain
intact. Base: `3d049ec00be7d89c5141084c50930596999e8db9`.

| Request | Property path | Negotiation |
| --- | --- | --- |
| thread/turns/list | itemsView | Standard |
| thread/resume | initialTurnsPage.itemsView | Present enclosing page is experimental |

## Reproduction and source-derived correction

Before correction, the new protocol regression reports **5 tests /3 failures**
and the actual-binary regression **1/1**. Local schema validation rejects the
object before dispatch. An exact-copy diagnostic changes only request validation
to `:wire` and passes **1/0** against immutable Codex. Restored default
validation passes **5/0 protocol and1/0 actual binary** after the correction.
The diagnostic remains outside the repository; no validation bypass is delivered.

Target is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The source report identifies eight complete protocol, handler and storage files;
source evidence binds their bytes to their unique archive members. Existing
pinned serde source/license/origin and Cargo.lock bindings remain required.

`thread_data.rs:412–423` declares the ordinary camelCase unit enum. Its enum
default Full differs from the request fields' omitted/null default Summary.
The actual buffered ClientRequest decoder accepts one known key with null or
empty-map unit payload. An object with a null payload selects a present view;
outer null remains absent. `thread.rs:426–430,500–509,1742–1755` defines the
optional fields and enclosing page gate. Only the list field is reachable from
standard request params; the full graph adds the nested resume field. An unused
stable page definition does not make that resume property reachable.

The thirteenth input descriptor preserves the **complete canonical described
oneOf** as its first branch and adds only the disjoint known-key object branches.
It composes with existing resume and SortDirection corrections without altering
output schemas, defaults, caller data or unrelated request paths. Malformed
keys, extra entries, non-unit payloads, required thread IDs and enclosing page
constraints remain enforced. The generator guards exact declarations/defaults,
gate/buffering source, five stable/full raw files and both property-reference
graphs. Provenance adds only this descriptor; all twelve prior input descriptors,
previous pins and770 official exports must remain byte-identical.

## Actual item projection and cold persistence

The native fixture creates one genuine paginated thread and completes two
ordinary assistant-only turns with distinct Unicode inputs. Original native
events establish four distinct item IDs, turn IDs, exact content and ordered
positive start/completion times. A synchronous full-history read must match
these facts; that read is not asserted to be an fsync barrier.

Each object reaches both consumers while loaded: six turn-list requests and
six resume bootstrap-page requests. Every complete page is independently
derived from the original full turn rows by changing only the selected view
and its prescribed items projection. NotLoaded must have no items; Summary and
Full must retain the original first-user/final-agent items and report their
distinct canonical view names. All other turn fields remain exact, with a null
terminal cursor and a bounded nonempty backwards cursor. Resume must leave
inline turns empty under `excludeTurns:true`; its page is independently checked
before comparison with the list page.

After closing and reaping the original owned PID, a distinct pinned process
reuses the same fixture. All six cold list requests precede full-history reads
and keep the runtime unloaded. Original rollout bytes, turn/item identity and
content, config/catalog, support/provider/test sources and provider request
journal remain exact. Exactly two inference calls are allowed, with no new
execution events, pending/uncertain operation or event gap. There is no cold
resume and no claim about its bookkeeping or timestamp-restoration boundary.

Capture is **21/24 frames**, each at most4KiB: one thread/start, two turn/start,
twelve turn-list and six warm resume calls. Request maps, literal nested objects,
encoded bytes and correlation IDs are checked after successful send. Existing
case60s, turn20s, request5s, collector256 events/1MiB, snapshot1MiB and owned
cleanup limits remain. No timeout increase, mutation retry or removed assertion.

The unchanged model peer produces only one user and one final assistant item per
turn. Their Summary and Full content legitimately coincides. This qualifies the
six input forms, selected views and NotLoaded projection; **richer intermediate
item filtering remains unverified**. Existing canonical defaults are tracked
separately in [resume-page qualification](resume-page-qualification.md). Legacy
history, active overlays, continuation cursors, object-specific cold resume and
other transport/storage/provider/platform profiles remain unqualified.

## Evidence and remaining gates

Exact commands, logs and source bindings belong in
`/tmp/samgita-v366-functional-checks/`, with runners and source/binding checks
in `/tmp/samgita-v366-{run,source,bind}.py`. Staging reviews and the final source
review are `/tmp/samgita-v366-{staged-tests,input-correction,final}-review.md`.
All eleven final matrix commands pass: **77/0 schema and136/0 ordinary driver
cases at both501432/987654**, outside consumer **1/0**, compile/format,
strict Credo on535 sources and inventory. Native blocks take187.986/208.254
seconds. The363-source guard stays exact, including356 other unchanged prior
sources, all twelve prior descriptors and770 exports.
Root warning-free compile, format, assets, forced Dialyzer and both architecture
scanner commands also pass against the same unchanged sources.
Local production compile, minified assets and release assembly pass using
synthetic configuration without application startup or publication.

Only supplemental requirement evidence changes; alternate inputs add no physical
schema owner or verified state. Counts remain **5,038 implemented /1,517 missing
/66 blocked** contracts and **462 implemented /12 missing /11 blocked**
requirements, zero verified. Inventory consistency passes; the strict
`inventory.py --require-verified` gate exits1 on unverified requirements.
Prohibited security/credential/authentication/
authorization/permission/approval tests, audits, mixed broad suites and hosted
workflows remain unrun/incomplete. A11, producerless legacy and unavailable
external/platform profiles remain blocked; full compatibility is incomplete.
No tag, package publication, service start or deployment.

Rollback removes the descriptor/provenance entry, derivation, input helper and
associated tests/evidence together. Preserve all prior corrections and histories.
No platform migration, redispatch or Task acceptance is involved. Continue with
the source-selected ordinary MergeStrategy input forms and their actual
configuration merge effects.
