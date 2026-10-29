# Ordinary Codex functional delivery

## Amended milestone and exact profile

The user's 2026-10-30 `prompt.md` explicitly authorizes this ordinary milestone
to finish independently of the original complete compatibility goal. Its input
SHA256 is `1a79283d742ec3ccf4b92726140b44000e9bd4486fb5d8b77169bccef2c83f4c`.
The input remains an untracked user file; this document records its durable
completion contract. Starting revision on `main` was
`b9ab42ecb10d5c9c5357b8beb3fc3cb4ee1008c5`; no reset, branch or worktree is used.
The executable implementation is committed as
`025f4a8e431a7e752fb710cb1c9ae724db4799c2`. The subsequent qualification commit
changes documentation only; both carry `[skip ci]`.

Deliver an independently runnable consumer with A–E below, repair concrete
in-scope defects, pass reviewed functional checks and inventory consistency,
commit and push with prohibited automatic CI suppressed, then stop. The
[original goal](goal.md), full implementation ledger, native surface and strict
completeness gate remain intact and incomplete. Passing this milestone grants
no full-compatibility, publication or platform-readiness claim.

| Immutable input | Identity |
| --- | --- |
| Official version / source | `rust-v0.163.0` / `83086188ae0614bd882818ff1aa23f3194962012` |
| Combined Linux musl binary SHA256 | `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215` |
| Official source archive SHA256 | `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567` |
| Schema/binary provenance | `apps/samgita_protocol_codex/priv/upstream/0.163.0/provenance.json`, unchanged |

The profile is Linux x86_64 musl, Elixir 1.18.5 / OTP 27, Python 3.11+, an
explicitly owned disposable Codex process, fresh HOME/CODEX_HOME/workspace and
loopback deterministic Responses model providers. Fixed YOLO launch settings
are `approval_policy="never"` and `sandbox_mode="danger-full-access"`. They are
qualification inputs, with no permission-policy assertions or deployment changes.
No paid inference, real credentials or production task is involved.

## Implementation and evidence map

The [consumer](../../apps/samgita_codex_driver/examples/consumer/README.md) reuses
the existing Session, native schema, interaction and Stdio ownership APIs.
`Workflows.run/4` returns full operation envelopes, ordered native event maps,
opaque interaction handles, provider inputs, history and connection metadata.
`run.exs` is its executable entry point. Codec representation, controlled faults
and actual native behavior are separate evidence layers; no manifest entry is
promoted by this companion table.

Paths in the table are relative to `apps/samgita_codex_driver`; requirement IDs
were checked against the current manifest's `entries`.

| Workflow | Implementation / existing requirement IDs | Behavioral evidence and limits |
| --- | --- | --- |
| A. Thread and streamed text | Consumer `Workflows.completed/3`; `lifecycle:initialization-order`, `lifecycle:item-lifecycle`, `lifecycle:bidirectional-correlation` | New `examples/consumer/test/ordinary_workflows_test.exs` runs actual pinned Codex. Correlates create/submit IDs, reconstructs message deltas, observes the completed terminal event and matches original thread/turn/item IDs and full item maps in persisted history. A request response is not completion. Text is deterministic model-fixture output, not external inference evidence. |
| B. Pure dynamic tool | Same consumer flow; `lifecycle:server-request-resolution`, `lifecycle:item-lifecycle` | Actual `item/tool/call` from Codex carries native call/thread/turn IDs and a generation-bound handle. Explicit lookup response produces a completed dynamic item and a provider continuation containing the same function call/output. Local send remains distinct from remote processing; subsequent native item/history evidence supplies completion. No approval or credential flow is exercised. Existing `test/native_active_injected_history_lifecycle_test.exs` also covers this ordinary path. |
| C. Observable interruption | `Workflows.interrupted/3`; `lifecycle:turn-interrupt` | A fresh actual process/provider holds at a genuine unanswered tool callback. Exact-turn interrupt returns an ACK; the consumer separately awaits interrupted `turn/completed` and reads its interrupted history. No tool response or continuation is submitted. This proves interruption of a pure callback wait, not command/subprocess termination. No assumed ACK/notification arrival order, sleep or timing-selected retry is used. |
| D. Truthful recovery | `Workflows.completed/3`; `lifecycle:disconnect-reconnect`, `lifecycle:deadline-uncertainty`, `lifecycle:bounded-buffering` | Actual owned stdio replacement explicitly reconnects/initializes, reads/resumes/reads the original thread and preserves its history, connection instance and gap. Provider requests remain exactly two; no new turn is sent. Existing `test/native_ordinary_websocket_gap_test.exs` covers real WS/UDS and controlled loss of one actual native response. `test/query_uncertainty_test.exs` adds 29 reviewed scripted fault cases to the runner: lost reads settle without execution uncertainty; mutations retain uncertainty and are never resent. These injected boundaries are not represented as native race reproduction. |
| E. Ownership and independence | Consumer `with_session/3`, `ProviderFixture.with/3`, `verify_consumer.py`; `lifecycle:owned-process-exit`, `lifecycle:stdio-framing` | Normal consumer flows verify Session DOWN, closed provider Ports and absent native PIDs. An initialization-error regression uses a clearly labeled scripted peer while its caller stays alive, preventing owner death from concealing a leak. Existing four `test/stdio_owner_lifecycle_test.exs` cases cover cleanup phases; native gap tests prove borrowed Session closure leaves the owning listener/process alive. Outside-umbrella verification copies only three reusable packages plus two explicit provider scripts; no Repo/Phoenix/platform config is available. |

