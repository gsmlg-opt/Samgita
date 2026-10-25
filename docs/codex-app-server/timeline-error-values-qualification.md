# Native timeline terminal errors

This continuation qualifies exactly physical contracts **6436–6438** in
v2/ThreadTimelineListResponse.json: the terminal `error` field, its TurnError
object alternative and its explicit null alternative. The target remains
immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

## Behavior and independent oracles

The added tagged case in native_timeline_position_values_test.exs owns one
paginated durable thread. timeline_error_fixture.py supplies only Responses
SSE: a first response.failed with server_is_overloaded and deliberately
different provider text, then an assistant message for the one caller-created
recovery turn. It emits no app-server response, writes no native history and
supplies no timeline data. Fixed yolo options configure only the owned native
launch; this case asserts no security or permission behavior.

Before recovery, actual native notifications, saved full history and timeline
must independently report failure. Their exact API TurnError is:

```json
{"message":"Selected model is at capacity. Please try a different model.","codexErrorInfo":"serverOverloaded","additionalDetails":null,"misalignment":null}
```

The genuine raw task_complete record must instead contain exactly the
two-key snake_case error with codex_error_info:server_overloaded. The successful
raw terminal record must omit error. Its native API timeline entry must contain
an explicitly present error:null; Map.fetch! makes omission fail. Expected
values come from prescribed constants and the canonical raw terminal ordinal,
never from the timeline response being checked. Native thread/turn/item IDs
bind each actual provider input, notification, raw record and stored turn.

The failed history is checked before recovery, and one provider request must
remain one while the failed timeline is read. Only an explicit second turn can
produce recovery. Both full saved turns and the full raw history are checked
before snapshotting complete rollout/provider journal bytes. Confirmed owned
process exit precedes a fresh process reading history/timeline without loading
the thread. Full timeline equality, saved-turn equality, empty loaded lists and
unchanged rollout, model catalog, configuration and provider journal demonstrate
the scoped process-restart behavior without another inference. This is not a
power-loss/fsync or production-cutover proof.

## Immutable production path

The pinned [overload conversion](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/codex-api/src/sse/responses_error.rs#L87)
produces ServerOverloaded. With no server retry advice,
[sampling](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/responses_retry.rs#L91)
returns the terminal error. The native task copies its captured error into
TurnComplete. Raw ErrorEvent, its custom codex_error_info serialization and
TurnComplete's absent-error rule produce the separately asserted raw format.

The [history projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/thread_history_projection.rs#L34)
maps that native record to failed/completed status and optional API TurnError.
The local store serializes error_json in the terminal transaction. Actual
[timeline SQL](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/thread-store/src/local/thread_history/realtime.rs#L125)
reads that stored JSON, and the app-server returns the page unchanged.
Loaded paginated includeTurns reads call persist before loading full turns;
projection errors can only warn, so the test requires actual expected raw
records and full saved turns rather than treating a read ACK as proof.

Eighteen complete production/serialization files match source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
All three exact node hashes and their export match pinned provenance.
Independent read-only review finds no actionable defect or broader promotion.

## Qualification and limits

Base commit: b712db7. Initial focused v283 passes compilation/format but fails
**2/1**: the new raw user-text equality omitted native text_elements:[].
Pinned user_input.rs:25 defines the serialized default field. Adding that exact
empty array corrects the oracle without relaxing an assertion or deadline;
v284 passes **2/0** and full strict Credo. The existing ordinary position case
retains its paging, cursor, persistence, buffer and process-cleanup checks.

Final twenty-eight-file commands use the same explicit file list as the
[context-window checkpoint](thread-event-lifecycle-qualification.md#context-window-catalog-qualification).
Both seeds 501432/987654 pass **51 tests / 0 failures**, with warnings as errors,
in **84.758/84.368** command seconds. Scoped format, warning-free compilation,
strict Credo on 479 sources, outside actual-binary consumer **1/0**, five fixture
AST checks and the **255-source** unchanged-byte guard pass. All eight commands
complete. Event collection retains 256 events/1 MiB and 20s; requests use 5s;
capture retains 32 frames/4096 bytes; raw reads retain 2048 lines/1 MiB.

Commands, logs and source bindings:
`/tmp/samgita-v285-functional-checks/functional/`. Results/source SHA256:
`f0998b92d23d18dd174caf68ee243b0f3fb5cbb7aaac4d9b865aba5c936cb07d` /
`44d692453a6744e7b0e599ea542a1d24cb70e260542b6e015e744347c6fcabd3`.
Adjacent source-evidence.json SHA256:
`b0e11e195b83134ba752216a3dbbf33507cd2ac9ad03f0d9c3785ce421aaf791`.
The manifest binding records only the three original/current owners and final
test/fixture hashes; no requirement record or schema identity changes.

Contracts become **4,736 implemented / 1,826 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero
verified in either ledger. Inventory --check passes; strict completeness exits
**1**. No timestamp alias, other error kind, enclosing response/method, realtime
or selective history mode, other OS/transport or external backend gains evidence.
Runtime/shared helpers, dependencies and platform configuration stay unchanged.
Security/permission tests, audits and broad/hosted workflows are unrun under the
user restriction. Full compatibility, A11, source-unreachable alternatives,
external/platform acceptance and release remain incomplete. No publication or
deployment occurs.
