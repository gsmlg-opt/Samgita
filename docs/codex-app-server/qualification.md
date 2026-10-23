# Codex compatibility qualification

Status: **incomplete**. No full compatibility, publication, deployment or production
readiness claim is made. The complete accepted contract is in [goal](goal.md).

Baseline inspection on 2026-10-23 confirmed clean tracked `main` at
`4fe354f2ce916aa32517c361a171b8878bf6ca84` before this work; only the user-provided
goal and plan were untracked. Existing source metadata pins official
`rust-v0.163.0` / `83086188ae0614bd882818ff1aa23f3194962012`. It covers selected
reference schemas, six convenience request mappings and three notifications.
Those prior tests do not establish real-binary conformance.

The tested executable source is committed in native checkpoint
`e0e4d6b9f5c652d76fa849a533fd08efdf1086fe` and driver checkpoint
`9566fda6f0462cd2a9fd508dfb8b345e93e57f2f`. The final passing checks below ran
against those same source files before committing; the following documentation
commit changes no executable code. Neither checkpoint completes the full goal.

## Immutable reference

The checkpoint verifies official `rust-v0.163.0`, Linux
`x86_64-unknown-linux-musl`, using disposable HOME, CODEX_HOME and workspaces.
Python model fixtures listen only on loopback; no account or paid provider is used.

| Artifact | Immutable identity |
| --- | --- |
| Source commit | `83086188ae0614bd882818ff1aa23f3194962012` |
| Tag object | `129b8ec7ee6f4511557a4856279f529025c25af4` |
| Binary SHA-256 | `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` |
| Release archive SHA-256 | `beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4` |
| Source archive SHA-256 | `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567` |

Complete stable/experimental schemas, source gate annotations and individual
artifact hashes are in
`apps/samgita_protocol_codex/priv/upstream/0.163.0/provenance.json`. The binary and
source cache live in ignored `tmp/codex/0.163.0/`, outside package contents.

## Local checkpoint evidence, 2026-10-23

These checks were executed during this implementation, after the final executable
changes. Package commands ran in `devenv shell --no-tui -- bash -c '…'`, serially,
from the named package directory. This is scoped foundation evidence, not the
final full-goal release matrix.

| Check | Exact command or scope | Result |
| --- | --- | --- |
| Pin | `python3 scripts/codex/fetch_pin.py` | Passed; exact source/archive/binary hashes and version |
| Inventory | `python3 scripts/codex/inventory.py --check` | Passed; 318 stable + 452 experimental artifacts, 477 entries + 6,549 contracts |
| Inventory regressions | `python3 -m unittest discover -s scripts/codex -p 'test_*.py' -v` | 9 passed |
| Native package | In `apps/samgita_protocol_codex`: `mix test` | 29 passed; includes 452 generated message/result examples and 6,549 field/variant examples |
| Native static checks | `mix compile --warnings-as-errors`; `mix format --check-formatted` | Passed |
| Driver package | In `apps/samgita_codex_driver`: `CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" mix test` | 48 passed |
| Driver static checks | `mix compile --warnings-as-errors`; `mix format --check-formatted` | Passed |
| Outside consumer | `python3 scripts/codex/verify_consumer.py` inside Devenv | Passed fresh dependency resolution, warnings-as-errors compilation, 1 real-binary test and formatting; no Repo/Phoenix/platform/config inheritance |
| Raw reference baseline | `python3 scripts/codex/real_binary_baseline.py --output tmp/codex/0.163.0/native-baseline.json` | Stable and experimental profiles passed initialize, pre-init/duplicate-init rejection, config/thread reads, configured thread/text turn and full item completion; one local model request each |
| Source-semantic gates | `python3 scripts/codex/probe_gates.py` | 13/13 actual-binary probes passed, without valid turn execution |
| Completeness gate | `python3 scripts/codex/inventory.py --check --require-verified` | **Failed as required**: unverified entries remain; this must prevent a full compatibility claim |
| Whitespace | `git diff --check`, followed by staged checks at commit | Passed |