The streaming companion `scripts/codex/ordinary_consumer_provider.py` subclasses
the existing provider. Its message-added / text-delta / message-done sequence
matches the pinned `core/tests/common/responses.rs` helpers. The shared
`model_fixture.py` remains byte-identical, preserving its existing test source
pins. Neither script emulates app-server. The independent verifier copies both
scripts together; the example has no dependency on root test-support modules.

The example bounds event collection by a five-second absolute deadline, 256
messages and 1 MiB of wire data. It uses owner notifications and pull draining;
no sleep or retry is used to obtain a terminal result. Reconnect never replays
requests, clears a gap or creates a replacement turn. Existing uncertainty tests
retain stable operation IDs, explicit evidence-based reconciliation and the
distinction between application knowledge and absent upstream idempotency.

## Concrete repair and focused verification

The original example's `with` returned an initialization error without closing
its newly created Session. The regression keeps the caller alive after return
and checks its scripted peer's OS PID before caller teardown. Pre-fix focused
execution fails **1 test /1 failure** with “start returned its initialization
error before closing its owned peer”; log:
`/tmp/samgita-ordinary-delivery-cleanup-red-20261030.log`.

`StandaloneCodex.start/5` now closes the owned Session synchronously before
returning an initialization error, and surfaces cleanup failure explicitly.
Optional capabilities retain `start/4`; `initialize/2` supports explicit
reconnection. Workflows close each successfully started Session in `after` and
providers use the existing Stdio owner cleanup in `after`. Existing shared
process cleanup and malformed request-option repairs remain unchanged.

The first integrated workflow test fails on a new test oracle that compared
notification envelopes to an exact map lacking native `completedAtMs`. The
corrected assertion still requires one original item ID, exact complete item
map, matching thread/turn and an integer native completion timestamp. It drops
no lifecycle assertion. The original failure log is retained at
`/tmp/samgita-ordinary-delivery-consumer-functional-20261030.log`.

Focused cleanup/workflow checks then pass **2/0**, and reviewed query-uncertainty
checks pass **29/0** at seed 501432. The final companion-based outside consumer
passes **3/0**, warnings-as-errors compilation, formatting and `mix run run.exs`;
log `/tmp/samgita-ordinary-delivery-outside-companion-20261030.log`.
This focused proof precedes the final combined run below.

An additional Credo invocation with multiple positional paths exits 1 because
its CLI rebases paths against the first directory, yielding a nonexistent path.
The corrected `mix credo --strict --files-included
'apps/samgita_codex_driver/examples/consumer/**/*.{ex,exs}'` exits zero with no
issues; no source change is needed. Both original logs remain under
`/tmp/samgita-ordinary-delivery-scoped-credo-20261030.log` and
`/tmp/samgita-ordinary-delivery-scoped-credo-corrected-20261030.log`.

## Final-source commands and results

Run from the repository root:

```sh
python3 -B scripts/codex/check_ordinary.py --list
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- \
  python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-delivery-combined-20261030
python3 -B scripts/codex/inventory.py --check --require-verified
```

The reviewed selection preserves every previous main/extension argument,
assertion and deadline. It adds the separate 29-case query-uncertainty step
(30-second bound), checks that file's format, and changes the independent
consumer's expected count from one to three. Existing main 166-case /320-second
and extension 26-case /120-second bounds remain unchanged. No restricted test
is added. Full security/credential/authentication/authorization/approval/
sandbox-policy/permission tests, audits, mixed broad suites and hosted workflows
remain unrun and incomplete; tests and gates are preserved.

All **18/18** steps pass against **1,770 identical before/after/current guarded
hashes**, fingerprint
`820cc7f9dabd4079b3ef2aeda19c42f4585e55678bd48b251cfc9ecb43368393`.
The final binding checks every command, count and log SHA256, the original
bounds, the executable pin and the unchanged user inputs. Of 1,763 previous
guarded sources, 1,760 remain exact; only the consumer launcher, ordinary runner
and outside-consumer verifier change, with seven new sources. The shared
fixture, existing consumer test, driver Session and entire manifest remain exact.

| Final check | Observed result |
| --- | --- |
| Main selection, seeds 501432 /987654 | 166/0 each; total step time 291.323s /287.970s, original 320s bounds |
| Extensions, same seeds | 26/0 each; 40.185s /40.238s, original 120s bounds; 23 native plus 3 scripted cases |
| Selected WS overflow/replay, seeds 455834 /501432 /987654 | Each reports 16 tests, 0 failures, 13 excluded; original selection retained |
| Retained stdio cleanup phases | 4/0 |
| Controlled query/mutation uncertainty | 29/0; 4.964s, 30s bound |
| Outside-umbrella consumer | 3/0, warnings-as-errors compilation, formatting and executable example; 13.832s total |
| Inventory consistency | Exit 0 |
| Driver/root compile and format, strict Credo, Dialyzer, assets build | All exit 0 |
| Separate unchanged strict full gate | Exit **1**: “Full-compatibility gate failed: unverified requirements remain in entries” |

