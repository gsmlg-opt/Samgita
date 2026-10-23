# Codex compatibility qualification

Status: **incomplete**. The manifest records **0 verified / 485 missing requirements**
and **0 verified / 6,621 missing field/variant contracts**. Selected passing
journeys and generated schemas do not establish complete compatibility. The
accepted contract remains [the full goal](goal.md). The
[current repair record](repair-qualification.md) supersedes the dependency-audit,
WebSocket synchronization and reused-database fixture failure claims below for
its tested scope. A11 remains blocked: real HTTP evidence now proves plaintext
can enter server telemetry before application handling. Full compatibility and
release readiness remain incomplete.

## Delivered source and immutable reference

The historical runtime checkpoint is
`d63dcddae49c0c7c7b5565482134d4282275a86c`, on existing `main`. It adds
`49d1c37e23404f6255fd742c70f7dd23bc27f4c9` (confirmed owned-process shutdown)
and retained legacy contract tests to the previous native platform checkpoint
`39ff43fa32961282628d9616f0b015b8d072fd5d`. The previous checkpoint includes
`f14afc2` (omitted source contracts), `f5d6530` (additional actual-binary scenarios)
and `a88a456` (atomic Session dispatch fences). Its table below is historical;
current checks are in the owned-process repair section. Baseline inspection
started at `4fe354f2ce916aa32517c361a171b8878bf6ca84`. Following documentation
changes do not change the executable source. Native turn test coverage is
extended at `73258c516bcf5c7f40d4cedde5d3a149314d086f`, as recorded below.

| Artifact | Immutable identity |
| --- | --- |
| Official release | `rust-v0.163.0` |
| Source commit | `83086188ae0614bd882818ff1aa23f3194962012` |
| Tag object | `129b8ec7ee6f4511557a4856279f529025c25af4` |
| Linux musl binary SHA-256 | `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` |
| Release archive SHA-256 | `beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4` |
| Source archive SHA-256 | `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567` |

`python3 scripts/codex/fetch_pin.py` reverified the pin on 2026-10-23. The
executable/source cache is ignored `tmp/codex/0.163.0/`, outside package contents.
Qualification currently covers Linux `x86_64-unknown-linux-musl`. Test children
use disposable homes/configuration/workspaces and loopback synthetic model,
authentication, MCP and attestation fixtures. No account or paid provider was used.

The 318 stable and 452 experimental official JSON artifacts retain their original
bytes/hashes. A separately labeled, locally derived supplement accounts for
`getConversationSummary`, `getAuthStatus`, `gitDiffToRemote`,
`rawResponse/completed` and `rawResponseItem/completed`, using matching pinned
TypeScript and Rust/serde declarations. Provenance and source hashes live in
`apps/samgita_protocol_codex/priv/upstream/0.163.0/provenance.json`. Source discovery
now includes 175 client methods and 87 server notifications. This is inventory
coverage, not runtime acceptance.

## Previous executable checkpoint local checks, 2026-10-23

All checks in this table were actually run by the coordinator after the
`39ff43f` executable edits, before the shutdown repair, serializing Mix builds.
Package commands run from their own
directories inside `devenv shell --no-tui --`, with Elixir 1.18.5 / OTP
27.3.4.17. Root test commands additionally use:

```sh
MIX_ENV=test PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao \
  SAMGITA_TEST_DATABASE=samgita_redesign_codex_runtime_test \
  CODEX_BINARY=/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl
```

