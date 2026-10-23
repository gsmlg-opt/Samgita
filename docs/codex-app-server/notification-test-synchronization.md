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
final-source aggregate repeat. Hosted validation remains pending on pushed
source. Neither ordering repair nor selected conformance closes full manifest,
external-profile or A11 requirements.
