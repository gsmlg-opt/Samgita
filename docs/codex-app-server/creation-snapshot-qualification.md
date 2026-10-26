# Native creation snapshots

Two actual Codex threads retain independently selected local projects, history
modes and creation provenance before any inference. Their first messages then
materialize the expected metadata without changing the collected creation
notices. This closes a scoped evidence gap; no driver defect was demonstrated.
Base: `e9fde80de8226cd74ea12e71867565f5577b0305`.

## Pin and producer

The target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Twelve complete relevant source files match their immutable archive members.
All **770 official JSON exports**, every existing pinned artifact and all prior
executable sources remain unchanged.

`thread_processor.rs:1193–1209` resolves the real local Project; `1488–1530`
reserves its native thread and starts it without a turn. `1578–1588` builds the
snapshot and attaches project/Daybreak metadata; `1652–1664` emits the correlated
response and actual `thread/started`. `6579–6634` supplies model, history mode,
version, originator, path and creation timestamps. The CLI default source is
**vscode** (`app-server/src/main.rs:49–55`), independently of the client name.

Public `project/create` only creates disposable local Codex project records and
notices in this profile. These are not Samgita PostgreSQL Projects. Explicit
`daybreakEnabled:false` is saved metadata; no Daybreak execution or true/null/
omitted behavior is exercised. A fresh rollout path exists as a selection before
its first file is materialized. A pre-message read need not include staged
project membership; two ordinary first messages supply the real persistence
barrier. Cold resume does not emit `thread/started`.

## Actual behavior and exact owners

The new [owning test](../../apps/samgita_codex_driver/test/native_creation_snapshot_notification_test.exs)
uses an owned native Linux musl stdio process, fixed YOLO configuration and the
unchanged assistant `model_fixture.py`. Every app-server frame and history record
comes from Codex. The local Responses peer supplies only the fixed model answer.

Two public project/create requests have distinct prescribed names, roots and
idempotency markers. Both thread starts precede all turns. A selects its real
project and legacy mode; B selects its other project and paginated mode. Both
select mock-model and explicit false Daybreak. Outgoing encoded frames, exact
RPC IDs/parameters and genuinely correlated responses are checked. The provider
journal stays empty through registration and creation inspection; no turn/item
lifecycle appears at that point.

Each actual creation notice has independent assertions, beyond response equality:

| Physical owner | Full ServerNotification pointer below `/definitions/` | Qualified value |
| --- | --- | --- |
| 2385 | `SessionSource/oneOf/0` | Scalar arm with vscode only |
| 2387 | `SessionSource/oneOf/0/enum/1` | vscode, the pinned CLI default |
| 2425 | `Thread/properties/cliVersion` | 0.163.0, tied to the actual pinned executable |
| 2429 | `Thread/properties/daybreakEnabled` | Explicit false on both threads |
| 2439 | `Thread/properties/historyMode` | Independently prescribed legacy/paginated |
| 2440 | `Thread/properties/historyMode/allOf/0` | Actual field traverses its referenced contract |
| 2442 | `Thread/properties/model` | Prescribed mock-model |
| 2445 | `Thread/properties/originator` | Fixed initialized client owned_creation_snapshot |
| 2447 | `Thread/properties/path` | Distinct absolute native paths inside owned CODEX_HOME containing their thread IDs |
| 2448 | `Thread/properties/preview` | Empty creation preview; later exact prescribed marker |
| 2449 | `Thread/properties/projectId` | Each owning actual local project ID |
| 2453 | `Thread/properties/recencyAt` | Positive seconds within host request bounds, equal creation createdAt/updatedAt |
| 2459 | `Thread/properties/source` | Actual vscode |
| 2460 | `Thread/properties/source/allOf/0` | Actual field traverses its referenced scalar contract |

