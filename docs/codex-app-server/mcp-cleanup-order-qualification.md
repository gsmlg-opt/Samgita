# MCP fixture shutdown ownership and ordering

This repairs the native MCP qualification fixture, not the production process
guardian. Target remains stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The real executable runs in an owned private namespace with synthetic local MCP
services. No inference, live account, sibling repository or production task is
used.

## Failure and source-established cause

[Hosted run 40082826118](https://github.com/gsmlg-opt/Samgita/actions/runs/40082826118)
at `3dcf64b` reports M7 failing setup's `on_exit` assertion: the journal has no
`fixture_closed` marker. Its body reports no failed stream/cancellation assertion;
the preceding owned-PID disappearance checks complete. The discarded scratch
journal cannot establish which graceful shutdown stage was interrupted.

`Stdio.open` monitors its opening test process. ExUnit runs `on_exit` in another
process after that caller exits. Caller death therefore starts the production
guardian's TERM/KILL sequence before the cleanup callback can require graceful
fixture evidence. `priv/stdio_owner.py:50-56` allows at most one second before
group KILL, potentially less when the leader exits. The fixture's existing
native/HTTP shutdown must finish before it writes `fixture_closed`; the guardian
never promised it that graceful interval. Extending production grace or adding
sleep would leave the ordering requirement unresolved.

The immutable native source also distinguishes graceful draining from forced
shutdown: `app-server/src/lib.rs:218-229,255-308`. The driver cannot infer that
reaped processes completed every fixture cleanup step. This diagnosis identifies
a deterministic ownership defect without inventing the unretained hosted trace.

## Repair and independent regression

All M1–M8 bodies already finish at `assert_profile`. After its existing
no-inference/interaction checks, that live-caller boundary now sends one fixed
fixture-local `close` control. The fixture runs its full existing native and HTTP
shutdown, persists `fixture_closed`, and only then persists the correlated
`control_done` acknowledgement. Completed graceful close is idempotent. Its
controller remains available until the unchanged caller-death guardian reaps it.

M9 requires exactly one close marker before the ACK, all native PIDs gone, the
native UDS absent/refusing connections, and controller/namespace/guardian still
alive with cleanup completion zero. A subsequent barrier proves the controller
remains usable; repeated close must preserve the one marker. The existing
`on_exit`, including final PID and marker assertions, is unchanged and separately
checks the final hard ownership boundary. Production cleanup code, one-second
grace, observation deadlines and all prior assertions remain unchanged.

The new M9 was first run against the old fixture and failed at its immediate
one-marker assertion while the caller was still alive. With the repair, that
same selected test passed, followed by the complete M1–M9 suite, **9/0**, seed
`501432`. Both selected runs have eight intentionally unselected sibling cases;
they are red/green evidence, not a complete-suite claim.

Commands run from `apps/samgita_codex_driver` with `MIX_ENV=test`, the pinned
`CODEX_BINARY` and `devenv shell --no-tui --`:

```sh
mix format test/native_mcp_control_lifecycle_test.exs
mix test test/native_mcp_control_lifecycle_test.exs:425 --seed 501432
mix test test/native_mcp_control_lifecycle_test.exs --warnings-as-errors --seed 501432
```

Red, selected green and complete first-seed logs are
`/tmp/samgita-mcp-close-order-{red,green,501432}-20261024.log`.
The complete MCP suite plus `process_lifecycle_test.exs`,
`stdio_session_fixture_test.exs` and `transport_stdio_test.exs` passed **29/0**,
seed `987654`; log:
`/tmp/samgita-mcp-close-order-cleanup-987654-20261024.log`. Driver formatting
and Python AST parsing passed. Both production ownership files have their
unchanged pre-repair SHA256 values. Final combined-source/hosted qualification
remains required. No manifest contract
is promoted by fixture shutdown evidence. Complete compatibility, A11,
unreachable legacy paths and external/OS success remain incomplete.