The strict failure is genuine incomplete evidence, not a metadata, source-pin or
inventory-consistency error. It does not fail the amended ordinary milestone.
No security/permission-related test or audit, mixed broad suite, hosted check,
external-service profile or other-OS profile runs. No production release assembly,
publication or deployment is attempted for this example-only milestone.

| Evidence artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-ordinary-delivery-combined-20261030/results.json` | `655fe884ef5d711b6813d07fa7a3d8ba0b24ce6fb5785a308378b29c73af49e9` |
| Same directory, `source.json` | `ca8484a1c646c3ea3155a2d2e384fa3523e7829a1b492a3374dfc789fe8afe7f` |
| `/tmp/samgita-ordinary-delivery-final-binding-20261030.json` | `cd7b0c63e6985ca13063728b8725af7e16acddad9f6ee73e1ecc7d970e460c66` |
| `/tmp/samgita-ordinary-delivery-plan-binding-20261030.json` | `653d6ae287c33aa3bcc583afaf582c27ebc4719362eea61e41ca4768cb1a020a` |
| `/tmp/samgita-ordinary-delivery-full-completeness-20261030.log` | `8c14de37787f2fa05e8a25dbe96cc1932f9d716f451c257ce98ba73ecbeea0cd` |
| Preserved cleanup regression red log | `6f3f14e69ea4a8bb7cfaa153d58973b5278cad8d1a21527300e30bfe0477cd0d` |

The report stores individual step log hashes and command-plan hash
`6a709593581374f097c8cb49a69c834d6fd14480f1b45ec6544272490b978446`.
Evidence is local, reproducible through the committed scripts and distinct from
hosted or external acceptance. Documentation-only completion does not change
any guarded executable source or require another broad run.

## Remaining full-goal blockers and reopening conditions

| Boundary | Truthful disposition / concrete reopening condition |
| --- | --- |
| Fixed queue-start constructor and serializers | [Pinned source evidence](pinned-output-blockers.md) proves specific declared alternatives cannot be emitted there. Client representation/codec handling remains separate. Reopen native acceptance only with a genuine emitter or an explicitly changed upstream/evidence target; no mock substitutes for emission. |
| Selective-history command source `agent` | [Producer prerequisite](ordinary-command-shutdown-prerequisites.md) remains unestablished, not globally unreachable. Reopen with a permitted actual completed `agent` producer plus original-ID cold history; `unifiedExecStartup`, aliases or injected items do not qualify. |
| Shutdown selective history | Shutdown is possible, but the public wait-subscription readiness barrier remains unresolved. Reopen with a supported causal observation proving subscription before close; ItemStarted, sleeps, retries and private hooks do not establish it. |
| Reverse `created_at` pagination | Retain the [upstream precision defect](ordinary-reverse-timestamp-qualification.md). Reopen with the required upstream correction/changed authorized target and the original assertions; never rewrite native cursors. |
| Other missing native branches / prediction | Original inventory and source limitations remain authoritative; schema forwarding, identical codec shapes and method-not-found evidence do not prove a native producer. Reopen only with a concrete genuine fixture/source prerequisite and an authorized verification profile. |
| Prohibited and unavailable checks | Current user restriction leaves security/permission-related verification and mixed/hosted checks incomplete. Real external-service/backend and other-OS success profiles require their actual environment and separate authorization. |
| A11 and platform readiness | Raw framework telemetry exposure remains blocked as recorded in [repair qualification](repair-qualification.md). No real secrets enter this path; no security tests are run here. Platform readiness requires that independent repair and its applicable gates. |

Requirements remain **462 implemented /12 missing /11 blocked**; schema contracts
remain **5,756 implemented /729 missing /136 blocked** out of 6,621; zero are
globally verified. The manifest is unchanged. This document grants ordinary
workflow evidence only, without reclassifying those entries or weakening
`inventory.py --check --require-verified`.

## Delivery and stopping boundary

Ordinary A–E workflows and applicable checks: **complete**. Original full
compatibility: **incomplete**. Publication: **not performed**. Platform production
readiness: **incomplete**. No service deployment, tag, release, production
migration, live credential change or external-repository edit occurs.

Delivery uses the current `main` branch, explicit scoped staging and a
Conventional Commit with `[skip ci]`. `.github/workflows/ci.yml` would otherwise
run prohibited mixed tests/audits on push; `cd.yml` and `codex-conformance.yml`
are manual. Do not alter workflow definitions or dispatch them. Verify remote
SHA convergence and absence of hosted runs for the pushed revision. The exact
commit/push result is reported with delivery. After A–E, applicable checks and
push pass, stop this milestone; do not restart deferred producer searches.
