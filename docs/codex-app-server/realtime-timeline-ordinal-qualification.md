# Native realtime timeline ordinals and original responses

V439 strengthens only the existing ordinary transcript case on `main`
`76e0b1bfc738a7a0cba42d8b9831b9949f163a13`. Its complete timeline oracle
previously sampled positions from the response under test. It now obtains them
from genuine canonical native persistence and checks the complete original
correlated response. The original start/stop and service-error cases remain.

After the existing native thread/read persistence barrier, the test reads only
its owned synthetic rollout, bounded to 1 MiB and 2,048 complete JSONL records.
Exactly three realtime records must have complete independently prescribed
snake_case payloads: caller session start, the known assistant streamed text,
and requested ended closure. Their native UUIDs must match the already checked
live notices. Full record keys, parseable timestamps within the separate native
start/transcript/stop brackets, and strictly increasing nonnegative canonical
ordinals are required. Neither content nor IDs come from the timeline result.

The expected public page combines these actual persisted ordinals with the
separately prescribed complete public items. Both native timeline responses
must equal that whole page. Each original request/response has its exact params,
unique ID and causal capture order; original JSON and direct Wire decoding must
equal the complete expected envelope, and the original result validates the
canonical schema. Existing rejection of the differing flat completion text
remains. Rollout bytes and hash stay unchanged after the repeated read and
confirmed native/peer cleanup. No new request, process, backend scenario or
model inference is added; original bounds and all behavior assertions remain.

Only two physical canonical owners gain scoped implemented evidence:

| Owner | Canonical pointer in `v2/ThreadTimelineListResponse.json` | Node SHA256 |
| --- | --- | --- |
| 6422 | `/definitions/ThreadTimelineEntry/oneOf/1` | `58f608a76edffd1f090e97bc6f147f8396dfa86e0d6288f9b61b5596ff7427dc` |
| 6423 | `/definitions/ThreadTimelineEntry/oneOf/1/properties/item` | `9d5e58c462d865f9c4d44ab76dbb3e25e649d623f08db865d80072103be4216f` |

The real native reducer and `session/realtime_history.rs` append typed facts
before completed-notice delivery. Native live_writer flushes persistence before
SQLite materialization; materialization and timeline reads preserve the canonical
ordinal. Public mapping converts the known item shapes without changing their
identity or selected text/outcome. Twelve whole producer/storage/readback files
match the immutable archive. This is actual pinned native persistence and
readback, with a synthetic backend supplying realtime data only.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All source/node hashes are in
`/tmp/samgita-v439-v440-binding/source.json`, SHA256
`cd4fbaaf9ea1e18b520e739205b5953fd14729252b7081fd3a28b7dc6433c6fa`.

## Checks, correction and limits

The initial combined owning block passed **4/0**. Strict Credo then rejected
the new rollout helper's complexity of 10 against maximum 9. Moving its exact
record-key/type/timestamp assertions into `assert_rollout_record/2` fixed the
finding. No assertion, timestamp bracket, deadline or production code changed.
Initial commands and failed log remain in
`/tmp/samgita-v440-functional-checks/final/results.json`, SHA256
`dbe5950800f034753d7975f2c5e1ce5babf8945ef32642f10dc7a47436b297f8`.
That initial run stopped at the failure and is not a completed matrix.

All nine final commands pass in
`/tmp/samgita-v440-functional-checks/final-after-split/results.json`: owning
realtime/MCP **4/0**, explicit ordinary block **51/0** at both `501432` and
`987654`, syntax, scoped format, warning-free driver compile, root strict Credo,
inventory consistency and the reviewed outside-umbrella consumer **1/0**
(generated seed 189700). The consumer uses actual pinned Codex without Repo,
Phoenix or umbrella runtime. These results include the concurrent MCP envelope
enhancement; the two changes are delivered as separate logical commits.

Final command/log ledger SHA256:
`2f06079b8f15f6a89fe5e8f8dc524be2737222394ac732b009445fd2c34042fe`.
All 414 source hashes remain stable; 412 prior paths are exact and only two
tests change. Guard SHA256:
`b93c23ca6ed50efd892de4f1aaefeeae5d65e886dec94628ff96efa898abd7f3`.
Final realtime test SHA256:
`d7e96511cd740613a65ccb8c4685e77aaab4c2b29079332b1c12319787151cf4`.
Binder `/tmp/samgita-v439-v440-bind.py`; evidence JSON SHA256:
`35b538363e60b0ff476ca144e39d6891be22b20dc9859938ac65dc7767a1d825`.

This binding yields **5,238 implemented / 1,317 missing / 66 blocked** contracts.
Requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified
in both ledgers. Only selected started/assistant-transcript/ended timeline items
gain evidence; aliases, other item variants, failed closure, cursors, cold reads,
remote providers/media/OS/transports do not inherit it. Fixed YOLO setup remains;
no security/permission tests or audits, broad suites or hosted workflows run.
A11, legacy reachability, external/platform/full-goal and release gates remain
incomplete. No publication or deployment. Rollback restores these added test
assertions and two evidence bindings without runtime or historical-data changes.
Continue the separately owned complete MCP startup-envelope binding.