| Check | Exact command/scope | Observed result |
| --- | --- | --- |
| Root compilation/format | `mix compile --warnings-as-errors`; `mix format --check-formatted` | Passed |
| Strict Credo | `mix credo --strict` | Passed; 251 files, 69 checks, no issues |
| Retained/redesign suite | `mix test`, then `mix test` on the populated database | Each run: 188 core tests; 114 web cases, 2 dedicated e2e cases excluded; zero failures |
| Native platform/API journey | `mix test apps/samgita_web/test/samgita_web/controllers/codex_runtime_controller_test.exs apps/samgita_web/test/samgita_web/integration/codex_runtime_test.exs --include e2e` | 4 passed, including two ordinary Agent names, explicit synthetic approval, progress/artifact, review and acceptance |
| Restart/rollback | `SAMGITA_TEST_DATABASE=samgita_redesign_restart_test mix test apps/samgita_web/test/samgita_web/integration/restart_reconcile_test.exs --include e2e` | 1 passed on isolated database |
| Neutral packages/outside consumers | `python3 scripts/verify_isolated_protocol.py` | 32 core tests plus 1 pure and 1 WebSocket outside-consumer test passed; independent compilation/format passed |
| Optional transport | In `apps/samgita_protocol_websocket`: `mix test`; `mix compile --warnings-as-errors`; `mix format --check-formatted` | 40 passed; static checks passed |
| Codex wire | In `apps/samgita_protocol_codex`: `mix test`; `mix compile --warnings-as-errors`; `mix format --check-formatted` | 32 passed; static checks passed |
| Complete driver suite | In `apps/samgita_codex_driver`: `CODEX_BINARY="$PWD/../../tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" mix test`; `mix compile --warnings-as-errors`; `mix format --check-formatted` | 89 passed; static checks passed |
| Independent Codex consumer | `python3 scripts/codex/verify_consumer.py` | Fresh outside resolution, warnings-as-errors compilation, 1 actual-binary test and formatting passed; no Repo/Phoenix/platform/config inheritance |
| Inventory | `python3 scripts/codex/inventory.py --check` | Passed; 485 requirements / 6,621 contracts, all still missing |
| Inventory regressions | `python3 -m unittest discover -s scripts/codex -p 'test_*.py' -v` | 12 passed |
| Legacy runtime gate | `python3 scripts/test_check_legacy_runtime.py`; `python3 scripts/check_legacy_runtime.py` | 4 passed; scan passed |
| Frozen web installation | `python3 scripts/install_web_dependencies.py --isolated` | Passed; Bun 1.3.13, 1,212 packages, 126.98 seconds; lockfile unchanged |
| Assets | `mix assets.build` | Passed |
| Dialyzer | `mix dialyzer` | Passed; 0 errors, 0 skips |
| Dependency security | `mix hex.audit` | **Failed**: retained `plug_crypto 2.2.0`, EEF-CVE-2026-105963 / CVE-2026-105963 / GHSA-ffw9-w85g-f2vh |
| Local production assembly | `MIX_ENV=prod MIX_BUILD_PATH=/tmp/samgita-codex-production-build mix deps.get --only prod`; `mix compile --warnings-as-errors`; `mix assets.deploy`; `mix release --overwrite` under the same prod environment | Passed with synthetic runtime settings; unpublished local 0.1.0 assembly only, not started/deployed |
| Full compatibility gate | `python3 scripts/codex/inventory.py --check --require-verified` | **Failed**: unverified requirements remain; must prevent a full compatibility claim |
| Whitespace/YAML | `git diff --check`; staged whitespace checks; Bun YAML parse of the new workflow | Passed |

The four native concurrency cases use distinct PostgreSQL backend PIDs and retain
their committed records through authorized cleanup. Full root tests include fresh/
additive history preservation fixtures. Both new native migrations were applied
to the existing populated scratch database; no reset or record deletion occurred.
The local host refreshed during review; Devenv and the existing scratch cluster
were restored without initializing it again. The separate restart database did
not exist. Its first Mix create failed because this local cluster's template1 is
SQL_ASCII; explicitly creating the named scratch database as UTF8 from template0
resolved that environment prerequisite. No application migration was changed for it.

The security advisory concerns secret-key-base exposure in stacktrace arguments
after wrong-typed Plug.Crypto calls. The root and optional WebSocket lockfiles
still contain affected 2.2.0. This checkpoint does not upgrade the retained
dependency or mark the audit passed. Fresh outside consumers resolved 2.2.1;
that does not repair or qualify either retained lockfile. Keep this release gate
blocked and handle the dependency remediation as its own scoped change.

## Behavior and corrections demonstrated