The driver suite combines scripted faults with actual binary tests. Real
transports cover stdio, capability-token-authenticated WebSocket and borrowed
WebSocket-over-UDS. Scripted transport tests cover WSS trust/hostname rejection,
fragmented/coalesced JSONL, control/fragmented frames, bounds, EOF, HTTP 429,
environment isolation and owned process cleanup. TLS rejection tests deliberately
produce certificate alerts.

Actual Session journeys cover stable/experimental configured text turns, a valid
image URL reaching the local model, full item events, structured native errors,
command decline/cancel/explicit acceptance, a dynamic tool's structured result,
plan-mode user input and explicit WebSocket reconnect/read/resume without a second
model execution. Only the exact synthetic `printf samgita_fixture` command in a
disposable cwd, using a private test shell, may be approved. These journeys cover
selected behaviors, not all 172 client methods or 11 server interactions.

Scripted Session regressions separately verify typed bidirectional IDs,
out-of-order responses, initialization, native trace/envelope preservation,
redacted errors, deadlines, caller loss, stale/resolved/expired handles,
bounded queues/outcomes, local cancellation and uncertain mutations. Local reply
encoding failure leaves an interaction usable; an attempted transport send can
remain uncertain. A sent or resolved reply never implies task acceptance.

## Corrections established by these checks

Initial real-driver runs failed on output validation and fixture assumptions.
Those failures were reproduced and corrected before the passing runs above:

- Rust input gates depend on value/Option semantics, not field presence alone.
  Thirteen actual-binary probes distinguish false/null/empty/nested cases.
- Stable upstream responses and notification payloads contain fields removed by
  stable schema generation. Full pinned output schemas preserve/type-check them;
  client-input field gates do not apply to those emitted payloads.
- Both notification exports list 85 methods. Rust source annotations gate 24 at
  runtime, so discovery exposes 61 stable/85 experimental notification methods.
  Server-request export annotations impose no runtime gate: all 11 interactions,
  including `currentTime/read`, remain discoverable in either profile. Inventory
  metadata distinguishes annotation/export status from runtime capability needs.
- The command fixture selects a shell type, while upstream discovers its actual
  executable. A private shell first on the owned child's PATH makes the exact
  approval assertion independent of host shell symlinks.
- The initial one-pixel PNG had an invalid IDAT checksum. The valid replacement
  passes the same actual-provider-input assertion; the assertion was not weakened.
- A clean outside consumer exposed a missing formatter configuration. It now has
  its own configuration and passes without inheriting the repository's settings.

## Unfinished acceptance

| Layer | Remaining gate |
| --- | --- |
| Manifest evidence | 0 verified, 477 missing message/lifecycle entries; 0 verified, 6,549 missing field contracts. Generic implementation and generated fixtures do not advance end-to-end evidence states. |
| Method/interaction matrix | Per-entry enabled/disabled/error/differential journeys for remaining families and server interactions; current selected journeys are insufficient. |
| Platform | Ordinary Agent native bindings, durable thread/turn/operation/interaction records, authorized programmatic APIs, current fences and Samgita end-to-end tests are not implemented in this checkpoint. |
| External profiles | Real account/backend authentication, signed-JWT success, external tools/services and other OS/backend success profiles have not run. Controlled authorized environments and synthetic/test credentials are needed after independent implementation; no live credentials were provisioned. |
| Aggregate/hosted | Root tests, assets, strict Credo, Dialyzer, audit, restart/assembly and hosted full-compatibility checks have not run for this checkpoint. Prior redesign CI evidence does not qualify these additions. |

No manifest entry was mass-marked verified from schema coverage or JSON transport.
Missing, mock-only and externally blocked requirements keep the full goal active
and incomplete. Continue using the next steps in
[the implementation ledger](implementation-plan.md).

## Security and release limits

The existing raw LiveView credential telemetry issue A11 remains explicit and
prevents platform readiness. Synthetic credentials and isolated processes only
are authorized. Upstream mutation timeouts/disconnects may be ambiguous; never
retry automatically or pretend a local command ID confers upstream idempotency.
No release tag, publication, deployment, production migration or live credential
change has occurred in this work.
