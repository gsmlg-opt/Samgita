# Native process notification envelopes

V402 starts from `2b7030000c793135a58c4ce93369b097a102dba8` on `main`.
The new [ordinary native test](../../apps/samgita_codex_driver/test/native_process_notification_envelope_test.exs)
qualifies only stable `ServerNotification.json` owners2927 (`/oneOf/36`,
`process/outputDelta`) and2931 (`/oneOf/37`, `process/exited`). Previously mapped
fields, aliases, runtime and shared helpers remain unchanged.

Target: official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Seven whole producer/protocol/initialization/transport files byte-match their
archive members; both complete stable nodes match canonical provenance.

## Real EOF and output effects

Two cold, independently rooted owned native profiles use distinct literal
process handles and explicit `outputBytesCap:null`/`0`. Neither profile uses a
model, provider, thread, external service or fabricated app-server frame. Fixed
YOLO launch defaults apply without testing permission behavior.

An inline Python child records its real PID, then reads bounded binary stdin.
Two literal chunks are accepted with `closeStdin:false`. A public diagnostics
RPC completes while the child remains alive, its journal contains only the
started record, and both raw capture and driver queue contain no notifications.
This is an observable no-effect barrier, not an elapsed-sleep assertion.

An explicit `closeStdin:true` delivers EOF. The child independently checks all
input bytes, records EOF, writes prescribed binary stdout/stderr containing
Unicode, NUL and invalid UTF-8, journals its actual successful writes, and exits7.
The Elixir oracle independently prescribes all input/output/journal contents.

Original incoming JSON, retained before Session decoding after JSONL delimiter
removal, must equal complete ordered driver event maps. Every output/exit map
must have exactly the independently expected method, params and top-level keys,
known handle and native `emittedAtMs` within the host-observed EOF/exit interval.
Uncapped canonical base64 deltas consume exact prefixes of independent per-pipe
byte oracles; arbitrary OS chunking and stdout/stderr interleaving are allowed.
Both oracles must be exhausted and all cap flags false.

Cap0 requires exactly two empty deltas, one per stream, with true cap flags.
The child's independent journal still proves nonempty successful writes. Both
profiles require exactly one final exit notification with exit7, empty buffered
stdout/stderr and matching cap flags. Terminal is last, with ordered unique
Session sequences/current generation and no other event kinds. A post-exit
diagnostics barrier confirms the same native process remains usable; final
drain is empty and pending/uncertain/interaction state is empty.

Pinned `process_exec_processor.rs:535–553,677–700` orders accepted input and EOF;
`610–675` applies per-pipe limits and emits base64 notices; `585–608` joins both
output workers before exit notification. `v2/process.rs:151–202` declares the
stream/full terminal payloads, and `outgoing_message.rs:895–908` supplies the
timestamp. No cross-stream order, signal, PTY or general execution guarantee
is inferred.

## Initial failure, repair and finite resources

The first new-fixture matrix fails **25/1** at501432 before `process/spawn`:
stock initialization emits `remoteControl/status/changed` even with remote
control disabled. The fixture's empty-startup assertion was therefore invalid
under its original subscription. The failure is retained in
`/tmp/samgita-v402-functional-checks/final/`.

The fixture now uses the supported initialize
`optOutNotificationMethods:["remoteControl/status/changed"]`. Pinned
`initialize_processor.rs:90–93,137`, `lib.rs:1215–1251` and
`transport.rs:104–127` show opt-out registration before the initial notice and
exact-method suppression in the native writer. No driver-side filter is added.
Process output/exit, empty-startup/no-effect assertions, cleanup, limits and
deadlines remain unchanged. Remote-control/authentication behavior is not
tested or qualified by this choice.

Each profile requires eight original correlated RPC pairs plus initialized.
Raw capture is96 frames/256KiB combined,8KiB outbound/64KiB inbound per frame;
events are64/256KiB. Child input is1024 bytes, journal4096 bytes/three rows;
config4096 bytes. Requests, child lifetime/EOF and terminal collection retain
5s bounds; case timeout30s. Configuration bytes and empty workspace stay
unchanged. Normal and failure cleanup verify owner completion, closed Port and
disappearance of actual native/child PIDs before removing owned roots. The
established process cleanup implementation remains unchanged.

## Final-source evidence and remaining gates

Final **25/0** at seeds **501432/987654** completes in40.658/41.157 command
seconds, without exclusions. Python syntax, scoped format, warning-free driver
compile, root strict Credo and offline inventory consistency pass. All398 guarded
sources stay stable; all397 prior paths retain their bytes. Test SHA256:
`1193017a1cdb61feb234f017580dd52b4b9bb41b442971fb89880a8cbef98ee1`.
Runner/results: `/tmp/samgita-v402-run.py` and
`/tmp/samgita-v402-functional-checks/final2/`. Results/guard SHA256:
`84cbddd942da97b56fb7f99418810b274105f791b5024f64a7d426dd57afad24` /
`831b304afb674c5fada963fc494eee0726060f1f66448ee46a0799e5c5dd6e46`.
Source binding `/tmp/samgita-v402-source-final/evidence.json` SHA256:
`af3f79f9fbfbefbfed4b8ef5f74a48208b505cead263841acd0868805bd6c00a`.
Manifest binder `/tmp/samgita-v402-bind.py` and
`/tmp/samgita-v402-binding/evidence.json` SHA256:
`426d608c4f7345d8f4efbb3196d0ed198eea7fc524d8cca2b66b84562c5ac15f`.

Only2927/2931 become scoped implemented: **5,117 implemented /1,438 missing
/66 blocked** contracts; requirements remain **462 implemented /12 missing
/11 blocked**, with **zero verified** in both. Strict completeness still fails.
Security/credentials/authentication/authorization/permission/approval tests and
audits, mixed broad suites and hosted workflows remain unrun. A11, unavailable
producers, external/OS/platform/full-goal/release gates stay incomplete. No tag,
publication, deployment, production migration or sibling edit occurs. Rollback
removes the new test and two mappings; retain runtime and historical records.
Continue real external-configuration import progress/completion envelopes.