Actual executable scenarios cover stdio, authenticated WebSocket, borrowed UDS,
selected method families, complete item delivery, explicit approvals, dynamic
tools, plan input and reconnect/read/resume without a second execution. Two
method-family suites contain 28 selected scenarios. Existing plus new journeys
cover selected behavior across 9/11 server-interaction families. Legacy
`applyPatchApproval` and `execCommandApproval`, remaining decisions/fields and
external success profiles remain unqualified. The subsequent
[legacy approval audit](legacy-approval-qualification.md) documents that the
immutable target retains those schemas but has no production emission path or
legacy negotiation switch. Scripted contract tests and actual rejection of
removed client APIs cannot qualify an enabled legacy approval success path.
Neither family is excluded from the target or counted as verified.
Synthetic token refresh/header
forwarding is not real account, signed-JWT or attestation-service acceptance.

Scripted faults separately exercise framing, TLS rejection, correlation,
deadlines, caller loss, bounded buffers and uncertain sends. TLS rejection tests
deliberately emit certificate alerts. No local command ID promises upstream
deduplication. Only explicitly asserted synthetic commands/patches in disposable
workspaces are approved; no general auto-approval policy was installed.

The platform journal validates current authority before replay and settlement,
encrypts complete native payloads, issues one-use tickets and never dispatches
from registration, schedules, event delivery or restart. Native completion does
not report/accept a Task. See [the API and recovery contract](platform-integration.md).
Review reproduced and corrected:

- Unconfirmed interaction replies were omitted from mutation ambiguity guards.
- Operator replies did not check the current execution authority epoch.
- Local driver selection checked generation without checking process identity.
- A status-check/send race could cross reconnect; atomic Session instance,
  generation and deadline guards now reject before sending. Three new Session
  regressions failed before the fix and passed afterward.
- Native identity/correlation omitted generation; same-instance reconnect could
  reject reused IDs or settle an old uncertain approval. Three new database
  regressions failed before generation-qualified queries/indexes and passed after.

Strict Credo initially rejected complexity in the two new fixes. Small helper
extractions preserved the predicates/guards; final Credo passed without exclusions
or warning suppression. A populated-database test assertion was also corrected
to inspect its own runtime records rather than assume a globally empty journal.

Earlier native-layer corrections preserved Rust Option/union gates, runtime
notification annotations and full output fields. Missing TypeScript legacy
exports are now accounted for separately. Early shell-discovery, image-fixture,
skill/config and provider-capability fixture assumptions were corrected against
matching source/runtime behavior; those changes did not weaken assertions or gates.

## Owned-process shutdown repair

The hosted teardown failure led to a deterministic regression: a delayed SIGTERM
handler writes a cleanup marker, and `close` must wait for that marker before
returning, including after the original owner dies. It failed against immediate
`Port.close/1`. The repair adds a port guardian and shared completion reference;
success requires the helper's protected cleanup acknowledgement and exit, rather
than port disappearance. Later close calls retain that confirmed outcome.

The helper bounds input buffering, accepts private shutdown control under input
backpressure, rejects child NUL output, and reaps owned descendants on Linux.
Only an explicitly unsent control byte may be retried within the shutdown
deadline; native requests and directory deletion are never retried. The direct
child stays unreaped until the main thread finishes signalling its process group,
preventing group identity reuse. A deterministic helper regression checks child
waitability and thread identity at each group signal.

Session settles pending mutations as uncertain before attempting shutdown.
Unconfirmed cleanup leaves a visible `shutdown_failed` state, returns a typed
error and refuses reconnect. Framing-overflow cleanup failures follow the same
uncertainty path. The model fixture now uses the same owned-process cleanup.
Borrowed servers/sockets remain untouched and `File.rm_rf!` assertions remain
strict. Non-Linux lifecycle behavior remains unqualified.

The expanded repair exposed two implementation failures before final validation:
backpressure initially closed the cleanup-ACK channel too early, and a boolean
test incorrectly used the tuple returned by `Port.info/1`. Both were corrected;
review then found and fixed the process-group identity and overflow propagation
issues above. One recovery test invocation omitted `CODEX_BINARY`; its two
environment failures passed after restoring the pin without changing source.

Final focused command, in the independent driver package with the pinned binary:

```sh
mix test test/transport_stdio_test.exs test/session_test.exs test/legacy_approval_contract_test.exs
```

Observed: **45 tests, zero failures**. Subsequent coordinator checks used the
final source, including the added legacy tests and corrected alias ordering:

| Check | Observed result |
| --- | --- |
| Independent driver compile/format/full suite | Passed; **102 tests, zero failures**, seed `689291` |
| Outside-umbrella actual-binary consumer | Fresh independent resolution, compile, **1 test**, formatting passed; seed `921459` |
| Root compile/format/strict Credo | Passed; 253 files, 69 checks, no issues |
| Root suite and populated-database repeat | Each: **188 core tests; 114 web cases, 2 excluded; zero failures** |
| Native platform/API journey | **4 passed**, including both ordinary Agent names and explicit approval/review/acceptance |
| Restart/rollback on reused `samgita_redesign_restart_test` | **Failed before driver startup**: activation returned `conflict`, reason `unmapped_or_unresolved_tasks` |
| Dialyzer/assets | Passed; zero Dialyzer errors/skips; assets built |
| Security audit | **Failed** on retained `plug_crypto 2.2.0`, CVE-2026-105963; no dependency change |
| Local production compile/assets/archive | Passed; archive and extracted helper bytes match final source; not started, published or deployed |
| Inventory consistency/regressions | Passed; **12 tests**; all 485 requirements and 6,621 contracts remain missing |
| Legacy scan/regressions | Passed; **4 tests** |
| Strict completeness | Failed as required on unverified entries |

The repeated restart failure occurs in the existing `activate_fixture/0`, before
the selected driver code runs. The prior successful restart used that database
when it was fresh. No test, activation rule, mapping or retained database record
was changed to bypass the failure. It remains a failed local reused-database
check; a fresh hosted run cannot retroactively make that repeat pass. Initial
final-source static checks also caught an unformatted blank line and alias order;
both were corrected without suppressing checks.

The production archive is
`/tmp/samgita-codex-production-build/samgita-0.1.0.tar.gz`, SHA-256
`6bb5d46051d12297f09f5e9f1c74e2c15b67f863f053fd3de86ddb17fcd7f355`.
Its initial verification used an incorrect extra `/prod/` path component. The
assembly itself had succeeded; checking the actual release path and tar member
confirmed both contain the current helper. This is local packaging evidence,
not a passed security gate or a published release.

## Native turn input and parameter checkpoint

Test commit `73258c516bcf5c7f40d4cedde5d3a149314d086f` adds 23 scenarios across
three new independent-driver suites and a shared isolated fixture helper. No
native schema, driver or platform runtime changed. The new tests cover every
UserInput form, selected enabled/disabled/invalid parameter behavior and persisted
text spans/client IDs across a confirmed owned-process restart. Detailed source,
profile and semantic limits are in [turn qualification](turn-input-qualification.md).

The final local compile, formatting and full driver suite passed **125 tests,
zero failures**, seed `959437`, under Devenv Elixir 1.18.5 / OTP 27.3.4.17 with
the hash-verified pinned executable. Review strengthened structured-skill
selection evidence, both item lifecycle assertions, asserted cleanup and
cross-VM scratch-path isolation before this final run. Initial failures exposed
incorrect test-profile/expectation assumptions, not a demonstrated driver bug:
the catalog requires an instruction template, default metadata lacks audio input,
and pinned preparation omits low-detail inline/local images, remote audio and
corrupt media with explicit placeholders. No upstream/runtime behavior was
patched to make those cases pass.

These are selected Linux/stdio client and provider-payload results, not live
media understanding, remote file resolution, enabled app/plugin/MCP routing or
complete parameter/transport coverage. All 485 requirements and 6,621 contracts
remain missing; selected evidence does not clear their full acceptance conditions.
The prior neutral WebSocket aggregate failure, local reused-restart failure,
Plug.Crypto advisory and A11 confidentiality blocker remain separately recorded.
The outside-umbrella consumer also passed fresh dependency resolution,
compilation, formatting and **one actual-binary test**, seed `208583`; it verified
that Repo, Phoenix and the umbrella application were absent. Its hosted results
are recorded below. No release or platform-readiness claim follows from this
test-only checkpoint.

## Standalone output, settings and MCP-startup follow-up

Test commit `50abfe3` adds ten real-binary `toolOutput` scenarios across stable and
experimental negotiation and four override/validation scenarios. Commit `9791d54`
adds one paired controlled MCP-startup scenario. These change tests and a synthetic fixture, with
no native schema, driver or platform-runtime change. Exact contracts and residual
limits are in [turn qualification](turn-input-qualification.md).

