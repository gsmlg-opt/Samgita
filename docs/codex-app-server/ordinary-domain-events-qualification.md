# Ordinary native Project and read-state envelopes

V474 adds two provider-free cases against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
These are Codex-native SQLite Project/thread records, not a new Samgita domain
model or a PostgreSQL recovery qualification. All protocol messages come from
the actual executable. Neither case starts a provider, requests a turn or uses
a scripted app-server peer. Fixed YOLO is launch setup; no security, credential,
authentication, authorization, permission or approval behavior is tested.

The Project case materializes an empty durable paginated thread with
`thread/name/set`. Actual import commits the Project and membership, producing
two notices. Durable-key replay preserves both without another notice. Updating
name, roots and metadata produces one notice; repeating the identical update
produces none. Deletion produces a Project-deleted notice followed by null
thread membership. Native read/list queries independently require every
committed state. Exactly five complete original selected frames must equal the
consumed events in order, with prescribed IDs/change types/null membership,
bounded emission timestamps, current generation and positive unique sequences.
Each notice lies between the actual mutation request and correlated reply.
A distinct cold native process still has the empty thread and unchanged history
bytes, with no Project. Config/workspace sentinel bytes remain unchanged.

The read-state case also persists an empty paginated thread, reads its actual
revision, and performs only positive current-revision unread then read updates.
Independent operation intent requires `firstUnread: {type: threadStart}` then
null; each native revision is a fresh nonempty opaque value. The immediate
query must match the complete committed response and original notification.
Two complete original notices preserve thread identity, timestamp bounds,
generation, ordered sequences and mutation-request/reply intervals. A distinct
cold PID/Port/session reads the exact final revision twice without loading the
thread. Complete thread projections, history and all inert input/config/catalog
bytes remain checked. No stale-revision or authority test is imported.

Both cases retain finite original-frame capture, five-second RPC/observation
deadlines, a sixty-second case deadline, bounded allowlisted request inventories
and exact correlated IDs. Project checks exact mutation/init counts; read-state
checks the complete request order/count. Checked native-owner/Port/PID shutdown
remains mandatory. Cross-review found no functional defect; its inventory-wording
correction is reflected here. Runtime evidence remains separate from review.

## Pinned production paths and physical owners

`request_processors/projects.rs:135–239,267–288` awaits committed create/import/
update/delete and direct notification sending before replying. It explicitly
orders creation before membership and deletion before null membership. The
read-state `Applied` path at `thread_read_state.rs:185–193` awaits the exact
committed projection and direct subscribed send at `65–88` before returning.
This supports the specific before-response assertions; it is not a promise for
other asynchronously published events. Eight complete producer/protocol files
match the official archive, SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

Only three physical outer nodes gain scoped implemented evidence:

| Index | `ServerNotification.json` node | Native event |
| --- | --- | --- |
| 2839 | `/oneOf/16` | `project/changed` |
| 2843 | `/oneOf/17` | `thread/project/updated` |
| 2899 | `/oneOf/3` | `thread/readState/changed` |

Each canonical subtree matches both generated and vendored stable/experimental
exports. Binding `/tmp/samgita-v474-domain-events-binding/source.json`, SHA256
`d336cbd03da6c38c38d469621d941b58d1381ce97404b913aad8cc6864608749`.
Existing method/literal/params owners remain unchanged. No nested alias,
field/default/variant, complete method/schema, other transport/OS/backend,
external success or release gains credit.

## Initial failure and focused qualification

The first read-state draft passed `includeTurns: true` on its paginated reads.
Stock Codex correctly emitted an extra `deprecationNotice`, failing the explicit
ordinary metadata inventory: **1/1**, 1.4 seconds, seed `501432`. Pinned
`thread_processor.rs:869–885` documents/emits that exact warning. This case needs
read-state and an empty thread, so the single request flag now uses the supported
`includeTurns: false`. Full empty-thread equality, original envelopes, history
bytes, notification allowlist, deadlines and every other oracle remain intact.
No warning is discarded or newly allowlisted. Initial log
`/tmp/samgita-v474-read-state-501432.log`, SHA256
`1ed2e90a0be3c7430873f5b9c0c4d657e6b912c13a54aa7a58b0906920d54be9`.

Focused commands from `apps/samgita_codex_driver`, in Devenv Elixir 1.18.5/OTP 27:

```sh
mix test test/native_project_notification_envelope_test.exs --warnings-as-errors --seed 501432
mix test test/native_read_state_notification_envelope_test.exs --warnings-as-errors --seed 501432
```

Project **1/0**, 2.1 seconds; final read-state **1/0**, 1.9 seconds. Original logs
`/tmp/samgita-v474-project-501432.log` and
`/tmp/samgita-v474-read-state-final-501432.log` have SHA256
`ce39e8e82fc833fb6e62c795ceac0ee2ac06a82d6de60ff6d8af28e640d9cb26` and
`95e17938796a74a16dd3ca171a92aae34337a9dd589c7c48df68b08d09ba1e33`.
Final Project/read-state test SHA256 are
`0c08a2326c7321226914b85273293b0da21abffbd633b3b98655e6e89879b86f` and
`6b164fdc10483341b4396424c32b6b7661968032c7e645bf1c3304e94f47ce32`.

The final combined 47-file/76-case reviewed matrix passes all **14** steps. It
includes the [settings/hook/skills work](ordinary-configuration-events-qualification.md)
and retains that unit's first failed source-guard record. Execution base is
`2d785439ed36c11fb7a2cad19c23b5aa65e6aca3` plus the scoped changes bound by
the source fingerprint below. Exact reproducible command from the repository:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v474
```

Results: **76/0** at both seeds `501432`/`987654`, 124.166/125.424 command
seconds; three selected WebSocket overflow/replay cases at each of seeds
`455834`/`501432`/`987654`, retaining thirteen excluded mixed-file cases;
outside-umbrella actual-binary consumer **1/0**. Warning-free driver/umbrella
compile, selected/root format, inventory consistency, strict Credo on 584
source files, forced Dialyzer and assets all pass. Elixir 1.18.5/OTP 27 and
Devenv's configured Bun 1.3.13 were used. All **1,663** guarded files remain
byte-identical before/after; no assertion, deadline or source-guard exclusion
changed. The earlier generated-asset mismatch is resolved by using the pinned
toolchain and rebuilding its output before taking the fresh snapshot, not by
accepting drift during qualification.

Original commands/logs: `/tmp/samgita-ordinary-v474/`. Results/source SHA256:
`04cb0c46dd206550d4272d4177c3ec10b45d27df046d56c9a569b9dfbabb9620` /
`27c2da997105a1be1669c1cc1c30b338cc83a40120e4e33ec1b40b2fd07b4558`;
command-plan SHA256
`82b314ec8ede8397ec7187cdc2b285795c723988463d325cb3ae213dedcc6454`;
reviewed fingerprint
`7b33d327c55ebdfafee8f41cf3df588bfd1e5bc40159438569d4e8f5d347b1cc`.

Counts are **5,329
implemented / 1,180 missing / 112 blocked** contracts, with **462 implemented /
12 missing / 11 blocked** requirements and zero verified in both. Prohibited
tests/audits, broad/hosted workflows, A11, unavailable upstream emitters,
real external/OS/backend success, complete compatibility and release remain
incomplete. No publication, deployment or production migration.
