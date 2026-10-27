# Original native command-output ingress

V401 starts from `63e0bf9745534231656384f84ee097583daccf49` on `main`.
The [retained owning test](../../apps/samgita_codex_driver/test/native_command_output_stream_values_test.exs)
adds bounded original incoming JSON capture for stable `ServerNotification.json`
owners2923–2926: `/oneOf/35`, its method, method literal and params. This extends
the historical [command-stream evidence](native-runtime-values-qualification.md#native-command-streams);
old runs remain historical for the changed test. Runtime and shared helpers
retain their bytes. No other physical export inherits this evidence.

The target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256 `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Five complete producer/protocol/conversion files byte-match archive members;
all four stable canonical nodes independently match the manifest hashes.

## Preserved functional oracle

One explicitly owned Python child writes independently prescribed stdout/stderr
bytes containing Unicode, NUL and invalid UTF-8, then exits7. Real Codex emits
`command/exec/outputDelta`. The transport wrapper now retains original incoming
JSON after JSONL delimiter removal and before Session decoding. Ordered decoded
original frames must equal complete driver event wire maps. This does not
claim preservation of original OS chunks/newline delimiters or outbound bytes:
outgoing capture still retains decoded request maps only.

Existing assertions remain: exact top-level and params keys, known process ID,
canonical base64, both stream labels, nonempty exact reconstructed pipe bytes,
false cap flags, unique ordered sequence/current generation, and native
`emittedAtMs` within the host-observed command interval. Relative ordering of
separate stdout/stderr pipes is deliberately unconstrained. The correlated reply
is exactly exit7 with empty final stdout/stderr; final drain is empty. Captured
requests remain initialize, initialized, diagnostics, one command and loaded-list;
there is no thread, model, provider or extra execution. Native and child PIDs
must be reaped, with no pending or uncertain operation.

Pinned `command_exec.rs:480–500` creates separate pipe workers,
`607–621` emits base64 stream notices, and `553–570` joins workers before the
correlated response. `outgoing_message.rs:804–827,894–908` provides the send
barrier and native timestamp. No artificial sleep substitutes for completion.

Original incoming capture is bounded to16 frames,8192 bytes per frame and8192
bytes total; exceeding it fails explicitly. All existing request/event limits,
timeouts and cleanup controls are unchanged. Callback extraction keeps nesting
within the strict static limit without changing behavior.

## Final-source checks and limits

Focused actual-native execution passes **1/0**. The final reviewed ordinary
matrix passes **24/0** at seeds **501432/987654** in38.953/39.256 command seconds,
without exclusions. Python peer syntax, scoped format, warning-free driver
compile, root strict Credo and offline inventory consistency pass. All397 guarded
sources remain stable;396 prior paths retain their bytes, with only the intended
owning-test change. Final test SHA256:
`9fb958c2789d8fae9595976de004ec9b104160023e4c474eb8296637ff421c7c`.

Runner/results: `/tmp/samgita-v401-run.py` and
`/tmp/samgita-v401-functional-checks/final/`; focused artifacts:
`/tmp/samgita-v401-native/command-ingress/`. Results/guard SHA256:
`65283564616b79cbac4576a9edaab48933c6c5b4a77f4b362088af5768a79932` /
`0eda86c2ffa0ba3042914bb36aa0a3803d51e3b0d7d056b6095d12967dcdb80c`.
Source binding `/tmp/samgita-v401-source/evidence.json` SHA256:
`665d0ce5290209828ecb7598ec7d2c4e7a274941f69149fac026098817aead81`.
Manifest binder `/tmp/samgita-v401-bind.py` and
`/tmp/samgita-v401-binding/evidence.json` SHA256:
`dd987d5fa33cb522d3c062fddee6bfcb03bda716494f252771e5a7f8997c42e2`.

Only2923–2926 become scoped implemented: **5,115 implemented /1,440 missing
/66 blocked** contracts; requirements remain **462 implemented /12 missing
/11 blocked**, with **zero verified** in both. Strict completeness remains red.
Security/credentials/authentication/authorization/permission/approval tests and
audits, mixed broad suites and hosted workflows remain unrun. A11, unavailable
native producers, external/OS/platform/full-goal/release gates stay incomplete.
No tag, publication, deployment, production migration or sibling change occurs.
Rollback restores this owning-test change and removes its four evidence mappings;
retain runtime, historical records and the established process-cleanup repair.
Continue real process/outputDelta and process/exited full-envelope evidence.