The **received full notification** validates against the experimental/full root,
and codec encode/decode preserves its complete map. Stable output omits the
Daybreak field; permissive extra-field handling there is not used as evidence.
No other SessionSource variant, nullable alternate, whole referenced definition
or sibling export inherits a promotion.

Exactly one marked assistant turn per thread follows. Each real provider request
has the correct native thread/turn metadata, its prescribed input and none of the
other thread's marker. There are exactly two inferences and two completed turns,
with the fixed actual assistant answer. Metadata-only reads retain the selected
project, false Daybreak, mode, model, originator, source and path; preview becomes
the unique user marker. The first legacy thread's exact saved user/assistant
history survives materializing the second. Paginated history hydration is not
claimed. Post-turn comparisons deliberately exclude mutable recency/updatedAt.
The retained creation envelopes/bytes still contain an empty preview.

Capture is bounded to 32 outgoing frames, 4KiB each and 128KiB total; collection
to 256 events, 1MiB and 32 method types, with ordered unique local sequences,
current generation and explicit gap/deadline failures. No mutation is retried.
Config/script bytes and empty project roots remain asserted. Existing owned
process completion barriers reap native/provider owners and Ports; the native
PID disappears. No existing fixture, test, deadline or runtime changes.

## Final permitted checks

The dedicated case initially passes **1/0**, 1.6s. All eleven final commands pass:

| Check | Final result |
| --- | --- |
| Nine reviewed protocol modules | **42/0 twice**, no exclusions |
| Nineteen reviewed ordinary driver modules | **121/0 twice**, seeds 501432/987654; 170.951/168.625s |
| Driver composition per seed | 92 actual-binary cases plus 29 scripted Session fault cases |
| Outside-umbrella native consumer | **1/0** |
| Scoped format/package compile | Pass with warnings as errors |
| Root strict Credo | Pass on **520** sources |
| Python AST/inventory consistency | Eight files parse; inventory passes |
| Executable source guard | **338** stable files; all **337** prior files unchanged |

Exact command arrays/logs: `/tmp/samgita-v358-functional-checks/final/`, generated
by `/tmp/samgita-v358-run.py`. Source/binding programs:
`/tmp/samgita-v358-{source,bind}.py`; binding uses `--verify` after the update.
The source-only selection is `/tmp/samgita-v358-ordinary-functional-gap.md`,
SHA256 `83d325d59f7049ff1d30da712f7695e2680a05eeda3dda3fc2fb335858304593`.
Independent source/test review found no blocker; its report SHA256 is
`3b1d5c3e1e47045050c2f7916a4de34fb5d12a624f03ad25b0dfb61da3f6b54e`.
Strict completeness separately exits **1**; it remains a failed gate.

| Artifact | SHA256 |
| --- | --- |
| Source evidence | `59a21e265e40fd38f5cd8c3fc4597b7f339394478bbe4d4e2c22211876e740d0` |
| Final results.json | `49652ecd635a81a6198be18ff84652864ead93805672a4c01591904a37502f8f` |
| Final source.json | `25880b88af34942728732655856898fc64af41a1bc4bea65dc110d673843383f` |

## Rollback and remaining gates

Rollback removes only this additional test/evidence mapping. No application state,
schema, migration or historical-data change occurs. Session, cleanup, providers
and protocol input supplements remain unchanged; rollback never redispatches work.

Only the fourteen exact owners gain scoped implemented evidence. Contracts become
**5,033 implemented /1,522 missing /66 blocked**; requirements remain **462
implemented /12 missing /11 blocked**, **zero verified**. No whole method/family,
other source/Daybreak variant, cold-resume notification, other OS/transport or
external/provider/platform success is inferred. Full compatibility stays incomplete.

Security/credential/authentication/authorization/permission/approval tests, audits,
mixed broad suites and hosted workflows remain unrun/incomplete under the user's
restriction. A11, producerless legacy paths and external/OS/platform/final aggregate
gates stay open. No tag, publication, deployment or live-credential change occurs.
