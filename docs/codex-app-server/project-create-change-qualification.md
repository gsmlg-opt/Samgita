# Native project creation, changes and durable deletion

This extends the ordinary project sort case on immutable Codex `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Base repository commit: `6992e3e`. The actual app-server produces every response
and notification. Owned synthetic providers supply assistant text only for the
retained recency case; creation, move and empty-project deletion require zero
provider calls. No Samgita, Repo, PostgreSQL or external service starts.

## Independent observations

| Exact physical owners | Native behavior and independent oracle |
| --- | --- |
| 4946–4950, ProjectCreateResponse Project.id/metadata/name/position/recencyAt | Four creations preserve literal names and nonempty metadata, initial positions 0–3 and explicitly present null recency. Read-only native SQLite selects IDs by requested key/name, independently of response IDs; all four IDs must differ. |
| 4940, ProjectCreateParams ProjectRoot.path; 4951, ProjectCreateResponse Project.roots | A separate creation declares two owned absolute directories in beta-before-alpha order. Captured params, literal response roots and SQL position/path rows must agree. No Git discovery, thread or execution is needed. |
| 4945/4952, ProjectCreateResponse Project.createdAt/updatedAt | Host milliseconds bracket the creation. Independently selected SQL timestamps must be equal and within that bracket; each API timestamp must equal its stored milliseconds divided by 1000. |
| 2348–2350, canonical ServerNotification ProjectChangeType.created/updated/deleted | Genuine notifications have no request ID and exact projectId/changeType params: four created notices, the actual last-before-first move's updated notice, and the deleted target's deleted notice. Scripted notifications are not used. |

The new deletion case starts with four owned empty projects and records complete
survivor API records and native storage. Deleting one middle project must return
the native empty response and emit its actual deleted notice. Full and one-item
list pages preserve the exact three survivors and position gap. Reading the
target returns code `-32602` and exact message `project not found: <id>`.
Read-only SQLite must lose only the target project; all four original
key→project_id mappings remain and the thread count remains zero. The snapshot
checks mapping key/ID columns, not mapping timestamps.

Confirmed owned-process exit precedes cold startup against the same synthetic
home. The complete deletion/survivor/storage checks repeat. The roots/timestamps
case likewise preserves its complete public record and independent stored
values after restart. Workspaces and declared directories stay empty. Ready
phase, no pending requests, no uncertainty, no gaps and unchanged zero-request
provider journals remain asserted. Existing position/recency/cursor/error/
history oracles and checked cleanup are preserved.

Capture remains bounded to 256 frames of at most 4096 bytes. Change collection
drains the ordinary Session queue, observes availability notifications and has
fixed limits of 256 events, 1 MiB and five seconds. No state-changing call is
retried, and no deadline is increased.

## Immutable production semantics

The actual
[processor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/projects.rs#L145)
sends created/updated/deleted notifications only after store operations return.
Its API conversion preserves roots and divides millisecond timestamps by 1000.
The
[creation transaction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/projects.rs#L180)
uses one current millisecond value for both timestamps, appends position after
the current maximum, and stores roots in caller order. These are real SQLite
effects observed through a read-only connection, never fixture-seeded outputs.

The
[delete transaction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/src/runtime/projects.rs#L339)
removes the target and leaves survivor positions unchanged. The
[migration](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/state/migrations/0049_projects.sql#L18)
deliberately gives project_idempotency_keys no project foreign key; deletion
retains historical mappings. This test has no member threads and does not
qualify member detachment. The notification schema's concrete project/changed
branch references the canonical ProjectChangeType enum; same-shaped response
aliases do not receive this evidence.

All five complete inspected source files byte-match the pinned source archive;
all twelve exact node digests and corresponding experimental exports match the
inventory. Four embedded read-only SQLite Python scripts parse successfully.
Independent source reviews find no actionable issue in the notification/delete
or roots/time oracles. Runtime libraries, shared helpers, dependencies and
application configuration are unchanged. Yolo is fixed owned-launch setup;
there are no permission assertions.

## Qualification boundary

The final twenty-five reviewed functional files are the same explicit list as
the [cold-search unit](cold-search-persistence-qualification.md#final-checks-and-limits).
Both mix test commands use warnings as errors and seeds 501432/987654; each
passes **43 tests / 0 failures**, in **77.677/77.661** command seconds.
Scoped format, warning-free compile, root strict Credo on 477 files, outside
actual-binary consumer **1/0**, three Python fixture AST checks and the
**251-file** unchanged-source guard all pass. All eight commands complete.

Exact commands/environment/logs/final-source hashes:
`/tmp/samgita-v272-functional-checks/functional/`. Results/source SHA256:
`e87dbbabeaffe596a56e9a392b2aa31e3f5c57262f7f3e76da6b5fa0596a6a41` /
`e47dc9818620bd420420878bdb24e7902a909084ab8962e3ad10e5d4a00e8516`.
The adjacent source-evidence.json SHA256 is
`ca0c709be5b518df14b74460b26bd4448e89b68e836251f8d3e867dff28ff36e`;
owning test SHA256 is
`3ad1f0e4557ffb4c9a58d795aa6bb30aa93f5fbb3030c2cecdd8c0f3b6805109`.
manifest-binding.json records all twelve original/current rows and binds the
final test, immutable source proof and successful matrix.

The initial v267 format-only check fails on a missing blank line and runs no
native case; formatting is corrected without assertion or deadline changes.
The v268 **2/0**, v269 **3/0**, v270 **42/0 twice** and v271 **4/0** results
pass but precede the final roots order/no-request-ID assertions. They remain
intermediate evidence, not substitutes for the final block. There is no native
runtime failure in this unit.

`python3 -B scripts/codex/inventory.py --check` passes. Contracts become
**4,727 implemented / 1,835 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, with zero verified in both.
The unchanged strict command with `--require-verified` exits **1** because
unverified requirements remain. It executes no security tests and remains a
failed full-compatibility gate.

Only the twelve listed rows receive scoped implemented evidence. No whole
method, enclosing Project/notification, read/list/update alias, arbitrary
metadata/path normalization, nonnull creation recency, later update timestamps,
member deletion, permission behavior, other OS/backend or transport is qualified
by these cases. All existing planned tests and schema identities stay intact.

Security/permission tests, related audits and broad/hosted workflows remain
unrun under the user's restriction. Full compatibility, A11, immutable
upstream-unreachable legacy emission, real external/platform acceptance and
release remain incomplete. No publication, production migration or deployment
occurs.
