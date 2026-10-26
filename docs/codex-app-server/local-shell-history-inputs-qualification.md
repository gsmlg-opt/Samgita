# Current LocalShellCall history inputs

Two real pinned-native profiles qualify current generic Responses decoding,
raw/durable identity and supplied-history metadata for LocalShellCall. The source
is local synthetic Responses data. Neither profile establishes real upstream
legacy emission, shell execution or call/output pairing.

## Actual behavior

`apps/samgita_codex_driver/test/native_supplied_local_shell_history_test.exs`
uses `scripts/codex/supplied_local_shell_history_fixture.py`. Its first stream
supplies an incomplete local_shell_call, an exec action containing one inert
command name, and an ordinary assistant message. It supplies no native ID,
call ID, passthrough metadata, app-server frame, rollout row or sidecar.

Stock Codex creates the lsh_ ID, call_id:null, native optional action nulls and
source-turn metadata. Exactly one actual rawResponseItem/completed notification
must equal the entire native durable shell map, with the correct thread/turn.
The user map is independently fixed in full, including original ID, source
turn, bounded actual creation timestamp, classification and content. The shell
map's complete independent canonical oracle fixes every action field and null.

After source close/reap, a distinct cold native with an empty loaded list imports
the actual user/shell maps through unstable thread/resume.history. One profile
submits them unchanged. The second changes only shell passthrough metadata to
present client null; the independently expected durable map omits exactly that
key. It does not establish native-null emission. Both require a new idle
thread/path, whole original maps once/in order, zero automatic turn or inference,
and unchanged source/config/catalog/provider bytes.

One explicit followup consumes exactly the original shell provider copy with
only passthrough metadata removed. The native lsh_ ID and all nulls remain;
the original/followup user markers each occur once. The request states
history_initialization:supplied_history and yields the literal expected assistant
answer on the matching thread and turn. Requests stay **1 → 1 → 2** per profile.
No shell/tool lifecycle, compaction or synthesized FunctionCallOutput occurs.
Imported originals and all source bytes remain exact after followup and shutdown;
the owned workspace stays empty.

## Source evidence and boundaries

Pin: rust-v0.163.0, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Twenty-three complete production files match the official immutable archive;
seven physical schema nodes independently match their canonical hashes.

Only ClientRequest ResponseItem/oneOf/4 metadata owners **469/470/471** gain
implemented evidence: the property, actual source-turn object branch and
separately modified client-null branch. Other physical owners and equal-hash
aliases receive no promotion. ConfigurationUpdate426–429 remain unchanged and
missing. Their distinct genuine producer requires feature/provider/model support
and a separate harness-authored envelope annotation; raw-map equality cannot
establish its effective reasoning-override replay.

The bounded archive investigation reads8665 regular members including5259 Rust
files. No ordinary explicit LocalShellCall functional constructor or recorded
real backend emission was located. This does not prove unreachability:
`codex-api/src/sse/responses.rs:354–359` is the current generic production
ResponseItem decoder exercised here. The actual native raw/persisted frames
therefore establish current decoding and history handling of synthetic provider
data, not historical production traffic.

`core/src/tools/router.rs:257–308` falls back to non-tool handling for this raw
variant. `stream_events_utils.rs:93–105,360–399`,
`session/mod.rs:3481–3753`, the opt-in thread listener and
`app-server/src/bespoke_event_handling.rs:1167–1181` establish native preparation,
recording and real raw-event forwarding. `protocol/src/models.rs:1082–1097,1425`
defines metadata/call-ID serialization and the lsh prefix.
`rollout/src/policy.rs:86` and `context_manager/history.rs:1045` retain this
variant; current supplied-history reconstruction preserves original metadata.
`client.rs:1007–1009,1092–1095` strips only metadata in the separate selected
provider copy and preserves its prefixed ID.

`context_manager/normalize.rs:112–142` can add an aborted prompt-only output
when a call ID is present without its matching output. These profiles use the
schema-supported absent call ID and explicitly reject any synthesized output.
They make no paired-call or execution-completion claim. The inert command is
history data and is never executed.

## Final verification

The owning module passes **2/0**, seed501432,8.2seconds:
`/tmp/samgita-v316-local-shell-history-501432.log`. Before execution, full user
and shell oracles are split into bounded helpers; no semantic native failure,
timeout increase or weaker assertion is observed.

Commands/environment: `/tmp/samgita-v316-run.py`; artifacts:
`/tmp/samgita-v316-functional-checks/functional/`. The reviewed **47-file matrix
passes93/0 twice**, seeds501432/987654, in **171.029/163.204 seconds**. Scoped
format, warnings-as-errors compile, strict Credo on497 sources, outside
actual-binary consumer **1/0**,26 fixture ASTs and the **294-source** guard pass.
All prior292 guarded sources match baseline
`a603a3e923fa6751e5831076f791b95048145075` byte-for-byte; only the new test and
Responses fixture are added.

| Evidence | SHA256 |
| --- | --- |
| Results | `55c3a2eb6729581f4789766a3495d376381129b18808c14be8a3249c417af5ea` |
| Source guard | `8539a5aed0c22e88b2f8d824af37c6565e48bc2e943692e0299d3e88bdbe11eb` |
| Twenty-three pinned files and seven nodes | `5f9dc344d4ed7ef73fb858d45b248ccc445623d7479405c8a13cb2849d620226` |
| Resulting manifest | `b4028d6b052c56b74e7a02c5f67b6c27688939ad7dcac864871d0d42f557e29d` |

Existing256event/8MiB Session defaults,256event/1MiB local capture/import,
4MiB files/2048rows/262KiB lines and20s/60s event/case bounds remain. Owned
guardians and explicit native close/reap plus provider owner/completion/Port
checks precede root removal. Fixed yolo is setup, not policy qualification.

Final binding proves exactly three promotions with all schema identities,
planned tests, requirements and excluded owners unchanged. Inventory consistency
passes; strict completeness exits **1**. Contracts become **4,947 implemented /
1,608 missing / 66 blocked**; requirements stay **462 implemented / 12 missing /
11 blocked**, zero verified. Real backend/legacy execution, arbitrary metadata,
full restoration, external/OS/transports, A11 and full compatibility remain
unqualified. Prohibited security/auth/permission/approval tests and broad/hosted
workflows stay unrun. No release, publication or deployment occurs.
