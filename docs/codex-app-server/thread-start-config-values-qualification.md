# Native per-thread configuration override

This unit targets only physical contract **6320**, ThreadStartParams.config,
on immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The actual app-server receives every request. The assistant-only local model
fixture supplies fixed text, never native responses or settings. No Samgita
platform, Repo, database service or synthetic database seed is needed.

## Independent override and controls

An immutable owned root config prescribes high effort and concise summary.
The model catalog supports low/high and summary, with no model effort default.
Three distinct legacy threads with ephemeral:false start before settings or inference:

| Exact start configuration | Expected native effort |
| --- | --- |
| Object containing model_reasoning_effort=low | low |
| Explicit config:null | high |
| Config omitted | high |

Each response and genuine thread/started notification must match those
independently prescribed values. Summary-only concise→auto updates on the first
two threads produce actual applied-settings notices retaining low/high effort.
Exactly two real provider requests must then contain low/high plus auto, fixed
instructions, the corresponding unique input and actual thread/turn IDs. Neither
thread's input may contain the other's marker. The third thread receives no turn
or inference. Five unchanged captured start/turn envelopes have distinct IDs
matched to genuine response IDs; the null and omitted forms remain distinct.

The pinned
[configuration manager](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/config_manager.rs#L375)
maps missing/null to an empty override map, appends actual JSON→TOML request
entries and builds the thread configuration. The selected ordinary string value
reaches SessionFlags with ordered overlay precedence. Fifteen complete production
files match the immutable archive; both versioned exports match provenance. The
exact property-node canonical digest **739cb0c0defcb7f0ed857b685e2d027b2b62284b06f53af782bfb441863f28b3**
matches inventory. The source handoff initially confused a whole manifest-row
digest with that property digest; it is corrected before owner binding, without
changing schemas or their hashes. Source and implementation evidence are in
`/tmp/samgita-v245-next-functional-candidate/` and
`/tmp/samgita-v246-thread-config-implementation/`.

## Characterized failures and corrected history expectations

The first focused case fails **1/1** before inference at C's full legacy-history
read. A diagnostic rerun remains **1/1** and reveals actual -32600: includeTurns
is unavailable before the first user message. The pinned
[history error mapping](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L6271)
explicitly defines this condition. The corrected case requires that exact native
code/message/correlated ID before and after the other threads execute. It also
reads C's genuine metadata; its empty turns array is explicitly a metadata stub,
not a persisted-history claim. Exact provider/call assertions separately prove
no C execution. The original empty/no-execution oracle is retained with accurate
upstream semantics, without forcing persistence or submitting a dummy turn.

That corrected diagnostic reaches inference but fails **1/1** at another wrong
test expectation: live item UUID equals legacy reconstructed ID. Pinned
[legacy history construction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors.rs#L730)
creates a fresh builder; ordinary user/assistant records allocate item-1/item-2.
The test now requires those exact independently prescribed IDs, retaining actual
turn IDs/status, content, streamed-item sanity and every provider assertion.
This diagnostic command also contains an Erlang PATH typo and falls back to
OTP 27.3.4.13; it is a failed diagnostic, not final qualification evidence.

Logs: `/tmp/samgita-v246-thread-config-first.log`,
`/tmp/samgita-v248-thread-config-traced.log` and
`/tmp/samgita-v248-thread-config-corrected.log`. The correct-environment final
focused run passes **1/0**, seed 501432, in **1.5** test seconds; log
`/tmp/samgita-v248-thread-config-final.log`. Independent final source review
in `/tmp/samgita-v247-thread-config-review/` finds no further actionable issue.
The review also byte-matches five relevant complete producer files to the archive.
No timeout, skipped assertion, runtime workaround or production-code change is
used. The original failures remain evidence.

## Qualification boundary

The final block is the twenty-four reviewed functional files in
[memory reader qualification](memory-status-reader-qualification.md#checks-and-limits)
plus `test/native_thread_start_config_values_test.exs`. All **40 tests pass at
both seeds 501432 and 987654**, with warnings treated as errors, in
**74.183/74.238** command seconds. Scoped format, warning-free compile, strict
Credo on **477 files**, outside-umbrella actual-binary consumer **1/0**, three
Python AST checks and the **251-file** unchanged-source guard pass. All eight
commands complete in the verified environment. Exact artifacts are in
`/tmp/samgita-v249-functional-checks/functional/`; results/source SHA256:
`14a01ee2bc1dae5ac812ef78bb24fc8e8ea3fd2c71e8453d25ab2aea75d825a0` /
`bc27c04dc87d160e0507ed878a468fba6e316c87991053d7a6703c650de806e4`.
The adjacent `manifest-binding-config.json` binds the original/current row to
test SHA256 `3249f1dc5187dfc6bee291965e26b6e73fdd23db8e500ec4b36cf467823fe08e`.

Only field **6320** receives scoped implemented evidence. Inventory `--check`
passes; all requirement records and schema identities/hashes are preserved.
Contracts become **4,707 implemented / 1,855 missing / 59 blocked**;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both. Configuration/catalog/provider journal bytes remain unchanged, with
an empty workspace and checked owned shutdown.
Capture is bounded to five frames/4096 bytes, notices to 256 events/one MiB with
explicit gap failure, requests/init to 5s and ordinary turns to 20s. Yolo launch
is fixed owned setup only, without policy assertions. Earlier process cleanup
and shared helpers are unchanged.

Only the selected effort override/null/omission behavior is in scope. Arbitrary
configuration keys, complete precedence/error behavior, cold restoration,
other history modes/OS/transports/backends and real service success remain
unqualified. No alias, other request/response field or whole configuration
subsystem inherits evidence. Prohibited security/permission checks and broad/
hosted matrices remain unrun. Full compatibility, A11, source-unreachable legacy
emitters, external acceptance and release remain incomplete. No publication,
production migration or deployment occurs.
