# Owned stdio startup error redaction

The internal `Transport.Stdio.Owner` startup boundary now converts a raised port
startup exception into `{:stop, Error.new(:process_start_failed)}`. Previously
`GenServer.start` returned an error containing the complete exception stack,
including explicit port arguments and environment. Confirmed shutdown, descendant
reaping, close idempotence and unconfirmed-shutdown safeguards are unchanged.

The regression invokes this real Owner/OS boundary with a nonexistent executable
under its own temporary directory and two synthetic canaries. A separately caught
`Port.open` call positively requires `:enoent`, the exact options in its stack,
and both canaries. The test traces the actual Owner spawn and exit, independently
monitors death, crosses a trace-delivery barrier and requires exactly one child
and no remaining port. It scans the returned result, raw structured Logger
events and CaptureLog output, with positive capture markers. The final result
must be exactly a safe `process_start_failed` error with no wire/details and no
uncertainty. No mock exception, filesystem race or resource exhaustion is used.

This is an internal boundary test. Public `Stdio.open` validates its executable
before reaching this boundary; a normal-input public failure reproduction is
not established. Native Codex is not run by this regression.

## Retained failed reproductions

The first broken-interpreter setup did not make `Port.open` raise: it returned a
port, and the positive control failed before Owner ran. It proves no exposure.
The corrected absent-executable control reaches the real error. Before the fix,
the returned error exposes both canaries; raw and formatted Logger scans pass.
Thus the observed repair concerns the returned error, **not an observed Logger
leak**. Earlier source-only predictions of such a leak are not runtime evidence.

Artifacts remain in `/tmp/samgita-stdio-init-confidentiality-red-v1-20261025/`
and `red-v2` at the same path prefix. Results/source SHA256 respectively:

- v1: `097db98f3b63707da6509efa53c89f55b1112b9a063a613bfc1c1487504673c3` /
  `ec028ac19a158e27e5d6fe857ec7ab6ea6818e9df43c00c49f8f2c9f737428c9`.
- v2: `23042e16ab14eaf0b8358834c2abaa5dc1fe5c534bbdd5635aa1f71b7243bed4` /
  `02e9dde9ba9a9ea3b2d496c01e542bc32024bcc231ac04e64e3157f010b7be54`.

## Executed qualification

From the independent driver directory in verified Devenv, `MIX_ENV=test`:

```sh
mix compile --warnings-as-errors
mix test test/native_default_gates_profile.exs test/transport_stdio_confidentiality_test.exs test/session_confidentiality_test.exs test/session_test.exs test/transport_stdio_test.exs --warnings-as-errors --seed 501432
mix test test/native_default_gates_profile.exs test/transport_stdio_confidentiality_test.exs test/session_confidentiality_test.exs test/session_test.exs test/transport_stdio_test.exs --warnings-as-errors --seed 987654
```

The complete owning block passes **54/0 twice**, 32.1/32.2 seconds. Changed-file
formatting, warning-free compilation and root strict Credo pass. Before/after
executable-source snapshots match. Exact commands/logs are retained under
`/tmp/samgita-native-history-stdio-v2-20261025/`; results SHA256
`3b6627ff784a70877295af7ec2bf081612ec54baa3e5fdf368ade711216db0e5`,
source-snapshot SHA256
`e57074a14793dd6a009c2918d931d4751c6f3541eb692f74ffae01a97c8f498f`.
The first combined block's supplied-history oracle failure is retained separately
in [default semantics](default-semantics-qualification.md#successful-supplied-history-import).

This scoped repair does not qualify arbitrary transport errors, stderr,
privileged OTP Debug, exporters or framework ingress. No confidentiality
lifecycle entry becomes verified. [A11](a11-ingress-boundary.md), complete
final-source checks and full Codex compatibility remain incomplete. No live
credentials, paid task, publication or deployment is involved.
