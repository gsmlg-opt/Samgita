# Native reported-import input evidence index

V429 starts from `main` `49500351878415e6654894bfdec1d82d65771bb1`.
This is an evidence-index change: no executable or test changes and no new test
run. The unchanged [ordinary record-history case][test] already receives two
complete original requests and compares independent complete persisted histories
before and after an owned cold-process restart. Its source-equivalent V424 run
passes **44 ordinary cases at both501432 and987654**. All409 guarded source
paths and all eight check logs still match their recorded hashes.

Only14 exact `ClientRequest.json` physical owners gain scoped implemented
evidence. They were omitted from the [original record-history unit][original];
equal node hashes and the original three field bindings do not qualify them.
Every node is independently checked against the canonical export:

| Definition | Physical owner indices | Fields and demonstrated values |
| --- | --- | --- |
| ExternalAgentConfigImportHistoryRecordSuccessParams |154–158|cwd path/null; itemType SESSIONS/CONFIG/COMMANDS; exact nonnull source/target; title text/null|
| ExternalAgentConfigImportHistoryRecordTypeResultParams |159,161|full independently prescribed empty/nonempty failures and nonempty successes; native vector flattening/order|
| ExternalAgentConfigImportItemTypeFailure |162–168|cwd/source/subErrorType text/null; exact nonnull errorType, failureStage and message; itemType CONFIG/COMMANDS|

The case supplies three reported successes and three reported failures with
distinct provider IDs, values and ordering. Original outgoing bytes/maps retain
the complete supplied inputs and correlate to the real native responses.
Separate literal expected maps prescribe every selected readback value; expected
outcomes are not produced by flattening the requests. Only native UUID-v4 IDs and
UTC millisecond times vary, with syntax/distinctness and host time brackets.
History order is timestamp descending, UUID ascending, including ties. Checked
shutdown and a distinct cold native process must return the exact same history.

This is **record_only** evidence. The API stores caller-reported facts; it does
not perform or certify the reported import. No actual import, model, thread,
turn or command runs. Reported source/target paths remain absent, workspace and
rollouts stay empty, and provider/config/catalog/support bytes remain frozen.
Source/target success nulls, failure errorType nulls, missing/default fields,
empty successes, other item types, actual import-engine errors and notification
payloads are not qualified. Owner160, the group's own itemType, remains missing:
native storage discards it while flattening. No wrapper, alias, enum-literal or
other physical owner inherits this evidence.

The immutable target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Six complete upstream files match archive members. Public config structs at
`app-server-protocol/src/protocol/v2/config.rs:958–1020` feed the real dispatch
at `app-server/src/message_processor.rs:1158–1167`. Conversion at
`external_agent_migration/processor.rs:408–445,670–714` preserves selected
fields and flattens vectors before durable recording; the state runtime and
public history converter preserve values and ordering on readback.

Unchanged limits:128 captured frames/64KiB each/2MiB aggregate,
Session8pending/64events/2MiB,5s RPC,60s case. Fixed YOLO setup and checked
owner completion, closed Ports and vanished owned native PID remain intact.
Test SHA256:
`0b95ca616ff0b207fef9341e0373e294ed3fd0e99ab319515f38fc010321ddbc`.
The V424 syntax/format/compile/strict-Credo/inventory checks also remain
source-equivalent; this index does not claim new runtime verification.

Binder `/tmp/samgita-v429-bind.py` verifies the14 nodes, six complete sources,
409 source hashes and existing native logs. Evidence
`/tmp/samgita-v429-binding/evidence.json` SHA256:
`873c62a795471279361faf2865a30dff6b8613feba203219f5e91c44889e61df`.
Reused `/tmp/samgita-v424-functional-checks/final/{results,source}.json`
SHA256 values:
`a41102495af0c1a5724434480131b562d2aaf9471a822d068f53e72fbe052afe` /
`f6286e5ef71f72002072d155e6e8248bc8d0fbedb29c4092c91db1197c3671bf`.

Contracts become **5,192 implemented /1,363 missing /66 blocked**;
requirements stay **462 implemented /12 missing /11 blocked**, zero verified.
Security/credential/authentication/authorization/permission/approval checks and
audits, broad suites and hosted workflows remain unrun; existing gates remain.
A11, unreachable producers, external/platform success, full-goal and release
acceptance stay incomplete. Pushes suppress CI; no publication or deployment.
Rollback removes this index and its14 bindings, preserving runtime and history.
Continue with the independently reachable ordinary root Interrupt Hook profile.

[test]: ../../apps/samgita_codex_driver/test/native_import_record_history_test.exs
[original]: import-record-history-qualification.md
