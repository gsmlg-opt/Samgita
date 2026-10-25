# Management and local redesign qualification

Date: 2026-10-23. Scope: persisted management UI, complete fake-Agent journey, local restart/rollback and final aggregate checks. This record extends [acceptance](acceptance.md); it does not certify a production cutover, published package or real provider integration.

The reliability repair below supersedes the original P5 aggregate failures and reused-database limitation. The original P5 commands, browser observations and totals remain prior evidence from `91567e5116cb10f702a57012485ceed812b87d21`; they are not new browser runs. A11 remains blocked. No release or deployment is certified.

Current Codex work follows the user's prohibition on security and permission
tests. The [timeline error checkpoint](../codex-app-server/timeline-error-values-qualification.md)
passes 51 ordinary real-binary cases at each of two seeds, static checks and an
outside consumer, including independent raw/API error formats, explicit recovery
and cold no-load history/timeline persistence; it does not rerun the broad
suites or hosted workflows below.
Yolo is owned-fixture setup, with no permission assertions. All unrun gates,
A11, real-provider acceptance and full compatibility remain incomplete; no
release is authorized by these local results.

The [current repair qualification](../codex-app-server/repair-qualification.md)
updates both Plug.Crypto locks to 2.2.1, diagnoses the WebSocket control-mailbox
race, preserves and explicitly reconciles only each recovery test's owned
simulated execution, and adds real HTTP evidence of the pre-application A11
blocker. Original unresolved database records remain blocked. Read that record
for current commands/results; the following failures describe their earlier
checkpoint and are not current dependency or fixture repair claims.

The continuing full Codex plan also records an unexplained same-port Fake Agent
restart `:eaddrinuse` in a populated aggregate repeat. Later repetitions passed
without changing the database or weakening shutdown assertions, but the original
failure remains unresolved. See the [listener investigation](../codex-app-server/fake-listener-recovery.md).
Selected native protocol scenarios, synthetic backend success, hosted foundation,
full compatibility and production confidentiality remain separate gates.

The earlier Codex source/test checkpoint `d63dcddae49c0c7c7b5565482134d4282275a86c`
has separate [qualification](../codex-app-server/qualification.md). Its local
root tests, driver/consumer, static checks, assets and assembly passed, but repeat
restart failed activation with `unmapped_or_unresolved_tasks`, and its retained
`plug_crypto 2.2.0` failed security audit for CVE-2026-105963. Those historical
failures and fail-closed unresolved records remain evidence. The current repair
record above supersedes the dependency/owned-fixture status; it does not bypass
activation, erase data or establish A11/full compatibility. The latest populated
local aggregate instead fails an unchanged GitHub test's first-page assumption,
while separate recovery and hosted checks pass. No release or deployment is
certified.

## Reliability repair qualification

Date: 2026-10-23. Review baseline: `91567e5116cb10f702a57012485ceed812b87d21`. The application/protocol tree tested locally was committed as `896fc4886f77e731c38077069fb2d4c7feb8a18a`; tests preceded the commits. A subsequent hosted-run portability repair to the scanner is `d32a532b22cda45675456196775a8bf93d226ec9`, with four passing local scanner tests. No application/protocol code changed after those full-suite runs. The documentation commits add this record. All work stayed on `main`, with no new worktree, production migration, historical-data deletion, live credential, sibling-service change or remote GitHub write.

