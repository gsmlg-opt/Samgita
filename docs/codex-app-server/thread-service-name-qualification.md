# Thread provenance from serviceName

This ordinary functional unit starts from
`c1cb6802ac07c47cafaf67dc32b6ce6ae4e0b1c5` on the existing `main`. One new
test uses the unchanged local assistant provider and real Codex app-server.
Production code, shared fixtures, schemas, configuration and locks are unchanged.
Fixed YOLO is launch setup; no security or permission behavior is exercised.

Target: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The source archive SHA256 remains
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Final [test](../../apps/samgita_codex_driver/test/native_thread_service_name_test.exs)
SHA256: `72cbe960a9c982d23eaa0b67bc10c232ad627c96fd9847e9308f839413b5183d`.

## Native behavior and exact owner

Only physical owner **6347** is selected:
`schema:v2/ThreadStartParams.json#/properties/serviceName`, canonical-node SHA256
`cd49941f1a90808c0c692f85bc803a6dd936c9153aaac4a725cf9030c3fc9089`.
The native [start processor:1162,1523][start] forwards the optional field to
`StartThreadOptions.metrics_service_name`. [Originator selection:373–400][select]
trims the string and recognizes five names without ASCII case sensitivity;
unknown values fall through the ordinary provenance chain. Initialization
establishes the default client name. Twenty-eight complete source files match
their unique members in the immutable source archive, including initialization,
creation, persistence, timestamp conversion and public reads.

Six distinct persistent threads are created sequentially in one native process:

| Original serviceName | Independently prescribed originator |
| --- | --- |
| Omitted | `owned_thread_service_name` |
| `  CoDeX_WoRk_DeSkToP  ` | `codex_work_desktop` |
| `CHATGPT_CCA` | `chatgpt_cca` |
| `owned-service-λ` | `owned_thread_service_name` |
| Explicit null | `owned_thread_service_name` |
| Omitted again | `owned_thread_service_name` |

Exact original request maps/encoded bytes, unique RPC IDs and actual correlated
responses are retained. Every creation response and actual `thread/started`
notification must independently contain the prescribed literal originator
before any inference for that thread. Null and absence remain distinct in the
outgoing wire. Later overrides must not relabel any previously created thread.

Each thread then completes one uniquely marked assistant turn. Exactly six
provider requests retain independent native thread/turn metadata and only their
own marker. Native user/assistant item identities correlate start and completion;
full legacy history retains every item field with the source-defined readback
IDs `item-1`/`item-2`. Canonical SessionMeta independently records each originator.
Warm repeated full reads remain identical. A new process with a different
initialized client reads all histories without loading or resuming them; the
six saved originators survive unchanged, with no new inference.

## Timestamp failure and corrected independent oracle

The first focused run passes **1/0**. The first two-file matrix then fails
**2/1** when one completed turn crosses a wall-clock second: full cold read
`updatedAt` differs from the warm value. That failure remains recorded.

The [warm legacy path:57–88][read] refreshes metadata-only display fields from
the rollout head. [Head parsing:876–884,1026][head] supplies creation time without
an updated-time override. The cold full-history path retains indexed SQLite
metadata. Three additional runtime fields also differ by construction: status
becomes `notLoaded`, and environments/direct-input metadata become null.

An intermediate mtime-only correction passes its focused and two-seed checks
but is **not accepted as qualification**. Source review shows that live append
also [touches metadata with current time:181–220,405–414][sync]; persisted
timestamps may be allocated monotonically, and an already-complete backfill
need not replace them from file mtime. Passing within one second cannot establish
an exact timestamp contract.

The final test observes the actual owned Codex `state_5.sqlite` through Python's
standard sqlite3 library in read-only mode. A bounded, parameterized query reads
only the six known thread IDs and their rollout paths, creation milliseconds
and update milliseconds. Paths and canonical creation time must match the saved
native records. Cold `updatedAt` must equal the independently observed
`updated_at_ms // 1000`, matching the pinned [storage conversion][timestamps].
The complete six-row observation must remain unchanged after all cold reads.
This is the native fixture's own state, with no Samgita Repo or platform service.

Complete cold maps are compared to the saved maps with precisely those three
runtime fields and the independently determined timestamp accounted for. All
other fields, full histories and repeated reads remain exact. Warm creation
and update timestamps also match the canonical SessionMeta timestamp. Raw
rollout bytes/hash/mtime remain stable through both process shutdowns. No field
is discarded, no response supplies its own expected timestamp, and no sleep,
retry or increased deadline is introduced. The final focused case passes **1/0**.

## Final permitted checks and limits

The new case plus the existing native creation-snapshot case pass **2/0 at each
seed 501432 and 987654**. Scoped formatting, driver compilation with warnings as
errors, root strict Credo (**553** files) and inventory consistency pass. All six
commands complete; all **388** guarded source files remain identical, with all
**387** previous sources unchanged. Earlier larger matrices and outside-consumer
results retain their original unchanged-source evidence; they are not new runs.

Exactly **49** correlated RPC pairs are required. Capture permits 128 frames
per direction, 4KiB outgoing/65KiB incoming and 1MiB combined; event and file
checks retain their 256-event/1MiB limits. SQLite observations cover six rows,
8KiB output and a one-second database wait. RPC/init/creation bounds stay 5s,
turn bounds 20s and the case 60s. Inputs, helper/provider/catalog/config bytes,
six-call journal and empty workspace stay unchanged. Both native processes
close with owner completion, closed Port and absent owned PID.

Only 6347 gains scoped implemented evidence. Requirements remain **462
implemented /12 missing /11 blocked**; contracts become **5,078 implemented
/1,477 missing /66 blocked**, with zero verified in both. Other recognized
names, empty strings and inherited/resumed provenance remain unqualified.
No sibling schema, endpoint or deployment inherits acceptance.
Inventory consistency passes; strict completeness still exits **1** because
unverified requirements remain.

Final command arrays/logs and source guard:
`/tmp/samgita-v389-functional-checks/final3/`, runner
`/tmp/samgita-v389-run.py`; source binding is in `archive-evidence.json`.
The initial failing matrix remains under `final/`, the unaccepted mtime-only
matrix under `final2/`, and focused versions/logs under
`/tmp/samgita-v389-native/`. Source diagnosis/review records are
`/tmp/samgita-v389-cold-timestamp-cause.md` and
`/tmp/samgita-v389-final-review.md`.

Prohibited tests, audits, mixed broad suites and hosted workflows remain unrun.
A11, unavailable upstream producers, external/backend/OS/platform success and
full compatibility/release gates remain incomplete. No publication or deployment
occurs. Rollback removes only this test and its evidence mapping; no production
state, migrations or historical records change.

[start]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L1523
[select]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/thread_manager.rs#L373-L400
[read]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/read_thread.rs#L57-L88
[head]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rollout/src/list.rs#L876-L884
[sync]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/thread_metadata_sync.rs#L181-L220
[timestamps]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6430
