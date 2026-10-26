# Native project-sort key unit inputs

Default validation accepts four native `project/list.sortKey` objects:
`{"position":null}`, `{"position":{}}`, `{"recencyAt":null}` and
`{"recencyAt":{}}`. The experimental method gate, caller bytes and canonical
outputs remain intact. Base: `443ef908d6b6fbe487330c5fcedcd9d772a704e2`.

## Reproduction and correction

Before the correction, the protocol regression reports **5 tests /3 failures**
and the real-native regression **1/1**, rejecting the object locally before it
reaches Codex. An exact-copy native diagnostic changes only the helper's
validation option to `:wire` and passes **1/0**. After the correction, default
validation passes **5/0 protocol and1/0 actual-binary**. The diagnostic stays
outside the repository; delivered tests use normal validation.

Target remains official `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Five complete protocol/handler/state sources match their unique archive members.
Pinned serde source, license, origin and Cargo.lock bindings remain checked.

`project.rs:38–59` declares the camelCase unit enum and optional sort key. The
internally tagged ClientRequest buffers parameters through pinned serde, which
accepts one known key with a null or empty-map unit payload. Official JSON
exports describe string keys only. Fresh property-reference traversal finds
exactly one reachable full input path, `project/list.sortKey`. The stable bundle
contains an unused enum definition, without that method, params definition or
standalone export; it does not make project listing a standard operation.

The twelfth derived input descriptor wraps the complete canonical schema in an
input-only union. It composes with SortDirection without rewriting requests,
adding output variants, setting defaults or relaxing enclosing constraints.
Malformed names, extra keys and non-unit payloads remain invalid. Outer null or
omission differs from an object with a null unit payload: that object selects a
present key. The native handler retains its `sortDirection requires sortKey`
rule, Position/ASC and RecencyAt/DESC defaults, and cursor behavior.

The generator guards the exact enum, field declarations/defaults, buffered
decoder, method gate, full/stable exports and actual reference graph. Provenance
adds only the new descriptor. All **eleven prior input descriptors**, every
previous pin and **770 official exports** retain their bytes. There is no new
physical schema owner, dependency, platform migration or runtime change.

## Independent native ordering and persistence

The native test publicly creates four projects P(empty), Q(older active),
R(empty), S(newer active), then moves S before P. Those operations prescribe
Position ASC as S/P/Q/R and DESC as its reverse. Read-only, query-only native
SQLite observations independently check positions, keys, roots, metadata and
creation/update times against complete project responses.

Q and S each receive one genuinely completed assistant-only native turn in a
project-associated paginated thread. Original native events establish distinct
turn/item IDs, content and positive ordered timing. The two inference requests
contain the expected thread/turn association and original input. A bounded
clock precondition makes Q's persisted recency strictly older than S's.
Read-only native columns prescribe RecencyAt order independently of list
responses: active projects first, empty projects last in both directions, with
directional ID ties. Both recency orders must differ from position order.

All four objects combine with direction omitted, outer null, scalar ASC and
scalar DESC: **16 complete pages warm and16 unloaded cold**. Each page must
equal the independently prescribed complete project rows, with a null terminal
cursor. Exact original request maps, literal object bytes and response IDs are
checked after successful transport send. The new capture budget is **41/48**
frames, each at most4KiB; it does not widen a previous budget.

The original owned native PID must be closed and gone before a distinct pinned
replacement starts over the same fixture. All cold list queries precede history
reads and keep runtimes unloaded. No resume occurs. Complete native project and
thread records, both original rollout snapshots, IDs/content/timing, config,
catalog, provider source and request journal remain exact. There are exactly
two inference calls, no new turn/item events, no pending/uncertain operation or
gap, and an empty workspace. Existing case60s, turn20s, request5s, clock2s and
bounded collector/snapshot/cleanup limits remain enforced.

These are complete `limit:100` pages in a full negotiated stdio session. They
do not qualify continuation cursors, archived membership, every storage or
transport profile, or real-provider success. The local model peer supplies
assistant output; the immutable Codex binary owns decoding, ordering and state.

## Verification boundary and rollback

The final reviewed matrix and exact source/log bindings are recorded in
`/tmp/samgita-v365-functional-checks/`; source guard, runner and binder are
`/tmp/samgita-v365-{source,run,bind}.py`. Independent source reviews are
`/tmp/samgita-v365-{independent,final}-review.md`. All eleven matrix commands pass:
**72/0 protocol and135/0 ordinary driver cases at both501432/987654**, outside
consumer **1/0**, warning-free compile/format, strict Credo on533 sources and
inventory. Native blocks take199.427/205.354 seconds. The360-file source guard
stays exact; all353 other prior sources remain unchanged.
Root warning-free compilation, format, assets, forced Dialyzer and both legacy
architecture scanner commands also pass against those unchanged sources.
Local production compilation, minified assets and release assembly pass with
synthetic configuration and no application startup. Publication remains blocked.

Only supplemental requirement evidence changes. The ledger remains **5,038
implemented /1,517 missing /66 blocked** contracts and **462 implemented /12
missing /11 blocked** requirements, **zero verified**. Contract and requirement
states cannot be promoted by these alternate inputs. Inventory consistency passes;
`inventory.py --require-verified` still exits1 on unverified requirements.
Security/credential/
authentication/authorization/permission/approval tests, audits, mixed broad suites
and hosted workflows remain prohibited and unrun/incomplete. A11,
producerless legacy, external/OS/platform profiles and full compatibility remain
incomplete. No tag, publication, service start or deployment is authorized here.

Rollback removes the descriptor/provenance entry, derivation, input branch and
associated tests/evidence together. Preserve previous corrections and every
native/platform history. No database migration, redispatch or Task acceptance is
involved. Next reproduce the six TurnItemsView unit objects on turn listing and
resume's initial page, retaining their canonical described schema and actual
item-view semantics.