| Finding | Reproduction and resulting behavior | Regression coverage |
| --- | --- | --- |
| GitHub object deletion | Reproduced through the real Client and fake HTTP. An individual-resource 404 permits a minimal tombstone only after fresh installation/token/exact-repository validation. Installation/repository/list 404 and genuine 403 still fence access; 429/transient validation failures remain retryable. Current absence and immutable observations are separate. | `github/deletion_reconciliation_test.exs`: duplicate deletion, another mapped repository under the same installation, revoked access, rate/transient failure and verified reappearance. Initial four cases had three failures before repair. |
| Event-maintenance starvation | Reproduced with 106 older paused deliveries hiding a later active delivery. Bounded selection excludes inactive receive work, retains expired/reconciling cleanup on inactive Projects, and rotates successfully checked wakeups by `updated_at, id`. Domain versions, event identity, retry deadlines and fences remain intact. | `events/delivery_test.exs`: active lost wakeup, retained paused work and resume; retained expiry/ambiguity/stale-lease tests. GitHub maintenance had the same oldest-batch problem and now rotates successfully enqueued syncs; a greater-than-100-row regression proves progress. |
| WebSocket deadlines/accounting | Reproduced: the initial lifecycle suite had nine failures in eleven cases. Server-originated requests now expire, cancel timers, release pending capacity and notify the host once on timeout/disconnect/send failure. Sent mutations retain ambiguous outcomes. Expired request IDs remain bounded completion markers against late-response reuse. Consumed ping/pong bytes no longer accumulate as unread data. | `socket_lifecycle_test.exs`, `client_control_frames_test.exs` and core `client_test.exs`: real loopback timeout/disconnect, callback send-failure cleanup, response/expiry races, late replies, long control traffic, fragments, interleaving and oversize rejection. |
| Schedule command identity | Reproduced false receipt replay across two schedule IDs. Digests now bind the canonical target. Old receipts replay only with stored evidence of the same target and Project; missing/changed evidence conflicts and never reexecutes. Review found and reproduced a nil-target legacy-receipt edge, now rejected. Adjacent commands already bind their target in operation/scope/semantic fields. | `schedules_test.exs`: cross-target, uppercase-equivalent UUID, same-target retry, payload/version change, stale version, inaccessible/missing/nil target and immutable legacy receipt compatibility. |
| Request-rate ownership/race | Reproduced quota loss after the first request exits and over-admission by concurrent callers. A supervised owner serializes admission in private ETS. Enforcement is node-local, counts admitted requests, expires against a monotonic clock, visits at most 500 cleanup keys per tick, and starts with an empty quota after owner/node restart. | `plugs/rate_limit_test.exs`: independent requests, request termination, synchronized 64-caller boundary, expiry, supervised restart and 1,100-key cleanup cursor. ConnCase assigns an independent address per test; requests within one case retain their quota. No production limit was raised or disabled. |
| CI/static/security qualification | Credo, Dialyzer, legacy scan and the four reported Hex advisories reproduced and were repaired. The six-hour Bun stall did not reproduce; its original cause remains unknown. Bun 1.4.4 separately reproduced an asset-wrapper `ERR_INVALID_STATE`; CI is pinned to compatible Bun 1.3.13 with its generated lock format. | Strict checks and package audits pass. Clean frozen installs retain local Phoenix/LiveView/DuskMoon dependencies, package/lock hashes and bounded diagnostics. The installer times out at 240s; the CI step/job also have bounds. |

Maintenance rotation records actual UTC check time rather than the injected eligibility clock, so fixed-clock recovery scans also progress. Both delivery systems retain their bounded batch and ordered transaction rechecks. Notification acceptance does not claim execution ownership or Task acceptance. No reconnect, expiry or maintenance wakeup launches a second execution; status reconciliation and unresolved-effect holds remain required.

The WebSocket client retains its pre-existing conservative aggregate socket-read cap. A coalesced read larger than `max_frame_bytes + 14` can close even if its individual frames are legal. The repair fixes consumed-byte accounting without removing that cap or the per-frame/fragmented-message bounds. README documents this throughput limitation. The send-failure unit fixture simulates the WebSock termination callback; separate real-WebSocket cases cover transport disconnect/timeout.

### Exact local checks

Use `devenv shell --no-tui --` for these commands with Elixir 1.18.5 / OTP 27.3.4.17. PostgreSQL 16.15 used only the existing isolated socket cluster on port 55443, with UTF8 scratch databases. The populated reliability database was preserved across failed, focused and both full runs; no reset, row cleanup or test exclusion was used to obtain the result.

