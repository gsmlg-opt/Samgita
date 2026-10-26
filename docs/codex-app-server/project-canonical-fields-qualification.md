# Canonical Project root and sorting inputs

This evidence-only unit binds three canonical ClientRequest nodes to unchanged
current native tests. It adds no executable source, fixture or test and reruns
no test. The owning module was included in the immediately preceding final
48-file functional matrix:97/0 at both seeds501432/987654. All296 guarded
current and committed sources match that exact tested code.

## Exact input graph and effects

Only ProjectRoot.path299, ProjectSortKey.position300 and
ProjectSortKey.recencyAt301 become implemented. Each exact node/hash is resolved
independently from the experimental ClientRequest export. Actual request routes,
rather than shared hashes, bind them:

- ClientRequest.oneOf[48] project/create → ProjectCreateParams.roots.items →
  ProjectRoot.path → AbsolutePathBuf.
- ClientRequest.oneOf[46] project/list → ProjectListParams.sortKey.anyOf[0] →
  ProjectSortKey, with actual position and recencyAt literals.

Official protocol/common.rs:779–794 maps those same methods to the actual v2
params consumed by the native server. Existing direct v2 owners4940/4961/4962,
other aliases and all sibling fields stay unchanged.

apps/samgita_codex_driver/test/native_project_sort_matrix_test.exs:128 creates
private existing beta/alpha directories in that deliberate caller order. It
captures full encoded project/create params and matches the native response ID.
An independent read-only SQLite query joins committed Project/idempotency data
and requires exact ordinal/path roots. The entire Project map fixes actual ID,
name, metadata, paths, position0, recencyAt:null and observed SQL timestamps
converted to seconds. The original native closes/reaps; a distinct native reads
the identical full Project and committed roots/times. Both directories stay
empty; provider count stays zero. No native storage is seeded or rewritten.

The position case at74 creates four actual Projects and moves the last before
the first. Both directions must match the independently known ID order. Full
lists and every one-item page equal a complete independent Project ledger; exact
cursors match actual position/ID and direction. The whole matrix repeats after
native replacement without inference.

The recency case at193 interleaves empty, older, empty and newer Projects. Exactly
two genuine member turns create native recency. Independent read-only SQL
observes maximum nonarchived member timestamps, including nulls; no test writes
or backdates them. Those values/UUIDs prescribe both orders, tie breaks and
null-last placement. Both sortKey literals are captured on the real wire. Full
lists, one-item pages and exact recency/direction/time-or-null/ID cursors repeat
after native replacement. Original completed member thread/turn IDs remain in
cold history; exactly two provider requests persist.

The pinned handler projects.rs:69–112,133–151,242–264 consumes these actual
values. state/src/runtime/projects.rs:180–223,413–428 commits roots/idempotency
in order. Its434–569 query/cursor implementation selects the actual column,
direction, UUID tie breaks and recency-null placement. These native durable
effects are stronger evidence than response echo or generic forwarding.

## Current verification and binding

Pin: rust-v0.163.0, source83086188ae0614bd882818ff1aa23f3194962012, binary SHA256
399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
Five complete official files match the immutable archive; all three physical
nodes and both real request-reference graphs are checked independently.

Owning test SHA256:
3ad1f0e4557ffb4c9a58d795aa6bb30aa93f5fbb3030c2cecdd8c0f3b6805109.
Baseline52f3d42e69824d13bb61a28028328af776e83a8f and all296 guarded sources
equal the passing latest functional source. Historical V272 proof is supplementary;
no historical runtime/dependency equality is substituted for this current matrix.

Actual commands/environment and logs remain /tmp/samgita-v318-run.py and
/tmp/samgita-v318-functional-checks/functional/. That matrix passed97/0 twice,
compile/format/strict Credo, outside actual-binary consumer1/0 and27 fixture ASTs.
This indexing unit runs only source/node/reference/binding and inventory checks.

| Evidence | SHA256 |
| --- | --- |
| Latest functional results | 4f5253115565585f5ea9e82918c7c8eece422764007457f5b232970c2f424f25 |
| Latest source guard | ce0533be12e99cc6e5209f28d658f8567907ec5ea9b843ebd03e2888fcacc39d |
| Five pinned files, three nodes and current-code binding | 6925b6c4c51c9232486f06f23ea22993a3a1a8a1a68690435af12e11b2bb8a2b |
| Resulting manifest | ef77417e421d45bd4444c4527ec1f9a34f1f50c38eefb51c6d3ad3ad8bbd3e30 |

Final binding preserves every schema identity/planned check, all other contracts
and all requirements. Inventory consistency passes; strict completeness exits1.
Contracts become **4,956 implemented / 1,599 missing / 66 blocked**; requirements
stay **462 implemented / 12 missing / 11 blocked**, zero verified.

Only selected existing declared roots and SQLite-backed Linux/stdio ordering
are covered. Arbitrary path/Git discovery, symlink/root authorization, cwd
execution, other stores/platforms/transports, complete Project/platform lifecycle,
external integrations and full compatibility remain unqualified. Original fixed
yolo, bounds and ownership cleanup stay unchanged. Prohibited security/auth/
permission/approval tests and broad/hosted workflows remain unrun. A11 and
release gates stay incomplete; no publication or deployment occurs.
