# Session status and controlled crash confidentiality

Three scripted owned-Session cases qualify the existing callback against actual
OTP 27.3.4.17 status and Logger behavior. They do not run a fake Codex server as
native acceptance and do not establish full credential isolation or close A11.
Production Session, protocol Error and transport behavior are unchanged.

`apps/samgita_codex_driver/test/session_confidentiality_test.exs` retains four
independent synthetic canaries in pending request parameters, native error
message/data and explicitly supplied transport environment. Positive controls
scan the external-term encoding of raw state, independently of struct Inspect.
Authorized consumers still receive the exact error, late-response event and
pending-request result, including nested values. Error Inspect and exception
messages remain redacted.

With debugging disabled, the entire real `:sys.get_status` term contains no
canary and its outer Debug list must be empty. Explicit `:sys.log` is a different
boundary: the test positively requires all four canaries in raw outer Debug,
while requiring the process dictionary and callback-formatted component to be
redacted. Formatted State is exactly redacted and formatted Logged events is
empty. Disabling that explicit debug history restores the full-status assertion.
`:sys.get_state` and privileged Debug access are trusted diagnostic facilities,
not sanitized exporter inputs.

A controlled owned transport crash occurs with sensitive last-message, pending
state and debug history present. Both CaptureLog output and raw structured
Logger events must omit every canary. The genuine crash marker remains visible;
pending work settles once as `session_stopped`, uncertain, with its exact request
ID. The Session and owned resource must both terminate, with no reopen or resend.
This deliberately uses a safe controlled exception reason. It does not qualify
arbitrary transport exception reasons, native stderr, other processes, exporters
or application/framework ingress. The generic confidentiality gate stays missing.

## Why the callback has this boundary

Retained OTP source `stdlib-6.2.2.5/src/sys.erl:1006-1017` returns
`[PDict, SysState, Parent, Debug, FmtMisc]`, leaving raw Debug outside formatted
status. `gen_server.erl:2942-2962` invokes the application's callback only for
the inner state/log and uses Erlang string (character-list) labels. Its crash
report path at `:2629-2653` uses callback-formatted message/state/log before
emitting the structured Logger report. Session `format_status/1` supplies those
redactions. No OTP/private debugger state is patched.

The initial full-status assertion with explicit debugging enabled failed because
it scanned raw Debug too. The replacement preserves that exposure as a positive
regression and adds a separate full scan under the actual default. The v2 test
then failed only because expected labels were binaries instead of OTP character
lists. Exactly those two label types were corrected; no canary scan, crash,
settlement, payload, cleanup assertion or deadline was removed. Both original
failure logs and their hashes are retained in
[default semantics](default-semantics-qualification.md#fork-path-normalization-and-optional-resume-history).

## Executed checks and limits

In verified Devenv, with `MIX_ENV=test`, from the standalone driver directory:

```sh
mix compile --warnings-as-errors
mix test test/native_default_gates_profile.exs test/session_confidentiality_test.exs test/session_test.exs test/transport_stdio_test.exs --warnings-as-errors --seed 501432
mix test test/native_default_gates_profile.exs test/session_confidentiality_test.exs test/session_test.exs test/transport_stdio_test.exs --warnings-as-errors --seed 987654
```

Both complete owning blocks pass **52 tests / zero failures** (29.3 seconds
each). Formatting and root `mix credo --strict` pass, scanning 428 files.
Before/after executable-source snapshots match. Exact commands, final logs and
hashes are in `/tmp/samgita-native-default-confidentiality-v3-20261025/` and the
linked record. Final complete local and hosted matrices remain separate gates.

A11 concerns raw Bandit/Phoenix/LiveView instrumentation before application
handling, not privileged OTP debugging. Its
[source-boundary prerequisite](a11-ingress-boundary.md) remains unchanged. No
manifest owner is promoted, no arbitrary-logger/credential guarantee follows,
and no live secrets, native paid task, publication or deployment is involved.