```sh
export MIX_ENV=test PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao
export SAMGITA_TEST_DATABASE=samgita_redesign_reliability_test
export MIX_BUN_PATH=/run/current-system/sw/bin/bun # verified 1.3.13
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test --seed 437312
mix test --seed 437312
SAMGITA_TEST_DATABASE=samgita_redesign_reliability_restart_test mix test \
  apps/samgita_web/test/samgita_web/integration/restart_reconcile_test.exs --include e2e
python3 scripts/verify_isolated_protocol.py
python3 scripts/install_web_dependencies.py --bun "$MIX_BUN_PATH" --isolated
python3 scripts/install_web_dependencies.py --bun "$MIX_BUN_PATH"
mix assets.build
mix dialyzer
mix hex.audit
python3 -B scripts/test_check_legacy_runtime.py
python3 -B scripts/check_legacy_runtime.py
# Also, from each of the three protocol package directories:
mix deps.get
mix compile --warnings-as-errors
mix test
mix format --check-formatted
mix hex.audit
```

| Final local check | Result actually observed |
| --- | --- |
| Retained/redesign suite, twice on populated `samgita_redesign_reliability_test` | Each run: **167 core tests, 110 web cases, zero failures, one excluded dedicated restart case**, seed `437312`. Includes signed GitHub fixture to routed fake Agent, decisions, progress/artifacts and review/acceptance with both `Synapsis` and `Orion`; retained authorization, cancellation, concurrent-update and UI recovery cases run. |
| Dedicated application/fake-host restart and rollback | **1 test passed**, seed `56346`, dedicated `samgita_redesign_reliability_restart_test`. Lost ACK reconciles by original operation/status; no second start; epoch closure rejects stale results and retains unresolved effects. |
| Independent package checks | Core **32**, WebSocket **40**, pinned Codex **13** tests passed; their warnings-as-errors compilation, format and Hex audits passed. |
| Outside-umbrella proof | Script passed: copied core suite, standalone core consumer and direct WebSocket consumer. No Samgita Repo, database or umbrella configuration supplied to consumers. |
| Static and dependency gates | Root warnings-as-errors compilation, full format, strict Credo, Dialyzer, precise legacy scan plus its four tests, and Hex audit all passed. No warning suppression or rule exclusion was added. |
| Final Bun install/build | Bun **1.3.13**, new public-registry lock with current local-package metadata; isolated frozen install **85.57s**, workspace frozen install **4.34s**, asset build passed. Final lock SHA-256: `ec8912e098a5e4f0aa675e51fcfb5a38e5d913905760293ec170c0cd2798e74c`. |
| Local production assembly | `MIX_ENV=prod mix deps.get --only prod`, `mix assets.deploy`, `mix release --overwrite` all passed using `/tmp/samgita-reliability-prod-build`. Archive: `/tmp/samgita-reliability-prod-build/samgita-0.1.0.tar.gz`, SHA-256 `28c55a52add3d2e50797fd7e3006682d6afaebdd21431595b9c3216583ba254a`. No release process was started or deployed. |

For production assembly only, `MIX_BUILD_PATH` pointed to that separate directory; `DATABASE_URL` named the isolated reliability database and `SECRET_KEY_BASE`/`SAMGITA_API_KEYS` were synthetic local-assembly constants. Assets deploy reports the core app has no `priv/static`; the web app's assets and digest succeed. This is an unpublished local 0.1.0 assembly, not a release-readiness override or a service smoke test.

The first full repair run had a genuine 429 failure because unrelated tests shared one IP after rate ownership was fixed. ConnCase now isolates client identity while preserving within-test enforcement. Both populated-database repeats above pass with this correction. Prior GitHub fixture failures were repaired by fair durable selection and bounded assertions of the exact expected wakeup, not sleeps or fresh-database-only qualification.

