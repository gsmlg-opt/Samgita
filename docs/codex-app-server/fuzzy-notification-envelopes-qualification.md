# Real fuzzy-search notification envelopes

V404 starts from `f521e99ce89e4a65d40ed3bdaa539d9e046b447b` on `main`.
The new [ordinary native test](../../apps/samgita_codex_driver/test/native_fuzzy_notification_envelope_test.exs)
qualifies exact stable `ServerNotification.json` owners3071–3074/3079–3082:
complete branches69/70 and their method, literal and params nodes for
`fuzzyFileSearch/sessionUpdated` and `fuzzyFileSearch/sessionCompleted`.
Existing fields, aliases, runtime and shared helpers stay unchanged.

Target: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Ten whole upstream files match archive members; all eight physical canonical
nodes independently match their manifest hashes.

## Independent roots and complete native frames

Two cold owned native sessions use distinct literal Unicode session IDs and
isolated search trees. The first reproduces the official five-file fixture.
Its independently prescribed `abe` results contain complete file maps:

| Path | Score | Character indices |
| --- | --- | --- |
| `abexy` |84|0,1,2|
| `sub/abce` |72|4,5,7|
| `abcde` |71|0,1,4|

Root, relative path, match_type, filename, score and indices must all match.
The second tree omits `abexy` before scanning and must return exactly the other
two rows. Scores are fixed by the pinned official test, not learned from current
driver output. `file-search/src/lib.rs:304–315` shows the one-shot oracle uses
the same create-session/update-query/wait implementation as the session API.
The unique first nonempty query and independent root omission establish real
input-dependent effects without any model/provider/thread or fake server.

Each native profile observes a complete startup `sessionCompleted` frame as an
idle indication, a full ranked `sessionUpdated`, and a full empty-query snapshot
after submitting clear. Complete independent method/params/keysets and native
`emittedAtMs` within host-observed intervals are required. Selected raw incoming
JSON, retained before Session decode after delimiter removal, must contain those
complete frames in the same consumed order as delivered events. Current
generation and sorted unique Session sequences remain required.

Partial intermediate results and repeated idle notifications are legitimate;
they retain correct method/session/envelope metadata within finite bounds.
Completion carries no query generation and is not a result-success fence.
Sequence and timestamp bounds also cannot prove the empty snapshot belongs to
the clear operation: an already-spawned startup empty update could send late.
This is exact empty-wire evidence, not causal clear/cancellation proof. Stop
and a later diagnostics RPC do not promise that already-spawned notices cannot
arrive. No exactly-once, fixed notice count or cross-query total order is claimed.

Pinned `request_processors/search.rs:81–132` creates/updates/removes sessions;
`fuzzy_file_search.rs:118–158,173–256` runs the real scanner and projects actual
matching snapshots. `file-search/src/snapshot.rs:13–59` supplies match indices
and scores; `lib.rs:558–587` emits snapshots/idle completion. Official
`app-server/tests/suite/fuzzy_file_search.rs:220–299` defines the independent
golden. Native method mapping and timestamp producer remain in `common.rs`
and `outgoing_message.rs:895–908`. Supported initialization opt-out excludes
only the unrelated disabled remote-control notice, with no auth/control test.

## Bounds, checks and remaining gates

Each profile requires seven original correlated RPC pairs plus initialized.
Original capture128 frames/1MiB combined,4KiB outbound/64KiB inbound per frame,
and cumulative events128/1MiB fail explicitly on overflow. RPC/predicate waits
are5s, case30s; files256 bytes/config4096 bytes remain byte-exact and workspace
empty. Explicit stop, owner completion, closed Port and actual native PID
disappearance are checked normally and on failure before owned root removal.
Fixed YOLO launch is setup, with no permission behavior variation or assertion.

Initial format/compile passes, then strict Credo rejects the unused `Enum.reduce`
return in the new original-order helper. Removing only its trailing `:ok` lets
the function return that result naturally. All assertions, bounds and deadlines
retain their bytes. No functional test ran in that failed attempt; logs/source
remain in `/tmp/samgita-v404-functional-checks/final/`.

Final **33/0** at seeds **501432/987654**,54.836/55.289 command seconds, passes
without exclusions. Both peer Python syntax checks, scoped format, warning-free
driver compile, root strict Credo and offline inventory consistency pass.
All399 guarded sources stay stable; all398 prior paths retain their bytes.
Final test SHA256:
`7fcbee46a982832126b9d4a6dae546a925017ef9c754b181c4ebe986cebbf64f`.
Runner/results: `/tmp/samgita-v404-run.py` and
`/tmp/samgita-v404-functional-checks/final2/`. Results/guard SHA256:
`d95bccf50041ed94cf40b8188487ae0277c19ec02287c163fc8991bdf93d50ed` /
`cac073aef45e7ec102879498453ad4836c1646b51c876900c01d4c398258270e`.
Source binding `/tmp/samgita-v404-source/evidence.json` SHA256:
`ef6101cfbbae269109a94187c07ee80eebe5d2a8b6186d5b8ac1ce58b7617800`.
Manifest binder `/tmp/samgita-v404-bind.py` and
`/tmp/samgita-v404-binding/evidence.json` SHA256:
`3a9c85e2c04f3cd1b4777d6a5e0ddae5a2f46645b7ce1dfab994a246ad05f97b`.

Only3071–3074/3079–3082 become scoped implemented: **5,133 implemented /1,422
missing /66 blocked** contracts; requirements remain **462 implemented /12
missing /11 blocked**, with **zero verified** in both. Strict completeness stays
red. Security/permission-related tests/audits, mixed broad suites and hosted
workflows remain unrun. A11, unavailable native producers, external/OS/platform/
full-goal/release gates remain incomplete. No publication, deployment, production
migration or sibling edit occurs. Rollback removes the new test and eight
mappings; retain runtime/historical records. Continue ordinary goal/queue full
envelopes with direct fixed-YOLO threads, excluding old mixed helper profiles.
