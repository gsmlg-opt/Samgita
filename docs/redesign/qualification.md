# Management and local redesign qualification

Date: 2026-10-23. Scope: persisted management UI, complete fake-Agent journey, local restart/rollback and final aggregate checks. This record extends [acceptance](acceptance.md); it does not certify a production cutover, published package or real provider integration.

## Delivered behavior

The dashboard reads PostgreSQL counts and authority. `/agents` and `/agents/:id` manage stable identities, capability approvals, endpoint descriptors, versioned credential references and digest-only inbound credential registration. Connections, generations, sessions and membership remain distinct. Availability uses persisted activity/delivery evidence and connection expiry; every status explicitly leaves health unverified.

`/projects` and `/projects/:id` manage Projects, repository associations, project roles, responsible-Agent routing, Tasks, schedules and manual triggers, and inspect signed-source provenance and delivery history. Lists are bounded and paginated, with shared history offsets labeled. GitHub verification is distinct from an operator-entered URL alias. The first GitHub integration remains read/event-only.

Task UUID routes display Task/Attempt state, progress, children, decisions, artifact references and restricted legacy provenance. Attempt success with resolved effects leaves `awaiting_review`; unresolved effects block the Task and retain a hold. Acceptance requires an approved review of the current Task version and a separate authorized acceptance decision. Review eligibility is queried independently of history pagination. Holds, uncertain notification outcomes, authentication failures, unsupported/unreviewed delivery and retry exhaustion remain visible.

Writes use the existing context commands, optimistic versions and durable command receipts. Ordinary form recovery retains the original unknown command identity and expected version; changed semantics conflict rather than creating another command. New intent IDs follow observed success. Machine credentials are write-only, cleared from the form and intentionally not recovered. Browser access retains the infrastructure boundary, CSRF and secure headers; no account system was added.

Neutral Agent protocol traffic uses authenticated WebSockets at the Agent's `/app-server`; Samgita's management callbacks use the protected operator/machine REST API. No undocumented Task/lease methods were inserted into the neutral schema. A Samgita-hosted management WebSocket profile is not advertised or implemented; REST is the qualified authoritative callback interface. Direct sessions on an independent runtime host do not implicitly update Tasks.

## Evidence and commands

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

## Browser reproduction

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

## Required aggregate gate results

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