CI baseline [39838339835](https://github.com/gsmlg-opt/Samgita/actions/runs/39838339835) was cancelled during Bun installation; downstream gates were skipped. Clean baseline installs with Bun 1.3.13 and 1.4.4 both succeeded (about 10s and 13s) with stale local-package metadata warnings. Those observations do not establish the cancellation's cause. Regenerating the lock removes those stale descriptors and private mirror URLs. The final workflow pins Bun 1.3.13, keeps frozen installation, prints provenance and verbose diagnostics, bounds installation/overall runtime, repeats the retained suite on its populated DB, and explicitly overwrites cached local release assembly. It does not publish.

The first repair [hosted run 39899873064](https://github.com/gsmlg-opt/Samgita/actions/runs/39899873064) at `8f101da25dadf4c1bdd2aebb743305d0bd24cd48` passed install, compile, format, Credo, both retained-suite runs, restart, independent consumers/packages and assets. Its legacy scan then failed because the runner has no `rg`; Dialyzer, audit and release assembly were **skipped**, not passed. The new no-ripgrep regression reproduced this failure locally. The scanner now uses Git's tracked/untracked file inventory in the same scope, without new path exclusions; all four scanner tests and the real scan pass. Final hosted status must be checked for the pushed revision rather than inferred from the earlier local matrix. Failure log: `/tmp/samgita-reliability-ci-39899873064-failed.log`; red regression: `/tmp/samgita-legacy-no-rg-red.log`.

Terminal [hosted run 39900481097](https://github.com/gsmlg-opt/Samgita/actions/runs/39900481097) at `dd2a82b483ffb6ce0807c5e01ff20fba32b96e15` **passed every step**, including repeated retained tests, restart, independent consumers/packages, assets, the portable legacy scan, Dialyzer, Hex audit and production release assembly. It supersedes the initial hosted failure; full log is `/tmp/samgita-reliability-final/hosted-ci-39900481097.log`. Subsequent documentation-only commits record that terminal result without changing the verified application, protocol, scanner or workflow tree. This green CI run does not clear A11 or publish/deploy the archive.

Decimal is now **3.2.0**, Bandit **1.13.1**, and test-only lazy_html **0.1.13**, with compatible hpax/thousand_island updates. These clear the audited CVE-2026-97853, CVE-2026-105659/CVE-2026-105660 and CVE-2026-92106 findings. Dialyzer uses one consistent `Mint.HTTP1` lifecycle and includes ExUnit in its test PLT. Credo repairs extract existing validation/transition helpers without changing authority or review policy. The legacy scan allows full-line historical comments and literal negative `refute app in [...]` assertions in test files; runtime integrations still fail, including migrations and manifests.

Local evidence logs are `/tmp/samgita-reliability-final/{results.json,*.log}`, `/tmp/samgita-reliability-{red,focused2,static-final2}.log`, `/tmp/samgita-github-{deletion,maintain}-red.log`, `/tmp/samgita_ws_red.log`, `/tmp/samgita-schedule-legacy-nil-red.log`, `/tmp/samgita-frozen-compatible-{final,workspace}.log` and `/tmp/samgita-bun-1313-regenerated.log`. These are local logs, not published artifacts. Browser screenshots/hashes in the original P5 section below were not rerun in this repair; current automated LiveView cases and the rebuilt assets are the new evidence.

### A11 confidentiality gate remains blocked

The subsequent [repair investigation](../codex-app-server/repair-qualification.md#a11-source-proven-pre-application-blocker)
also exercises real Bandit HTTP/1 requests. Its request-start event exposes
coalesced body bytes through the adapter buffer before any application Plug;
exception metadata retains that original connection. Merely moving this form to
a controller or earlier Plug cannot close the gate. The four passing exposure
tests are not confidentiality acceptance. Source-level pre-emission controls or
a separately reviewed encrypted entry contract remain prerequisites.

`telemetry_confidentiality_test.exs` attaches real raw LiveView `handle_event` start/stop and Repo query handlers, submits a synthetic credential canary, captures debug logs and DOM, and evaluates configured metric projections. Logs, rendered markup and metric projections exclude the canary. The raw LiveView start **and** stop metadata contain the exact plaintext at `metadata.params["credential"]["credential"]` before application handling. The regression intentionally records this exposure; its passing result is not a passing A11 confidentiality gate.

The audit found Phoenix parameter filtering and bounded metric/tag definitions, with no application raw-telemetry exporter or reporter enabled. Repo persists/logs digests rather than the submitted credential; protocol/audit projections remain allowlisted. These application paths do not sanitize the framework's raw event metadata, sockets or arbitrary third-party handlers. In-process raw instrumentation must remain trusted and must not be exported. Aggregate metric allowlists do not prove raw telemetry safe.

Full closure requires verified upstream/source-level redaction or a separately accepted secret-entry flow that avoids those raw parameters, with a canary regression against the resulting metadata and configured exporters. No supported application configuration found in this round provides that source redaction. No external repository/framework was patched, and the acceptance criterion was not weakened. **A11 remains blocked**, even when automated build gates pass.

### Compatibility and rollback boundary

This repair adds no migration and rewrites no command receipt or historical record. Existing schedule receipts require target/scope proof; an ambiguous receipt conflicts rather than reexecutes. Fairness touches operational check timestamps only, preserving event creation time, delivery attempts and version/fence contracts. The rate limiter's ephemeral node-local quota intentionally resets on restart; it provides no cluster-wide guarantee.

Use the existing [closed-admission/epoch/hold rollback procedure](migration-rollback.md). Restoring an earlier binary reintroduces the repaired bugs and must not reopen legacy execution or replay unknown external effects. No production rollback or migration was performed. Real Sigma/Synapsis/Codex service conformance, real GitHub installations, full legacy storage/backup/readers and old-writer exclusion remain owner-controlled gates. No package publication, tag, live integration or deployment occurred. Publication is blocked by A11 and the absence of a normal publication workflow; CI/local archive success alone cannot authorize it.

## Delivered behavior

The dashboard reads PostgreSQL counts and authority. `/agents` and `/agents/:id` manage stable identities, capability approvals, endpoint descriptors, versioned credential references and digest-only inbound credential registration. Connections, generations, sessions and membership remain distinct. Availability uses persisted activity/delivery evidence and connection expiry; every status explicitly leaves health unverified.

`/projects` and `/projects/:id` manage Projects, repository associations, project roles, responsible-Agent routing, Tasks, schedules and manual triggers, and inspect signed-source provenance and delivery history. Lists are bounded and paginated, with shared history offsets labeled. GitHub verification is distinct from an operator-entered URL alias. The first GitHub integration remains read/event-only.

Task UUID routes display Task/Attempt state, progress, children, decisions, artifact references and restricted legacy provenance. Attempt success with resolved effects leaves `awaiting_review`; unresolved effects block the Task and retain a hold. Acceptance requires an approved review of the current Task version and a separate authorized acceptance decision. Review eligibility is queried independently of history pagination. Holds, uncertain notification outcomes, authentication failures, unsupported/unreviewed delivery and retry exhaustion remain visible.

Writes use the existing context commands, optimistic versions and durable command receipts. Ordinary form recovery retains the original unknown command identity and expected version; changed semantics conflict rather than creating another command. New intent IDs follow observed success. Machine credentials are write-only, cleared from the form and intentionally not recovered. Browser access retains the infrastructure boundary, CSRF and secure headers; no account system was added.

Neutral Agent protocol traffic uses authenticated WebSockets at the Agent's `/app-server`; Samgita's management callbacks use the protected operator/machine REST API. No undocumented Task/lease methods were inserted into the neutral schema. A Samgita-hosted management WebSocket profile is not advertised or implemented; REST is the qualified authoritative callback interface. Direct sessions on an independent runtime host do not implicitly update Tasks.

## Original P5 evidence and commands

Use Elixir 1.18.5 / OTP 27 from `devenv shell --no-tui --`, PostgreSQL 16 on socket `/tmp/samgita-p3-pg/socket`, port `55443`, user `gao`. All databases in this phase are explicit local scratch databases. Precreate them from UTF8 `template0` if the cluster's default template uses SQL_ASCII. Never reset an unresolved target.

```sh
export PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao
export MIX_ENV=test SAMGITA_TEST_DATABASE=samgita_redesign_management_qualified_test
mix test apps/samgita/test/samgita/management_test.exs \
  apps/samgita/test/samgita/tasks/progress_test.exs \
  apps/samgita_web/test/samgita_web/live \
  apps/samgita_web/test/samgita_web/integration/agent_journey_test.exs
# Run separately, with a fresh dedicated database:
SAMGITA_TEST_DATABASE=samgita_redesign_restart_verified_test mix test \
  apps/samgita_web/test/samgita_web/integration/restart_reconcile_test.exs --include e2e
python3 scripts/verify_isolated_protocol.py
# Final retained suite, on a fresh dedicated database:
mix test --seed 437312
```

| Check | Evidence |
| --- | --- |
| Persisted UI/context/API journey and retained suite | Final fresh database `samgita_redesign_management_qualified_test`: 158 core tests and 104 web cases, 0 failures, 1 excluded dedicated restart case; seed `437312` |
| Signed-webhook to Task acceptance | Real authenticated fake WebSocket delivery plus protected machine REST callbacks, separately run with names `Synapsis` and `Orion`; duplicated source ID yields one event; decision ACK remains separate from Task creation/execution/acceptance |
| Form recovery | Lost-result form recovery retains command/version; repeat is a receipt replay; altered unknown semantics conflict; stale edits are rejected; navigation/reconnect reads durable state |
| Application/fake-host restart and rollback | 1 test passed, seed `157470`, dedicated `samgita_redesign_restart_final_test`; fsynced test journal, lost ACK then status-only reconnect, no second start, application restart, epoch closure and stale report rejection, retained effect hold and activation refusal |
| Outside-umbrella consumers | Two independently copied consumers build/test/format without the umbrella. Core consumer covers event receive/status/report, retries and unsupported sessions; transport consumer covers thread/turn/steer, streamed replay/reconnect, approval denial and interruption. Final script exit 0, transport-consumer seed `596011`; independent package suites: core 30, WebSocket 24, pinned Codex 13, all passed. |
| Final retained aggregate/release checks | Compile with warnings as errors, full format check, frozen Bun installation, asset build/deploy and local production release assembly passed. Credo, Dialyzer, exact legacy-reference scan and Hex audit failed; details below. No release/tag/publication. |
| Browser/assets | Actual browser at `http://127.0.0.1:3119`, PostgreSQL `samgita_redesign_browser_final_test`, native fake at `ws://127.0.0.1:39483/app-server`. Persisted registration through review/acceptance, rejected transition, cancellation hold, repeat submission, interrupted schedule recovery, refresh/navigation/reconnect, keyboard and 320/375/390/1440px layouts verified. Final console had no warnings/errors; observed page/asset requests succeeded. Served hashes below. |

The test fake's disk journal simulates durable Agent acceptance and an execution-start journal. It fsyncs the file before acknowledgement; it does not fsync the containing directory and proves process/application restart, not power-loss durability. It invokes no shell, model or GitHub write. It is not a deployable Agent implementation or proof of a real service's persistence/idempotency guarantees. The package's original in-memory FakeAgent accurately advertises receipt, not durable storage.

## Original P5 browser reproduction

Create/migrate a fresh isolated `samgita_redesign_*_test` database. Build assets, then explicitly start the test-only driver:

```sh
MIX_ENV=test SAMGITA_TEST_DATABASE=samgita_redesign_browser_test mix ecto.migrate
MIX_ENV=test mix assets.build
MIX_ENV=test PORT=3119 SAMGITA_TEST_DATABASE=samgita_redesign_browser_test \
  SAMGITA_FAKE_JOURNAL=/tmp/samgita-browser-fake.json \
  mix run --no-start scripts/redesign/browser_fixture.exs
```

The driver prints only local endpoint/reference metadata. Provision its synthetic inbound fixture credential from the test source (never a live credential); the driver does not log the value. Use one fresh database/Agent per journey. Register an Agent in the browser with the printed exact endpoint, `browser-service-v1` reference and approved/advertised `project_events.v1`; register its fixture inbound credential. Create a Project, repository association, explicit manager/worker membership and responsible routing. Emit a manual or scheduled fact. In the driver's stdin send `{"action":"work","project_id":"…","agent_id":"…"}`. This explicit test action dispatches through the actual connector and calls the actual machine HTTP API to report its decision, create/delegate/claim/start/progress/artifact/finish a simulated Task. Open the printed Task URL and record review, then acceptance in the UI. A separate `work` action with `leave_running: true` leaves a running simulated Attempt; block/cancel it in the UI to inspect the persistent hold. Reconnect and inspect persistence. `SAMGITA_FAKE_PORT` may pin the local fake port across a driver restart. No LLM decision loop is installed in Samgita.

Final browser records: Agent `e37a4d8a-1869-4e55-a8e1-5984f2150031` (Orion Browser Fake), Project `4a24d96d-1e6a-45d1-b6d9-4320fa84b649`, accepted Task `c5eba1fc-c9b2-4ecc-b6f6-07cc54bf6aa4`, cancelled/held Task `5cc091e5-6b0e-4b9c-8841-49b59a6043de`. The accepted journey used one routed `manual.triggered` event and one delivery, with an explicit processing decision, child Task, Attempt, progress and artifact reference. The signed GitHub journey with both Agent names is the automated integration evidence, not a claim of live GitHub use in the browser. An earlier browser Task created before correcting the route filter is retained but excluded from end-to-end acceptance evidence.

The browser first showed `activity observed`, then `stale` alongside a still-connected connection record and **Health unverified**. The credential field was empty after registration and raw fixture credentials were absent from rendered Agent/Task markup. A running Task rejected direct acceptance; blocking then cancelling retained its unresolved-effects hold through application restart, refresh and reconnect. The interrupted disabled schedule retained the original command ID, expression and IANA timezone; keyboard Enter submitted it twice with one schedule/event. Project/repository field errors remained visible. Disclosure panels stayed open while typing and saving. The mobile header was corrected at the callsite; final 320px/375px checks had document width equal to client width, with all navigation/theme controls accessible.

Served final asset SHA-256 (fetched and hashed in the browser after `mix assets.build`):

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `/assets/js/app.js` | 179683 | `5575e1a4b953889574bcbdefdf11086533e7563f47500e91f8be167fb4d346de` |
| `/assets/css/app.css` | 401174 | `142830752b0ca9f5244ad1e791f2d551a8c30ac999397d61f5b72a00f99986ec` |

Local screenshots: `/tmp/samgita-task-accepted-desktop-final.png`, `/tmp/samgita-task-mobile-final.png`, `/tmp/samgita-agent-mobile-final.png`. They are local evidence, not published artifacts. The dependency's existing disconnected toast remains in the accessibility tree while connected (tracked upstream in `phoenix_duskmoon#162`); it was not represented as Agent health or silently patched.

## Original P5 aggregate gate results

The serialized final run passed compilation with warnings as errors and full format checking. The final full retained/redesign suite passed on fresh `samgita_redesign_management_qualified_test` (158 core tests; 104 web cases with the dedicated restart case excluded; 0 failures; seed `437312`). Frozen Bun installation and final `mix assets.build` passed. Fresh/additive preservation and independent-transaction concurrency tests are included in the core suite. Package and dedicated restart results above remain separate.

A repeated full run on the already populated `samgita_redesign_management_final_test` exposed two existing GitHub reconciliation failures, at `github/reconciliation_test.exs:49,307` (seed `437312`): bounded global maintenance did not select the new fixture's sync among retained committed concurrency fixtures. No rows were deleted, test/gate weakened or GitHub implementation changed. The same full suite/seed passed on fresh `samgita_redesign_management_release_test`, and again after the last layout change on fresh `samgita_redesign_management_qualified_test`. Repeated-run isolation for that inherited suite remains an explicit limitation; use a fresh named database for aggregate qualification.

The unchanged release gates fail and remain blocking:

- `mix credo --strict`: 93 refactoring opportunities, 33 readability issues and 23 design suggestions inherited across prior protocol/domain/GitHub code. Current UI findings are corrected; no rule or exclusion was changed.
- Exact CI legacy-reference scan: negative-isolation assertions naming `:samgita_provider`/`:samgita_memory` and the preservation fixture's `pgvector` comment match the inherited broad scan. The assertions/comment and gate remain intact.
- `mix dialyzer`: nine inherited warnings: two opaque Mint calls in `github/http.ex:59,73`, seven ExUnit callback/proxy warnings in existing ConnCase/DataCase support. No ignore file or warning suppression was added.
- `mix hex.audit`: `decimal 3.1.1` CVE-2026-97853, `bandit 1.12.5` CVE-2026-105659/CVE-2026-105660, and test dependency `lazy_html 0.1.12` CVE-2026-92106. Dependency upgrades are outside this UI scope; these are release blockers.

Local `MIX_ENV=prod mix deps.get --only prod`, `mix assets.deploy` and final `mix release --overwrite` passed with a separate OTP-27 build directory `/tmp/samgita-management-prod-build`. The explicit overwrite rebuilt the local assembly after an earlier noninteractive invocation only reached its overwrite prompt. This assembles an unpublished local 0.1.0 release only. It does not override failing gates or certify a running/deployed release. Logs are under `/tmp/samgita-management-checks`, `/tmp/samgita-management-final-checks`, `/tmp/samgita-management-qualified-tests.log` and `/tmp/samgita-isolated-protocol.log`; no lockfile/dependency change was made.

A11 is partial: tests capture credential-form logs, DOM, receipt/event data and digest-only persistence; browser markup checks also pass. Phoenix's internal raw LiveView telemetry includes event parameters and socket metadata before application handling. No raw telemetry exporter is configured, and the current metrics declare bounded measurement/tag projections, but arbitrary raw-telemetry capture was not certified secret-free. Treat in-process instrumentation as trusted; any exporter must allowlist measurements/tags and exclude params, sockets, request headers and query parameters. The literal raw-telemetry non-disclosure assertion remains open and blocks claiming full A11 acceptance; no framework dependency was patched or suppression added.

## Remaining target gates and publication boundary

Real Sigma and Synapsis endpoints stay in their existing services. Their advertised protocol/authentication/durability contracts require conformance evidence before enablement; see their separate integration guides. Codex supports only the pinned adapter subset, with real compatibility unverified. No sibling repository was changed.

Full legacy storage/readers, dual-Repo/pgvector backup restore, actual old-writer exclusion, external-effect cessation, production key/egress policy and each enabled GitHub/Agent installation remain target-specific cutover gates. The local fixture cannot attest to those targets. See [migration and rollback](migration-rollback.md).

The repository currently has CI release assembly and deliberately disabled CD, with no normal package/tag publication workflow. Push/CI status, local release assembly, package publication and deployed behavior must be reported separately. No failing build may be tagged. No deployment or live credential change is authorized.
