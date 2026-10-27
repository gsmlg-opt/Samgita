# Original native shell-output envelopes

V434 runs on `main` base `793f95b81d412ab8c055fb8fd90e576bf860857f`.
Only canonical physical owners2935–2938 become scoped implemented:
ServerNotification.oneOf38 and its method, method literal and params owners.
The literal is `item/commandExecution/outputDelta`. The four original node
hashes remain in the manifest and bound source artifact; no physical alias
inherits this evidence.

The existing [ordinary shell test][test] retains its fixed-YOLO native launch,
two sequential public shellCommand calls and two prescribed ASCII output/effect
literals. No model call chooses a command or generates its output. The change
adds a separate ledger for matching original incoming JSONL frames before
Session decoding. Outgoing request capture/count semantics remain intact.
Matching raw capture fails at256records,4096bytes per frame or1MiB total;
existing256event/1MiB collectors,20s deadlines,5s shell timeout and60s case stay.

For each call, native turn/item-start and completion supply joined identities.
Complete expected delta params require that thread/turn/item and the next bytes
from the independently prescribed output literal. Native chunk sizes only
determine how many expected bytes to consume; native output never supplies its
own expected content. Full raw/decoded maps require the exact method, four-key
params and native emittedAtMs bounded by host request/collection times. Original
ingress matches selected driver events one-to-one in arrival order, with current
generation and unique increasing sequences; codec and canonical schema checks
retain the full maps. Arbitrary OS chunk boundaries remain supported without
assuming a single read or increasing a deadline.

All original leaf/join, item/turn ordering, exit0, aggregated output, distinct
turn/item identities, exact append-only effects and zero provider requests
remain. Warm paginated history and a separate unloaded cold native reader
preserve both completed execution records and effect bytes. The new raw ledger
must remain exact across warm reads/shutdown and cold reads/shutdown, preventing
a replay claim or new command. Existing no-gap/no-uncertainty/config stability
and checked owned native/Port cleanup remain. No support, fixture, config,
dependency or runtime module changes.

Official target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Eleven whole upstream files match the immutable archive. Public shell handling
at `thread_processor.rs:2544–2593` submits the standalone task; genuine child
output is read at `core/src/exec.rs:1194–1238`. Public mapping at
`event_mapping.rs:438–449` preserves thread/turn/item IDs and actual bytes;
`bespoke_event_handling.rs:1199–1206` emits the native notification.
`outgoing_message.rs:747–757,894–909` adds actual emission timestamps.
`tasks/user_shell.rs:292–322,440–466` persists completed execution output;
cold history is not a durable replay log of stream chunks. Source/node evidence:
`/tmp/samgita-v434-binding/source.json`, SHA256
`3f0b1826995fb95ab512141aa6bafbb22ea168b180f68113a9cfe9941c2065a0`.

Focused actual-native **1/0**; the30-module reviewed ordinary selection passes
**48/0** at501432/987654,84.640/88.281 command seconds. Eleven Python syntax
checks, scoped format, driver compile with warnings as errors, root strict
Credo and inventory consistency pass. All414guarded sources stay stable:
413prior paths are unchanged and this existing test changes. Exact commands/
logs/source guard:
`/tmp/samgita-v434-functional-checks/final/{results,source}.json`, SHA256
`ea243d31d0fe864e6406cb444a871ada5850d0f359781d9a2d176fb89148e86d` /
`ff0808f8c5a40864bd214c320a642d14614ad6a01026a9d9fcbc23b1f70a1934`.
Test SHA256:
`67bf82972469041437a478d44851f06f70ebd3799f622531e56ebc3a363d3106`.
Binder `/tmp/samgita-v434-bind.py`; binding
`/tmp/samgita-v434-binding/evidence.json`, SHA256
`926647a8cd49d11fad0c796580a3a808e80ab36a751f3c386b853121b77ed8d6`.

The adjacent legacy fileChange/outputDelta branch remains unqualified.
[Pinned upstream item.rs:1518–1520][legacy] explicitly states:
“Deprecated legacy notification for `apply_patch` textual output. … The server
no longer emits this notification.” The native patch-event handler suppresses
the old path in favor of canonical FileChange items. No mock producer is used
to close that missing acceptance.

Contracts become **5,218 implemented /1,337 missing /66 blocked**; requirements
remain **462 implemented /12 missing /11 blocked**, zero verified. This covers
selected Linux stdio explicit userShell output, not LLM commands, binary/lossy
text, other transports/OS, stream replay or the whole family. Prohibited
security/credential/authentication/authorization/permission/approval tests and
audits, broad suites and hosted workflows remain unrun. A11, unavailable legacy
and external/platform/full-goal/release gates stay incomplete. Push suppresses
CI; no publication/deployment. Rollback removes the added ingress assertions
and four bindings while retaining the original shell/history/cleanup tests.
Continue the separately bounded ordinary realtime transcript profile.

[test]: ../../apps/samgita_codex_driver/test/native_shell_delta_identity_test.exs
[legacy]: https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/item.rs#L1518
