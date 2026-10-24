# Initialization notification test synchronization

The selected job's rerun at `e82f32f` in
[40034198690](https://github.com/gsmlg-opt/Samgita/actions/runs/40034198690/job/120692737039)
failed `NativeNotificationTest` at seed `728846`. The original helper started
an asynchronous Task and immediately expected initialize output within ExUnit's
default 100 ms. It had no observable proof that Session processed the request.
The exact hosted scheduling/schema-initialization delay is not established.

A deterministic regression suspends Session and uses public Erlang send tracing
to resume it only after both initialize and a subsequent status barrier are
queued. With the old helper in a scratch copy, the test fails at exactly 100 ms
with an empty mailbox. The repaired helper passes without sleeps, enlarged
timeouts, removed assertions or automatic retries.

The helper now uses public OTP `:gen_server.send_request/2`, enqueuing initialize
directly from the test process. `Session.status/1` from that same sender provides
a causal processing barrier. It must observe `initializing` and one pending
request before the test requires the exact transport output with
`assert_received`. Response settlement uses public
`:gen_server.receive_response/2` with the same existing 5,000 ms Task-await
bound. The adjacent pending-mutation setup uses the same barrier before testing
a failed notification send. Uncertain operation, gap, disconnected state,
reconnect, no replay and lossless unknown-notification assertions are preserved.
Production Session, transport code and configured deadlines are unchanged.

The regression verifies both initial and completed Session states and always
disables tracing, resumes an owned suspended Session and stops its owned helper.
It does not claim new native Codex behavior; this is deterministic driver-test
ordering evidence.

## Validation

From the standalone driver directory in verified Devenv, `MIX_ENV=test`:

```sh
mix test test/native_notification_test.exs --seed 728846
mix test test/native_notification_test.exs --seed 987654
mix format --check-formatted test/native_notification_test.exs
```

Both focused runs passed **10 tests / zero failures**, 1.0 seconds each.
At root, scoped `mix credo
apps/samgita_codex_driver/test/native_notification_test.exs --strict` passed.
Controlled red/green logs are
`/tmp/samgita-native-notification-barrier-red.log` and
`/tmp/samgita-native-notification-barrier-green.log`.
The red scratch file is `/tmp/samgita-native-notification-red-20261024.exs`.

The full driver repeat with actual pinned `CODEX_BINARY` and original hosted
seed `728846` passed **418 tests / zero failures**, 305.0 seconds, max_cases 32.
Command: `mix test --seed 728846`, from the standalone driver directory in
verified Devenv with `MIX_ENV=test`. The log is
`/tmp/samgita-driver-notification-repair-full-728846.log`. This run includes the
new deterministic regression; subsequent family additions require their own
final-source aggregate repeat. Hosted
[40039092156](https://github.com/gsmlg-opt/Samgita/actions/runs/40039092156)
at `403607ca405702475c86e01840fe090bd23f4f53` passed the full **418/0** driver,
native wire, outside consumer and selected platform journey; all 15 explicitly
selected native profiles also passed. The overall workflow failed its separate
required completeness/evidence gate. Full log:
`/tmp/samgita-403607c-hosted-conformance-20261024.log`.
This closes that ordering/acquisition checkpoint, not final-source qualification
after later additions. Neither repair nor selected conformance closes full
manifest, external-profile or A11 requirements.

## Queued notification after reconnect

The frozen local v17 default-driver repeat at `636b2ad`, seed `987654`,
failed the adjacent queued-notification test: the reconnect reply arrived but
the exact `stale_session, uncertain: false` notification reply was absent at
the unchanged 100 ms assertion. The log does not distinguish a pending callback,
lost reply or wrong reply. The isolated original module passed both fixed seeds
(**10/0** each), and ten additional cold/warm observations returned the expected
reply within that bound. Those observations do not establish the historical
scheduling or I/O cause and are not called a repair.

The test sent reconnect and notification calls directly from the same process,
but asserted replies before checking that the notification callback completed.
It now places the existing same-sender `Session.status/1` barrier first, requires
generation +1, phase `new` and zero pending requests, then requires both exact
replies immediately. The no-send assertion remains. Production Session and all
request/assertion deadlines are unchanged.

A new deterministic regression uses supported OTP `:sys.install/2` to hold only
the selected notification before its callback. It proves the reply is absent
for the original 100 ms, then releases the callback only when public send tracing
observes the same caller's queued status request. The processed-state barrier
must return the exact new generation/state before the single stale reply and
absence of transport writes are checked. Cleanup disables tracing, releases
the hold, resumes/removes the debug hook and shuts down the helper; the hold
also monitors its owner. This establishes the test's missing causal barrier,
not a proven native protocol loss or a claimed historical scheduler cause.

In verified Devenv, `MIX_ENV=test`, the repaired module passes **11/0** at seeds
`987654` and `501432`. The initial diagnosis and ten observations remain under
`/tmp/samgita-notification-diagnosis-v1-20261025/`; the repaired module logs are
`/tmp/samgita-native-repair-continuation-v1-20261025/notification-*.log`.
That runner's later new executor profile initially failed before native startup
because its draft omitted the required isolated `CODEX_HOME`. This separate
fixture error is retained and corrected without relaxing the driver guard.
The follow-up full 15-file owning block passes **91/0 twice**, seeds `501432`
and `987654`, including real default, goal and executor profiles. Compilation,
formatting, root strict Credo (431 files) and the executable before/after guard
pass; logs and exact commands are under
`/tmp/samgita-native-repair-continuation-v2-20261025/`. Complete final-source
default-driver/aggregate/hosted validation remains separately required.
