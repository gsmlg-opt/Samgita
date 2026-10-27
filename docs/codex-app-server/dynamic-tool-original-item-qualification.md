# Original native dynamic-tool item qualification

V436 extends the existing ordinary failed-tool test on `main`
`34cb334bbd2243acfc20b309b5bb4c344e088bc4`. It retains one actual pinned
Codex turn, one registered synthetic dynamic tool, its explicit false result,
the exact two-request provider continuation and the overall completed turn.
The local provider supplies model data; stock Codex produces every app-server
item and request. No remote provider or paid operation runs.

The original test already prescribed complete started/completed item maps, but
its round trip re-encoded a projected event and its schema check used the stable
export. The new test-local transport delegates to Stdio unchanged and captures
selected original JSONL before Session decoding. It bounds that ledger to128
records,64KiB per frame and1MiB total, failing explicitly on overflow. Exactly
two records must retain start/completion order and equal the complete independent
expected envelopes, driver events and direct `Wire.decode` output. Both validate
the canonical experimental ServerNotification schema; the original stable-schema
and encode/decode regressions remain.

The prescribed item retains `fixture-call-1`, `fixture_lookup`, null namespace,
`{key:"synthetic"}`, null inProgress result fields and the exact failed text
content/success:false. Only actual measured duration and native timing values
are variable: duration is nonnegative and bounded by elapsed time; lifecycle and
emission times lie within host observations. Generation, exact server request,
sequence, final assistant answer and provider continuation are checked. Tool
failure remains distinct from overall turn completion. Original15s/20s waits,
60s module limit, event/byte/method limits, frozen inputs and confirmed owned
native/provider process/Port cleanup remain. Capture stays unchanged after
shutdown. Production driver, model fixture and existing process cleanup do not
change.

Only canonical physical owner2648 gains scoped implemented evidence:
`ServerNotification.json#/definitions/ThreadItem/oneOf/9`, SHA256
`664c8564f4b51fbf6aaaac8f35683a88c05133d02ea225d9051e168b4ce3317d`.
Seven whole upstream sources match the immutable archive. Native
`core/src/tools/handlers/dynamic.rs:185–276` creates the typed inProgress/Failed
items and measured duration. The app-server handles ItemStarted/ItemCompleted,
requests the ordinary tool result and maps the complete typed item; native
outgoing-message code adds emission time. In
`app-server/src/bespoke_event_handling.rs:977–998`, deprecated legacy dynamic
request/response lifecycle events are explicitly ignored for v2. That legacy
arm is not substituted for this real typed producer or counted as acceptance.

Pin: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Source/node binding `/tmp/samgita-v436-binding/source.json`, SHA256
`a2c740b6fd2ac540e7d14705b23bfb279450f4099179f9a6c415719ad2d49e1f`.

## Actual permitted checks

All eight commands in
`/tmp/samgita-v436-functional-checks/final/results.json` pass. The focused
`mix test test/native_failed_dynamic_tool_notification_test.exs --warnings-as-errors
--seed 501432` is **1/0**. The explicit31-file ordinary list is **50/0** at both
`501432` and `987654`. Python dependency syntax, explicit-file format,
warning-free driver compile, root strict Credo and `inventory.py --check` pass.
The runner uses the pinned binary, Elixir1.18.5/OTP27 and fixed YOLO native
launches. No assertion, deadline or production behavior was weakened.

Exact command/log ledger SHA256:
`1412162b507de401d6d272e8e5711a101433c0791b2d15bbaf7298eb4d031b95`.
The before/after guard covers414unchanged source hashes;413prior paths stay
exact and only the selected test changes. Guard
`/tmp/samgita-v436-functional-checks/final/source.json`, SHA256
`656472f207c39e08789fa22269c731d3461c591291b25bfb586a899d243aaefa`.
Test SHA256
`0b9c4ea7f776656a132b4dbfe479fef387471422f55c457e4539aa4835220830`.
Binder `/tmp/samgita-v436-bind.py`; evidence
`/tmp/samgita-v436-binding/evidence.json`, SHA256
`558a25655fbbb8958e56cfac86f85a877da797dd672b064ec32c83835af32911`.

Contracts: **5,227 implemented /1,328 missing /66 blocked**. Requirements stay
**462 implemented /12 missing /11 blocked**, zero verified in both ledgers.
Other statuses/content/namespaces, persisted-history owners, reconnect,
legacy paths, real providers and other OS/transports remain unqualified.
Security/permission tests and audits, broad suites and hosted workflows remain
unrun under the user's restriction. A11, external/platform/full-goal/release
gates remain incomplete. No publication or deployment occurs. Rollback reverts
this test and its one evidence binding without touching runtime/history.
Continue the ordinary native realtime service-error closure profile.