An initial 14-case run caught an incorrect assertion that old developer text
would disappear after a settings update. Pinned history correctly preserves old
messages. Fresh threads isolate the three collaboration-instruction profiles;
all four override scenarios then passed. Review added exact name/input semantic
rejections in both negotiation profiles and stronger explicit-preset and MCP
output assertions. No production behavior or gate was changed to pass these tests.

The final independent driver compile, formatting and full suite passed **140
tests, zero failures**, seed `12198`, under Devenv Elixir 1.18.5 / OTP 27.3.4.17
with the pinned executable. Root strict Credo passed on all 260 source files.
After the semantic validation assertions, the 14 affected output/settings tests
passed, seed `61059`, plus strict Credo. A fresh outside consumer passed independent
dependency resolution, warnings-as-errors compilation, formatting and one
actual-binary test, seed `740994`, with no Repo/Phoenix/umbrella present. Inventory
consistency and all 12 Python regressions passed. Strict full compatibility failed
as required with all 485 requirements and 6,621 contracts still missing. No
compaction retention, enabled external MCP authorization, live model/service
acceptance or full transport matrix is claimed.

## Hosted evidence and remaining gates

Historical hosted [39928300713](https://github.com/gsmlg-opt/Samgita/actions/runs/39928300713)
failed strict Credo on `923b290`; later database/consumer/assets/audit/assembly
steps were skipped. Historical [39930133440](https://github.com/gsmlg-opt/Samgita/actions/runs/39930133440)
passed on `1422309d82706eb8ed8faf69f378433c155e31f3`. Neither run qualifies the
current native integration. Earlier local 29-wire/63-driver results and 477/
6,549 inventory totals likewise describe earlier source, not this checkpoint.

The new manual `Pinned Codex conformance` workflow has two independent jobs:
selected actual-binary/package/consumer/platform tests and a strict full-manifest
evidence gate. Missing entries intentionally fail the latter; it is not
continue-on-error and cannot be replaced by selected scenario success. Ordinary
CI retains its aggregate security and assembly gates.

The six logical checkpoint commits were pushed through
`af6cebb0f3e409a5f50ff667640e63e0f217cd06`; HEAD, `origin/main` and the live
remote agreed. Both hosted workflows reached terminal failure on that revision:

- Aggregate [39952609810](https://github.com/gsmlg-opt/Samgita/actions/runs/39952609810)
  passed compilation, formatting, Credo, repeated root tests, restart, independent
  packages/consumers, assets, legacy scan and Dialyzer. It failed `mix hex.audit`
  on the retained Plug.Crypto advisory; production assembly was skipped.
- Pinned conformance [39952677405](https://github.com/gsmlg-opt/Samgita/actions/runs/39952677405)
  passed the native wire suite, then failed four of 89 driver tests during
  `File.rm_rf!` teardown. Outside-consumer and platform steps were skipped. Its
  independent strict completeness job failed on missing evidence as required.

The teardown failure exposed an owned-process lifetime bug: `Port.close/1`
returned while the Python helper was still terminating Codex. An ExUnit test
process could also die before its `on_exit` callback, leaving the callback unable
to await the already closed port. The Codex process could continue writing into
the fixture directory during deletion. This invalidates the earlier local-only
shutdown qualification; cleanup errors must remain asserted. The repair and
renewed local results appear above.

The repair, legacy contract evidence and qualification documents were pushed
through `6e19d696f537907869087fe916b0227819b098aa`; HEAD, `origin/main` and the
live remote agreed. Both hosted reruns reached terminal states on that revision:

- Aggregate [39958837990](https://github.com/gsmlg-opt/Samgita/actions/runs/39958837990)
  **failed**. Compilation, formatting, strict Credo, repeated root tests and the
  fresh isolated restart/rollback rehearsal passed. The independent neutral
  WebSocket suite then reported **40 tests, one failure**, seed `455834`:
  `overflow leaves an unforwarded event recoverable, then replay and live checkpoints advance`.
  `take_owned_notification/1` received no matching message within 100 ms while
  waiting for replay cursor 2 (`test/integration_test.exs:424,490`). The cause is
  unqualified; this result is not classified as a harmless timing failure. No
  transport code, test timeout or assertion was changed. Assets, legacy scan,
  Dialyzer, security audit and production assembly were skipped in this run.
  The earlier local checks and retained audit failure remain separate evidence.
- Pinned conformance [39958930872](https://github.com/gsmlg-opt/Samgita/actions/runs/39958930872)
  **passed its selected actual-binary and platform job**: 32 native protocol
  tests, 102 driver tests, one outside-umbrella consumer test, 21 fenced
  platform/API/concurrency tests and four actual-binary platform journey tests,
  all with zero failures. This supplies hosted evidence for the shutdown repair;
  it does not qualify every advertised behavior. The workflow's independent
  strict completeness job **failed as required** with all 485 requirements and
  6,621 field/variant contracts still missing. The overall workflow is failed.

The neutral WebSocket failure is outside the delivered Codex shutdown/legacy
contract scope and remains reported without a repair. The successful fresh
hosted restart does not clear the failed local reused-database rehearsal above.
Subsequent documentation-only changes do not alter this tested executable tree.

The native turn checkpoint at `f777b514f9db5a60ac38fede98b2aa73749bd756`
had two observed hosted results:

- Aggregate [39963526529](https://github.com/gsmlg-opt/Samgita/actions/runs/39963526529)
  failed strict Credo on two unseparated `-32600` literals in the new turn test.
  Later aggregate steps were skipped. No runtime failure was established there.
- Pinned conformance [39963631668](https://github.com/gsmlg-opt/Samgita/actions/runs/39963631668)
  passed its selected job: 32 protocol tests, 125 driver tests, one outside
  consumer test, 21 platform/API/concurrency tests and four platform journeys.
  Its strict full-evidence gate failed as required.

The literal repair `8970df817fa928cae9b582e3842520b641542a90` passed local strict
Credo and all ten affected turn-input cases, seed `16364`. Its aggregate
[39964413395](https://github.com/gsmlg-opt/Samgita/actions/runs/39964413395) passed
compilation, formatting, strict Credo, repeated root tests, fresh restart/rollback,
independent protocol packages/consumers, assets, legacy scan and Dialyzer. It failed
`mix hex.audit` on retained `plug_crypto 2.2.0`, CVE-2026-105963, and skipped
production assembly. That rerun passes the neutral WebSocket scenario but does
not explain its preceding failure or clear the retained local restart repeat.
Both follow-up workflows reached terminal states at
`4690295375d7297b305508ba0099a644793ca35b` (test source `50abfe3` / `9791d54`):

- Aggregate [39966363211](https://github.com/gsmlg-opt/Samgita/actions/runs/39966363211)
  **failed** the retained application restart/rollback test, seed `888788`, after
  passing compile, format, strict Credo and repeated root tests. Restarting the
  fake Agent at `restart_reconcile_test.exs:138` failed to bind port `34755` with
  `:eaddrinuse` (one test, one failure). This is distinct from the retained local
  activation conflict. The cause remains unqualified; no listener/test change,
  timeout increase, database reset or gate bypass was made. Independent neutral
  packages, assets, legacy scan, Dialyzer, audit and assembly were skipped in this
  run. Earlier outcomes remain separate evidence.
- Pinned conformance [39966435643](https://github.com/gsmlg-opt/Samgita/actions/runs/39966435643)
  **passed its selected actual-binary and platform job**, including the new
  output/settings/MCP scenarios: 32 protocol tests, 140 driver tests, one outside
  consumer test, 21 platform/API/concurrency tests and four platform journeys,
  all with zero failures. Its independent strict
  full-evidence gate **failed as required**; the overall workflow is failed.

The aggregate restart failure is outside this native-turn qualification unit.
No retained platform behavior was changed to obtain a passing rerun. Aggregate
[39967256870](https://github.com/gsmlg-opt/Samgita/actions/runs/39967256870), on
`9684fdd4eaa0c830878aeee6663bdffc03025873`, subsequently passed compile, format,
strict Credo, repeated root tests, fresh restart/rollback, protocol consumers,
assets, legacy scan and Dialyzer. Its actual failed log reports
`plug_crypto 2.2.0`, `EEF-CVE-2026-105963` / `GHSA-ffw9-w85g-f2vh`; production
assembly was skipped. That success does not diagnose the preceding listener
failure or qualify the retained local reused-database restart.

## Initialization, image preparation and Unicode checkpoint

Commit `c48dd08` adds two native schema tests, nine actual-binary raw
transport cases, eight scripted initialization lifecycle cases and scoped
manifest evidence mappings. Commit `9193def` adds eight actual-binary
image/Unicode cases, plus one PNG-checker regression. See
[initialization qualification](initialization-qualification.md) and
[turn qualification](turn-input-qualification.md) for exact semantics and limits.
The generator's notification self-prerequisite regression failed before the
metadata repair and passed afterward. Pin/schema files, driver runtime,
platform/database behavior and release gates are unchanged.

The coordinator executed these checks on the final test tree based on `9684fdd`,
using Devenv Elixir 1.18.5 / OTP 27.3.4.17 and the pinned executable. Mix/Devenv
builds were serialized. Package commands run in their own directory;
`CODEX_BINARY` is the absolute pinned executable and `MIX_ENV=test` is set for
repository checks.

| Check | Exact scope/command | Observed outcome |
| --- | --- | --- |
| Native schema package | `mix compile --warnings-as-errors`; `mix format --check-formatted`; `mix test` | 34 tests passed, seed `327254` |
| Driver final test tree | `mix compile --warnings-as-errors`; `mix format --check-formatted`; `mix test` | 166 tests passed, seed `714912`; includes all 26 added driver cases |
| Root formatting/static | `mix format --check-formatted`; `mix credo --strict` | Passed; 266 files, no Credo issues |
| Outside consumer | `python3 scripts/codex/verify_consumer.py` | Fresh independent dependency resolution/compile/format and one real-binary test passed, seed `792498`; Repo, Phoenix and umbrella absent |
| Generator/source consistency | `python3 scripts/codex/inventory.py --check` | Passed; 485 requirements and 6,621 contracts |
| Python regressions | `python3 -m unittest discover -s scripts/codex -p 'test_*.py' -v` | 13 passed, including red/green prerequisite regression |
| Full completeness | `python3 scripts/codex/inventory.py --check --require-verified` | Failed as required: all 485 requirements and 6,621 contracts remain missing for full acceptance |

An initial full run passed 165 tests but exposed incorrectly addressed test-owner
notifications in the new scripted helper. The helper now explicitly assigns the
test process as Session owner. The focused eight cases, fresh outside consumer,
root checks and final full suite above passed after that correction; no runtime
workaround or suppressed log assertion was introduced. Review also replaced
latest-global image capture with exactly one appended request per submission,
added complete fixture PNG/pixel validation and corruption checks, and proved
borrowed WS/UDS server survival with a fresh connection and protocol round trip.
The 26 affected driver cases passed after these repairs, seed `999926`, plus
strict Credo. Scoped initialization
evidence is attached to its two manifest entries, with incomplete profiles and
native Session notification access still recorded. No entry is promoted to full
verification from selected examples.

Both hosted workflows reached terminal states at
`3c54d748871313bd69858ff05d0fd2c606019e6a`:

- Aggregate [39975272562](https://github.com/gsmlg-opt/Samgita/actions/runs/39975272562)
  passed compilation, formatting, strict Credo, repeated root tests, fresh
  restart/rollback, independent protocol consumers, assets, legacy scan and
  Dialyzer. It failed `mix hex.audit` on retained `plug_crypto 2.2.0`,
  `EEF-CVE-2026-105963` / `GHSA-ffw9-w85g-f2vh`; production assembly was skipped.
  Passing restart and neutral WebSocket checks do not explain their earlier
  failures or clear the reused-database restart result.
- Pinned conformance [39975362507](https://github.com/gsmlg-opt/Samgita/actions/runs/39975362507)
  passed the 34-test native schema suite. The driver reported **166 tests, one
  failure**, seed `513498`: the Unicode-boundary test's `on_exit` scratch removal
  raised `File.Error` (`file already exists`) after its assertions. Outside
  consumer and platform steps were skipped. Its independent strict completeness
  gate also failed as required. Local success above is not a substitute for this
  failed hosted test. The log does not identify a writer or establish the exact
  filesystem cause.

### Fixture cleanup after linked Session death

The subsequent source audit establishes a missing fixture barrier, without
identifying the writer in that hosted failure. ExUnit 1.18.5 exits its test
process with `:shutdown`; linked processes exit asynchronously before `on_exit`
callbacks. The non-trapping Session can therefore die without `terminate/2`.
Its independent Stdio guardian still confirms and records owned-process shutdown,
but the fixture's `Process.alive?(session)` guard skipped the close call needed to
wait for that confirmation. Closing the separate model-provider fixture does
not wait for Codex.

`StdioSessionFixture` now captures the initial Stdio connection immediately after
Session startup. Its callback closes a live Session and always waits for the
captured guardian in `after`, including when Session is dead or closing raises.
TurnFixture and five older stdio test starters use this shared callback before
their provider/root cleanup. Current callers never reconnect these owned stdio
Sessions; future reconnecting fixtures must retain every replacement guardian.
Borrowed WebSocket reconnect/resource ownership and production driver code are
unchanged. The existing persistent completion and unconfirmed-shutdown failure
contracts remain asserted; no deletion retry, sleep or swallowed cleanup error
was added.

The deterministic regression suspends the real guardian, terminates Session's
linked owner, waits for Session death and proves cleanup must issue a guardian
close before it can finish. It then resumes the guardian and requires confirmed
completion. The old callback failed that ordering assertion (two tests, one
failure, seed `513498`); the repaired helper passed both tests with the same seed.
The second test covers live Session close and repeated cleanup after an explicit
close. A third regression queues a live close on a suspended Session and then
terminates its linked owner. It reproduced the expected `GenServer.call` shutdown
race (three tests, one failure) before the helper handled only the exact close
call's `:noproc`, `:normal` or `:shutdown` exits. All three regressions then passed
with seed `513498`; the guardian barrier still runs in `after` and all other exits
and unconfirmed shutdowns propagate. This is a local Python-child fault fixture, separate from actual-Codex
behavior evidence. An initial harness run lacked required isolated `CODEX_HOME`
and failed before reaching the assertion; the corrected harness produced the
intended red/green result. No runtime change was based on that setup failure.

Final independent driver verification for this fixture repair ran
`mix compile --warnings-as-errors`, `mix format --check-formatted` and
`mix test --seed 513498` under Devenv Elixir 1.18.5 / OTP 27.3.4.17 with the
immutable executable: **169 tests, 0 failures**, 74.8 seconds. The full suite
includes the three cleanup regressions; synthetic shutdown ordering and actual
Codex scenarios remain distinct evidence. The local command log is
`/tmp/samgita-repair-driver-final.log`. A new hosted run is still required.

| Layer | Remaining requirement |
| --- | --- |
| Manifest | Per-entry and field/behavior evidence; all 485 / 6,621 entries remain missing, not mass-marked verified from forwarding or fixtures |
| Methods/interactions | Remaining enabled/disabled/error/differential and legacy approval variants, including full parameter surfaces |
| External/platform matrix | Real account/backend authentication, signed-JWT success, external tools/services and other OS/backend success profiles require appropriate controlled authorized environments; none was provisioned |
| Security/readiness | Retained Plug.Crypto advisory repaired; A11 raw server/LiveView credential telemetry still blocked; target-specific egress/key/legacy-cutover and real backup/memory rehearsals remain |
| Hosted | Repair-head aggregate `39983577211` passes, including dependency audit and assembly. Pinned `39983703308` fails a newly identified driver upgrade-buffer ordering defect; full evidence gate remains red. See repair record for listener and consecutive reused-database repairs |
| Publication/deployment | No normal package/tag publication workflow currently exists; CD remains disabled; no package publication or deployment is claimed |

New migrations are additive and refuse destructive down migration. Rollback
retains journals/keys and requires compatible software, writer fencing and
explicit assessment of uncertain effects; see [platform integration](platform-integration.md)
and [legacy migration/rollback](../redesign/migration-rollback.md). No production
migration, real credential change, sibling-service modification, release tag,
publication or deployment occurred. The full goal remains active and incomplete;
continue with [the implementation ledger](implementation-plan.md).
