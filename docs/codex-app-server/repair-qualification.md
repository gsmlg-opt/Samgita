# Repair evidence and continuing compatibility work

This record executes `samgita-codex-repair-followup.txt` on the existing `main`,
starting from `3c54d748871313bd69858ff05d0fd2c606019e6a`. It supplements the
[compatibility ledger](implementation-plan.md) and [qualification](qualification.md).
Local checks, hosted checks, full compatibility and confidentiality acceptance
remain separate gates. No production data, credentials or services are changed.

## Owned-process baseline

Pinned run [39958930872](https://github.com/gsmlg-opt/Samgita/actions/runs/39958930872)
passed its selected actual-binary/platform job after the production guardian
shutdown repair. That historical failure stays fixed. The subsequent hosted
teardown failure at `3c54d74` exposed a test fixture that could skip the existing
guardian barrier after linked Session death; commit `5964db9` repairs that test
ordering without changing production shutdown. Its three deterministic regressions
and final **169-test** driver run, seed `513498`, are recorded in qualification.

## Retained Plug.Crypto update

The maintainer's advisory is
[GHSA-ffw9-w85g-f2vh](https://github.com/elixir-plug/plug/security/advisories/GHSA-ffw9-w85g-f2vh),
verified with `gh api repos/elixir-plug/plug/security-advisories/GHSA-ffw9-w85g-f2vh`.
It affects `plug_crypto >= 1.0.0, < 2.2.1`: incorrect argument types can expose
secret arguments in function-clause stacktraces/logging. There is no established
incident or deployed exposure in this review. This advisory is separate from A11.

Only `plug_crypto` changes, **2.2.0 → 2.2.1**, in the root and standalone WebSocket
lockfiles. The WebSocket package also declares `~> 2.2.1`, enforcing the patched
floor for independent consumers. The other retained package lockfiles belong to
the native Codex schema and driver packages; neither contains Plug.Crypto. The
neutral core has no dependency lockfile and the consumer examples commit none.
Fresh consumer resolution cannot substitute for updating the two retained locks.

`plug_crypto_regression_test.exs` uses synthetic data to exercise all three
signing digests, authenticated encryption/AAD/tamper/wrong-key rejection,
Phoenix token scoping/expiry/encryption, signed browser-session round trips and
modified-cookie rejection. Wrong-typed signing, verification, encryption,
decryption and comparison calls must produce generic errors with no canary in
either formatted or actual stacktrace terms. Existing credential, API-key,
rate-limit and operator UI tests retain their authorization/validation assertions.

Under Devenv Elixir 1.18.5 / OTP 27.3.4.17, on the already populated isolated
`samgita_redesign_recovery_repair_test` database:

```sh
mix test apps/samgita_web/test/samgita_web/plug_crypto_regression_test.exs \
  apps/samgita_web/test/samgita_web/raw_http_telemetry_test.exs \
  apps/samgita_web/test/samgita_web/telemetry_confidentiality_test.exs \
  apps/samgita_web/test/samgita_web/live/agents_live_test.exs \
  apps/samgita_web/test/samgita_web/controllers/domain_api_test.exs \
  apps/samgita_web/test/samgita_web/plugs/api_auth_test.exs \
  apps/samgita_web/test/samgita_web/plugs/rate_limit_test.exs --seed 455834
```

Result: **49 tests, zero failures**, log
`/tmp/samgita-repair-crypto-telemetry.log`. The four raw-HTTP cases and the
pre-existing LiveView canary intentionally establish A11 exposure; their passing
result is not confidentiality acceptance.

The serialized repair verification block passed root compilation with warnings
as errors, formatting, strict Credo (272 source files), `mix hex.audit` from the
root and each of the three independently locked packages, and all outside
consumers. The neutral core had **32 passing cases**, its direct example **1**,
the isolated direct WebSocket example **1**, and the Codex consumer **1** against
the actual pinned binary. The corrected implicit cleanup scope passed all three
shutdown regressions again. Log: `/tmp/samgita-repair-audits-consumers.log`.
The first static run identified two new readability issues (explicit function
`try` and alias order); both were corrected without exclusions and the entire
block reran successfully. These checks precede the continuing notification API
work; final aggregate and hosted outcomes are recorded separately.

## Neutral WebSocket overflow and replay

Hosted run [39958837990](https://github.com/gsmlg-opt/Samgita/actions/runs/39958837990)
failed waiting for live cursor 3 after reconnect/replay, seed `455834`. The
unchanged focused test and 40-test package baseline passed locally once; that
did not establish a cause. The deterministic diagnostic then held the owner,
queued its forwarding command, emitted a real delta and observed the client's
TCP receipt/status barrier. The connection was already closed, rather than an
event merely arriving late (`/tmp/samgita-ws-repair-forced-control-red.log`).

The client conservatively counts **every** owner mailbox message against
`max_buffer`. The fixture's control command could occupy its sole slot before
the delta arrived. The resulting bounded disconnect was correct and left the
cursor unchanged. The test now acknowledges owner readiness before requesting
emission. No transport runtime, bound or timeout changes. Regression coverage
also deliberately saturates the control mailbox, requires reconnect/replay from
the retained checkpoint, and rejects oversized replay atomically without partial
forwarding or checkpoint advance. Retention exhaustion must return `replay_gap`.
Shutdown remains possible while the owner is awaiting a notification.

Executed from `apps/samgita_protocol_websocket`, under Devenv:

| Command | Result |
| --- | --- |
| `mix test test/integration_test.exs:384 --seed 455834 --max-cases 8` | 16 cases, zero failures, 15 excluded |
| `mix test --seed 455834 --max-cases 8` | 42 passed |
| `mix test --seed 0 --max-cases 8` | 42 passed |
| `mix test --seed 987654 --max-cases 8` | 42 passed |

Logs: `/tmp/samgita-ws-repair-green-focused.log` and
`/tmp/samgita-ws-repair-green-package-{455834,0,987654}.log`. These are bounded
recorded seeds, not retries until green. The README documents control-message
accounting and the dedicated-consumer requirement.

## Reused-database recovery and listener shutdown

Read-only inspection of the retained restart database found one qualification
Task with an execution hold and one expired Attempt with unresolved effects;
there were no unmapped historical rows. The previous test deliberately proved
activation refusal, then left its simulated execution unresolved and deleted
its journal. PostgreSQL's fail-closed activation guard was correct.

For an unchanged-behavior reproduction, only journal deletion was removed. A
fresh `samgita_redesign_recovery_repro_test` run passed; the immediate repeat
failed before startup with `unmapped_or_unresolved_tasks`, seed `366499`.
The journal records one start and no cessation. That database and the original
retained restart database remain blocked and unchanged; no guard is bypassed and
no prior unresolved effect is silently resolved.

The repaired test first proves the same hold/refusal. It then explicitly stops
only its own fake execution through an idempotent, fsynced `stop_once` journal
operation. After checking durable cessation evidence, it invokes the existing
operator `Attempts.resolve` command with exact IDs, version and evidence
reference, twice to prove receipt replay. The Task remains blocked and
unaccepted; the expired Attempt, original start, delivery ACK and audit history
remain. Cessation evidence is retained on disk. There is no replacement dispatch.
New rollback-isolated guard tests retain genuinely unmapped work, a mapping
conflict and unresolved effects, while legitimate repeated mappings permit
activation without executing or accepting old work. Production guards and
migrations are unchanged.

A separate deterministic lifecycle test held the owned Bandit listener and
terminated FakeAgent's linked owner. It failed because FakeAgent exited before
awaiting the listener. FakeAgent now traps exits and synchronously stops its
owned listener; the regression requires listener shutdown before FakeAgent DOWN
and successful rebind of the same port, without sleeping. An initial diagnostic
used `:sys.suspend`, which still handles a parent EXIT; it failed in harness
cleanup. Replacing that barrier with Erlang process suspension produced the
intended pre-fix failure. No production change was based on the harness failure.

The independently created UTF-8 `samgita_redesign_recovery_repair_test` was
migrated once, never reset. With explicit socket/port/user environment set
**after** Devenv, the scoped command was:

```sh
mix test apps/samgita/test/samgita/recovery_activation_test.exs \
  apps/samgita_web/test/samgita_web/integration/fake_agent_lifecycle_test.exs \
  apps/samgita_web/test/samgita_web/integration/restart_reconcile_test.exs \
  --include e2e --seed 366499
```

The fresh run passed **4 core + 3 web** tests. The preceding full root suite then
populated that same database: **192 core + 120 web passed, 2 excluded**, seed
`437312` (before the new raw-HTTP tests existed). Two consecutive scoped repeats,
seeds `366499` and `888788`, each passed **4 + 3**. Logs:
`/tmp/samgita-recovery-repair-{fresh,populate,repeat-1,repeat-2}.log`.
Read-only inspection then found three retained restart Projects, each with one
blocked/unaccepted Task, one expired/resolved Attempt, one ACK and a journal
containing exactly one start/stop. No unresolved row remains in the repair
database. The deliberately blocked reproduction remains one held Task and one
unresolved Attempt. Neither database was cleared; no historical task was lost.

## A11: source-proven pre-application blocker

**A11 remains blocked. No safe credential-entry closure is claimed.** The
existing LiveView canary demonstrates plaintext in raw `handle_event` start and
stop metadata. Moving submission into a controller or an early Plug cannot
close the full raw-instrumentation path in the retained stack:

| Retained source | Emission boundary |
| --- | --- |
| Bandit 1.13.1 `lib/bandit/pipeline.ex:34-40` | Builds a full connection and emits `[:bandit, :request, :start]` before calling the application Plug |
| Bandit `lib/bandit/http1/socket.ex:197-199` | Keeps bytes received after the headers in the transport buffer, reachable through `conn.adapter` |
| Bandit `lib/bandit/telemetry.ex:199-210` | Retains start metadata and merges it into exception events |
| Plug 1.20.3 `lib/plug/telemetry.ex` | Emits full connections at endpoint start and stop |
| Phoenix 1.8.13 `lib/phoenix/endpoint/render_errors.ex` | Emits connection, reason and stacktrace on parser/error paths |
| LiveView 1.2.11 `lib/phoenix_live_view/channel.ex:568-571` | Emits raw event params before the application handler; removing a handler cannot sanitize a stale client's event |

`raw_http_telemetry_test.exs` uses the **real retained Bandit server** with small
coalesced TCP header/body writes. Its first diagnostic Plug reads/decodes the
body into local variables and never assigns credential params to the connection.
Nevertheless, server-start metadata already contains the plaintext and API-key
canaries, before the Plug's entry marker. A generic exception after that read
retains the original credential-bearing connection despite a secret-free reason.
Two other cases run the actual Phoenix Endpoint: unauthorized JSON and malformed
JSON expose plaintext in start/stop and error metadata. Terms are scanned using
external-term encoding, including adapter buffers; `Inspect` hiding fields cannot
produce a false negative. All four cases passed in the 49-test run above.
They are exposure evidence, not mock confidentiality acceptance.

Bandit's supported options provide no hook to replace/redact metadata before
these emissions. Application handler attachment order, post-emission filtering,
catching endpoint exceptions, exporter allowlists and encryption at rest cannot
undo server-start exposure. Auth headers alone expose API keys/Bearer tokens;
lease proofs in request parameters and intentional protected proof responses
are additional boundaries. Existing filters and limited metric projections are
retained, but do not certify arbitrary raw export. No real credential is used.

The minimum prerequisite is a reviewed supported upstream mechanism that
allowlists metadata **before emission**, covering transport buffers, headers and
retained exception metadata, together with the LiveView source boundary; or an
explicitly reviewed encrypted client/ingress contract that places no plaintext
credential on the instrumented wire. Implementing a custom cryptographic entry
protocol is a new security contract, not an HTTP-form relocation. This round
does not edit another repository, monkey-patch private framework state, remove
authentication/CSRF/validation or call the blocked gate passed. Independent
compatibility work continues while that prerequisite is unavailable.

SHA-256 identities of the inspected Hex sources:

```text
Bandit pipeline.ex: 0c86cc25a146c6ed6514812c8d761d09e3fd067533634d9c64769b797d4a5f5b
Bandit http1/socket.ex: 831cb5ae1e527529c6ddeccbfb6ab5aabcea0716fd18c99418541319d1ddebb4
Bandit telemetry.ex: 029c40cb8f7af0846cf76f3d2db72aab5305af37a52166e6027de05f76efbc40
LiveView channel.ex: e2973e1d30cc3542610127f116421f6bc3401d066d66996b97bde0f397b3b58c
```

## Codex WebSocket upgrade ordering

Pinned run `39983703308`, seed `501432`, exposed a separate driver transport
defect. `finish_handshake` switched Mint to active mode before queuing upgrade
bytes back to its owner. A later TCP continuation could enter the mailbox first,
so Mint decoded it without the first fragment and returned
`invalid_websocket_frame`. Extending a receive timeout cannot repair wire order.

The driver now retains the already bounded upgrade bytes in transport state.
Every socket-response path consumes that prebuffer before later bytes; the
self-message only wakes an idle consumer and cannot replay consumed data. The
shared WebSocket/UDS handshake, original frame/message/read limits, control-frame
handling and process ownership remain intact.

Three regressions use an explicitly released real loopback server and selectively
handle the later TCP message before the queued upgrade wakeup. They require the
fragmented message/pong/close order, complete-message order without duplicate
wakeup delivery, and enforcement of advertised-frame and fragmented-message
limits. With production unchanged they reproduced **three failures in 13 cases**,
including the hosted error. After the repair, all **13 cases passed** at seeds
`501432`, `455834` and `987654`; compilation with warnings as errors, focused
formatting and whitespace checks also passed. Existing WSS and UDS coverage is
retained. Logs are `/tmp/samgita-driver-websocket-{red-501432,green-501432,green-additional-seeds}.log`.
Full driver and hosted evidence against the delivered source is recorded
separately; these scripted frame peers do not establish all Codex behavior.

## Attestation prewarm event ownership

The first full continuation run after the upgrade-ordering repair passed all
34 protocol cases, then failed **one of 203 driver cases**, seed `501432`.
The actual Responses WebSocket handshake carried `{"v":1,"s":1}` instead of
the explicitly returned synthetic attestation token. The second requested seed
did not run after that failure. Log:
`/tmp/samgita-codex-continuation-independent-final.log`.

Pinned `app-server/src/attestation.rs:19,82–109,139–146` defines a **100ms native
deadline** and distinguishes timeout (`s=1`) from refusal/failure (`s=2`). The
matching upstream test, `app-server/tests/suite/v2/attestation.rs:108–163`,
explicitly services incoming requests while waiting for both `thread/start`
and `turn/start`: prewarming can request attestation before either RPC returns.
Our fixture serviced only the first RPC concurrently. Its synchronous
`turn/start` prevented its event owner from answering the second RPC's incoming
request before the native deadline. No production driver defect is established
by this failure.

The test now pumps interactions while awaiting `turn/start` and carries forward
already-drained completion events. The successful-token assertion remains exact.
Two additional actual-binary tests deliberately withhold a response or explicitly
refuse it and require the corresponding exact handshake envelopes, without
sleeping, extending the native deadline or inventing a successful response.
The five auth cases passed at seeds `501432`, `513498` and `987654`; package
formatting and scoped whitespace checks passed. Log:
`/tmp/samgita-codex-attestation-repair-final.log`. Full-suite and hosted results
are separate checks. Synthetic local credentials and provider acceptance do not
qualify a real attestation service or account.

## Continuing gates

The pushed repair head `63588cdc442436e9f4cb2b085b9699a0f5c1d370` reached
terminal hosted results:

- Aggregate [39983577211](https://github.com/gsmlg-opt/Samgita/actions/runs/39983577211)
  passed the complete foundation job, including repeated populated root tests,
  isolated restart, independent packages/consumers, static/assets/legacy checks,
  Dialyzer, dependency audit and local production assembly. Assembly is not
  publication or deployment, and the fresh hosted restart does not replace the
  consecutive local populated-database evidence above.
- Pinned conformance [39983703308](https://github.com/gsmlg-opt/Samgita/actions/runs/39983703308)
  passed the 34-test native schema package, then failed the independent driver:
  **169 tests, one failure**, seed `501432`. The fragmentation/ping/close case
  returned `invalid_websocket_frame` instead of the ordered message and close.
  Outside-consumer and platform stages were skipped. This is a newly identified
  Codex-driver upgrade-buffer ordering defect, distinct from the repaired neutral
  protocol mailbox/replay scenario. Its deterministic repair and final-source
  evidence are tracked in qualification. The strict completeness job also failed
  because required evidence remains missing; the overall workflow is failed.

The pinned inventory check and its 15 Python regressions passed after these
repairs. Counts are generated from the pin, not inferred from selected passing
journeys: **0 verified / 1 implemented / 480 missing / 4 blocked requirements;
0 verified / 3 implemented / 6,618 missing contracts**. The notification's scoped
implementation status is distinct from full qualification. Legacy approvals retain their schemas and
[exact upstream reachability evidence](legacy-approval-qualification.md); no
scripted peer is counted as enabled real-binary legacy success. Required external
account/backend/OS profiles remain incomplete. No release/tag, package
publication, deployment, production migration or sibling-service change occurs.
