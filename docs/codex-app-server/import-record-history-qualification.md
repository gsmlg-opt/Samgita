# Native reported-import history persistence

V399 starts from `515911f28cc03266ae823e6cecb9eeadf122e303` on `main`.
The new [ordinary record-history test](../../apps/samgita_codex_driver/test/native_import_record_history_test.exs)
qualifies exactly three stable physical fields:3978/3979,
`ExternalAgentConfigImportHistoryRecordParams.json#/properties/itemTypeResults`
and `/properties/providerId`;3980,
`ExternalAgentConfigImportHistoryRecordResponse.json#/properties/importId`.
Historical mixed-profile evidence remains recorded; that module is not run.
Runtime, shared fixtures and all previous tests retain their bytes.

Official target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Six complete producer/readback/storage files match the immutable archive; all
three physical stable nodes independently match their canonical hashes.

## What is persisted

The case starts an owned native process with empty public histories and loaded/
durable thread lists. Report A supplies provider A, two independently described
successes and one failure across two groups. Report B supplies provider B, a
different success and two ordered failures, including distinct null fields.
Each write must return exactly one native UUID-v4 importId; IDs must differ.

Separate literal complete expected maps prescribe the public readback, preserving
exact providers, titles, paths, failure strings, nulls and vector order. Expected
outcomes are not flattened from the request or copied from a native response.
Only native-generated identity/time are variable: IDs have prescribed syntax and
distinctness, and each UTC millisecond timestamp must fall between host readings
immediately before and after its write. Readback order is timestamp descending,
UUID ascending, including a same-millisecond tie without sleeps.

The second read must retain complete A alongside B. Checked native shutdown and
a distinct cold native process must return the exact complete two-record history
with no additional writes. No direct database inspection, SQL seed or fake
app-server reply supplies expected persistence.

`external_agent_migration/processor.rs:408–445` generates UUID-v4, maps supplied
reports and awaits durable recording before returning. Its helper at670–714
flattens success/failure vectors. `state/src/runtime/external_agent_config_imports.rs:49–81`
records native UTC time and outcomes;114–163 reads them in the documented order.
`external_agent_migration/protocol.rs:219–266` supplies the separate public
readback. These are stock native producers, not Samgita database operations.

**Recording reported successes does not execute an import or prove an import
succeeded.** Group itemType is discarded by native flattening; owner160 and all
nested/readback aliases receive no inferred persistence or state promotion.
The wire inventory permits two record writes, four history reads, initialization,
diagnostics and empty thread-list reads only. Zero model requests, no import/
thread-create/turn/command call, absent reported metadata paths, empty workspace
and no rollouts remain asserted before/after writes, restart and shutdown.

## Final-source verification and limits

Original outgoing/incoming JSON is captured before Session decoding; each explicit
request ID joins exact sent bytes/map to received bytes/native result. Delimiters
have already been removed by Stdio; OS chunks/newlines are not claimed. Capture
is bounded to128 records/64KiB each/2MiB total; Session8pending/64events/2MiB,
snapshots2MiB, RPC5s, case60s and owner DOWN1s remain explicit. Normal/fallback
cleanup requires owner completion, closed Ports and absent native PID, including
the owned model fixture. Original config/provider/support bytes and byte-exact
empty provider journal remain unchanged. Mutations are not retried.

The initial focused case passes **1/0**. Final V398 ordinary selection plus this
case passes **22/0** at both **501432** and **987654**, no exclusions. Scoped
format, warning-free driver compile, root strict Credo and offline inventory
consistency pass. All395 guarded sources stay stable; all394 prior sources
retain their bytes. Environment remains Elixir1.18.5/OTP27.3.4.17, test mode,
two schedulers, pinned binary and fixed YOLO ordinary launch setup. One unused
candidate alias was removed during source review before compilation; no failing
test or assertion was removed.

Runner/logs: `/tmp/samgita-v399-run.py`,
`/tmp/samgita-v399-functional-checks/final/`; focused logs/source:
`/tmp/samgita-v399-native/import-history/`. Final test SHA256:
`0b95ca616ff0b207fef9341e0373e294ed3fd0e99ab319515f38fc010321ddbc`.
Results/guard SHA256: `3d0cbe7870459332e74f93807871f50c842802d316d0aa08edb78e73cd9435cc`
and `0a34a69a554e4f379db4b61814797e8ffd932ac1d5288333f03738d4705a8944`.
Source binding: `/tmp/samgita-v399-source/evidence.json`, SHA256
`cbd8c0bb2d7ab4703e3ba71c788cdc0ff585dec0e3adb71494bf971d26f36ed8`.
Manifest binding: `/tmp/samgita-v399-bind.py` and
`/tmp/samgita-v399-binding/evidence.json`, SHA256
`7e386d3ff021f8fea978bd6a4e0fd339b078bef643a0cf0632545384702138a3`.

Only3978–3980 become scoped implemented: **5,107 implemented /1,448 missing
/66 blocked** contracts; requirements remain **462 implemented /12 missing
/11 blocked**, with **zero verified** in both. Strict completeness remains red.
Other report variants, actual import execution, transports/OS/backend and full
acceptance remain separate. Security/credentials/authentication/authorization/
permission/approval tests and audits, broad suites and hosted workflows remain
unrun. A11, unavailable native producers and external/platform/full-goal/release
gates remain incomplete. No tag, publication, deployment, production migration or
sibling change occurs. Rollback removes the new test and three evidence mappings;
preserve runtime and historical records. Continue reachable ordinary native gaps.
