# Repair evidence and continuing compatibility work

This record executes `samgita-codex-repair-followup.txt` on the existing `main`,
starting from `3c54d748871313bd69858ff05d0fd2c606019e6a`. It supplements the
[compatibility ledger](implementation-plan.md) and [qualification](qualification.md).
Local checks, hosted checks, full compatibility and confidentiality acceptance
remain separate gates. No production data, credentials or services are changed.

## Integrated rich catalogs and custom instruction precedence

Reviewed implementation units are `4895586` (queued approval expiry), `aa5f9be`
(MCP resources/catalogs) and `611088c` (custom-base precedence). Scoped checks
ran their combined working tree before these commits; their source hashes are
retained in the reports. Explicit manifest binding follows those checks. The
complete committed-source local/hosted matrices remain the next required gate.

The [rich MCP catalog profile](mcp-catalog-qualification.md) and
[default/personality differential](default-gates-qualification.md#custom-base-instructions-override-personality-stripping)
pass the entire six-file block **37/0 at both seeds**, no exclusions. All eleven
scoped commands pass, including compile/format, strict Credo (448 source files),
namespace/sandbox preflights, 38 tooling regressions and inventory consistency.
The 1,507-file and immutable executable guards match. Logs/commands are
`/tmp/samgita-native-continuation-v58-20261025/`; terminal report SHA256
`58108203bdffacfc5e6e8ef57238ab6b6857cfa0217ad9c789354e8c3e60d042`.

The default candidate's first complete run fails 21/21 during setup because its
temporary Unix Socket address is 108 bytes; the exact length diagnostic and all
failures remain. Only shortening its owned TMPDIR to a 98-byte address repairs
the harness. The unchanged full candidate passes 21/0 at each seed. There is no
case exclusion, assertion/deadline change, product fix or database reset.

Fourteen exact catalog owners gain scoped implemented evidence, retaining seven
unobserved auth/runtime/null owners and all SDK-unreachable domains. Contracts
are **4,463 implemented / 2,099 missing / 59 blocked**; requirements remain
**462 implemented / 12 missing / 11 blocked**, zero verified. The new profile
has a required explicit hosted step. Final-source local/pushed hosted matrices,
remaining behavior, A11 and real external/backend/OS acceptance remain required;
no release or deployment follows from these scoped passes.

## Integrated resource normalization and queued approval expiry

The native [resource continuation](mcp-direct-qualification.md#mixed-resource-normalization-and-explicit-error-recovery)
and [post-ticket expiry case](native-authority-qualification.md#queued-response-expires-after-ticket-commit)
pass all **13 scoped commands** in verified test Devenv. Four complete MCP/Apps
files pass **15/0 twice**; the dedicated authority profile passes **4/0 twice**.
Compile, format, strict Credo (447 source files), namespace/sandbox preflights,
38 tooling regressions and 1,505-file/executable guards match. No existing
assertion, timeout, cleanup, database record or authority guard is weakened.

Commands/logs: `/tmp/samgita-native-continuation-v52-20261025/`. Terminal report
SHA256 `f1aeed3fdffbb777dc139faa41c5ecb835a44137cf01e52f28ac5a92a3d92c1e`.
Four physical present-value resource properties gain scoped implemented evidence:
**4,449 implemented / 2,113 missing / 59 blocked contracts**, zero verified;
requirements remain **462 implemented / 12 missing / 11 blocked**.
Temporary launcher/journal failures and the unrelated unqualified dev formatter
failure remain recorded in the owning resource/authority explanations. Complete
new final-source matrices, remaining behavior, A11 and external/OS success remain
required; no full-compatibility, release or deployment claim follows.

## Terminal frozen v49 local matrix

Frozen `4eed41fade9747d7b6151c8b5523f245181516e3` completes all **19 platform +
23 package commands**, then the required completeness check. Both independent
**1,505-file source guards match**. The combined command exits **1**, retaining
both populated aggregate failures and incomplete evidence.

```sh
ERL_FLAGS='+S 4:4' devenv shell --no-tui -- python3 -B /tmp/samgita-repair-final-combined-v49-20261025.py
python3 -B /tmp/samgita-collect-v49-20261025.py
```

| Local check | Terminal result |
| --- | --- |
| Complete driver, seeds 501432 / 987654 | **743/0 each**, no exclusions |
| All 51 isolated native profiles, both seeds | **302/0 each**, no exclusions |
| Native and neutral outside consumers | **1/0** native; **32/0 + 1/0 + 1/0** neutral |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0 each**, including overflow/replay |
| Native wire | **42/0** |
| Both populated umbrella repeats | **230 core/0/1 excluded; 131 web/1 failure/8 excluded** |
| Platform/API/races/native | **59 core + 11 web/0** |
| Dedicated native authority, both seeds | **3/0 each** |
| Populated recovery/restart, both seeds | **4 core + 1 web/0 each** |
| Compile, formatting, strict Credo (447 source files), forced Dialyzer, legacy checks | Passed |
| Root and all relevant independent-lock audits | Passed without exceptions |
| Frozen assets and local production assembly | Passed; never started or published |
| Complete compatibility evidence | Failed; zero verified entries/contracts |

Both aggregate failures are the retained `github_controller_test.exs:56`
first-page assumption: the newly registered connection need not appear on the
UUID-sorted first page among preserved rows. No unrelated GitHub code/test,
records, activation guard or exclusion changed. Separate recovery and fresh
hosted success do not repair this local aggregate failure.

Exact commands/logs remain under
`/tmp/samgita-repair-final-{combined,platform,packages}-v49-20261025/`.
Terminal report `/tmp/samgita-repair-final-v49-terminal-20261025.json`, SHA256
`07ae5bdcce1f2b0e7d613e2fb01917b64ad3f66dee08235986998f024f2c074c`.
The unpublished local archive is 25,748,643 bytes, SHA256
`42b4fcb2f92d95398cc3e72afa95b190d94ee28e72c75bc3c7f46535a496c4a6`.
The collector writes a new v49 report; the historical v38 report is unchanged.
Later candidates require their own integrated checks and new final-source
matrices. A11, source-unreachable emitters and real external/backend/OS success
remain incomplete. No tag, publication, production migration or deployment.

## Hosted v49 checkpoint at 4eed41f

Exact pushed source `4eed41fade9747d7b6151c8b5523f245181516e3` completes
[Foundation 40171789496](https://github.com/gsmlg-opt/Samgita/actions/runs/40171789496)
successfully. Both hosted populated-database repeats pass **230 core + 131 web**,
with the existing **1 core / 8 web exclusions** retained. The complete
[conformance workflow 40171853544](https://github.com/gsmlg-opt/Samgita/actions/runs/40171853544)
fails its required evidence gate while both execution jobs succeed:

| Required execution job | Terminal result |
| --- | --- |
| Selected actual-binary/platform | Wire **42/0**; all four complete driver partitions **206 + 169 + 203 + 165 = 743/0** at the original deadlines; outside native consumer **1/0**; platform **59 core + 11 web/0**; authority **3/0 twice** |
| All 51 isolated native profiles | **302/0**, zero exclusions; every required explicit step succeeds, including successful resource origins and explicit target/null scoping |
| Full compatibility evidence | **Failure**; required entries and variants remain incomplete, with zero fully verified |

The driver suite includes scripted lifecycle tests as well as actual-binary
scenarios. Stock Codex with synthetic model/MCP/backend dependencies does not
qualify real external credentials, every backend or OS profile. Neither this
workflow nor foundation CI publishes or deploys anything.

Terminal metadata: `/tmp/samgita-v49-hosted-terminal-20261025.json`, SHA256
`39ac4cd8534f04715091bf2749e31c19b6807c7f560edb2c2a722be264f36322`.
Per-job steps, actual counts and log hashes:
`/tmp/samgita-v49-hosted-logs-20261025/report.json`, SHA256
`896421fe3d44a9240576027c7c11a093bb96d4ee545a7696493758841e552375`.
Contracts remain **4,445 implemented / 2,117 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
A11, source-unreachable emitters, full field/lifecycle evidence and required
real external/backend/OS success remain incomplete. No tag, publication,
production migration or deployment. Later candidate sources receive no
qualification from these earlier jobs.

## Hosted v38 checkpoint at 10c5318

Exact pushed source `10c53185cd82c0c66261d79821eac85578616b30` completes
[Foundation 40164534477](https://github.com/gsmlg-opt/Samgita/actions/runs/40164534477)
successfully. Both hosted aggregate repeats pass **230 core + 131 web**, with
their existing **1 core / 8 web exclusions** retained. The complete
[conformance workflow 40164574042](https://github.com/gsmlg-opt/Samgita/actions/runs/40164574042)
fails its required evidence gate while both native execution jobs succeed:

| Required execution job | Terminal result |
| --- | --- |
| Selected actual-binary/platform | Wire **42/0**; four complete driver partitions **193 + 216 + 180 + 149 = 738/0**, all at their original eight-minute deadlines; outside native consumer **1/0**; platform **59 core + 11 web/0**; authority **3/0 twice** |
| All 49 isolated native profiles | **300/0**, zero exclusions; each required explicit step succeeds |
| Full compatibility evidence | **Failure**; 485 requirements and 6,621 contracts remain mandatory, with zero fully verified |

The four-way split now has terminal hosted evidence. It does not erase the v36
timeout or stand in for completeness. The local frozen v38 matrix below is also
terminal; hosted fresh-database success does not close its first populated
GitHub pagination failure. Subsequent candidates were held outside the
repository until both local source guards completed. They receive no acceptance
from these earlier jobs.

Terminal metadata: `/tmp/samgita-v38-hosted-terminal-20261025.json`, SHA256
`4b89e11d03984b28064705b843e138d5d3e7a63334a8c16514dd8baf8fb9a87e`.
Per-job steps, counts and log hashes:
`/tmp/samgita-v38-hosted-logs-20261025/report.json`, SHA256
`aa7e546fc93da12cafd86045285f51013931c3b0e263756dbb96121bb0923035`.
Contracts remain **4,383 implemented / 2,179 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
A11, source-unreachable emitters and required real external/backend/OS success
remain incomplete. No tag, publication, production migration or deployment.

## Terminal frozen v38 local matrix

All **19 platform + 23 independent-package commands** finish against unchanged
`10c5318` source. Both 1,495-file source guards match. Complete driver repeats
pass **738/0 twice**, and all 49 isolated native profiles pass **300/0 twice**,
with zero exclusions. The independent native consumer passes **1/0**; neutral
outside consumers pass **32/0 + 1/0 + 1/0**. WebSocket passes **42/0** at seeds
455834, 501432 and 987654; native wire passes **42/0**. All retained package
audits pass without advisory suppression.

The first populated umbrella run retains
`github_controller_test.exs:56`'s first-page assertion: **230 core/0 + 131 web/1**,
with the existing 1/8 exclusions. The second run passes **230/0 + 131/0** with
those same exclusions. No pagination code, fixture data or assertion changed.
The combined matrix remains **failed**, independently of completeness exit 1.

Native platform passes **59 core + 11 web/0**; independent-transaction authority
passes **3/0 twice**. Populated recovery/restart passes **4/0 + 1/0 twice** without
clearing the retained isolated database. Legacy isolation, warning-free compile,
format, strict Credo, Dialyzer, audits, assets and production assembly pass.
Local assembly is not package publication, production migration or deployment.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-repair-final-combined-v38-20261025.py
python3 -B /tmp/samgita-collect-v38-20261025.py
```

The collector preserves command exits, counts, log hashes and failed
completeness. Terminal report:
`/tmp/samgita-repair-final-v38-terminal-20261025.json`, SHA256
`4d9a741863d5cc0cf667334f1026aadab667debe5952f8ce0468c39ba56b1009`.
New executable changes require their own complete final-source qualification.
The full goal, A11, unavailable native emitters and external/backend/OS success
remain incomplete; no required gate is waived.

## Required upstream output blockers

The [source-bound audit](pinned-output-blockers.md) classifies 57 queue-start
result leaves and two omitted null arms as blocked, with immutable source
excerpts and exact original rows/nodes. All requirements remain mandatory;
scripted peers cannot qualify nonexistent native emission. Five inProgress
history leaves remain missing because exhaustive producer closure is unproven.
Contracts are **4,383 implemented / 2,179 missing / 59 blocked**, zero verified;
requirements remain 462 implemented/12 missing/11 blocked. Complete-evidence,
A11, legacy/external/OS and the full goal remain incomplete. Final-source
matrices and hosted qualification are next; no publication or deployment.

## Native reviewer/MCP/async continuation

The [complete eight-file block](native-reviewer-mcp-async-qualification.md)
passes **40/0 twice**, strict checks, 38 tooling regressions and matching
1,495-file/binary guards. The preserved first run has three legacy-history
fixture errors; only new async cases opt into paginated history. A subsequent
Credo failure is repaired without exceptions or assertion changes. Forty-six
exact physical owners bring contracts to **4,383 implemented / 2,238 missing**,
zero verified. Requirements stay 462 implemented/12 missing/11 blocked.
Complete final-source matrices and pushed hosted checks remain required; the
scoped passes do not erase v36 failures or close A11/legacy/external/OS/full-goal
gates. No release or deployment.

## Frozen v36 failures and scoped cleanup repair

Exact baseline `9b5298290c5b8724a2ddc9158786d80aec85e80d` ran all **19 platform
commands**, but only **8/23 package commands** before its second full-driver
run failed in scripted Session cleanup. First driver: **728/0**; second:
**728/1**, `GenServer.stop/3` `noproc` in `SessionToolRetirementTest`'s
`on_exit`. The remaining **15 package commands are unrun**, not passes.
Both 1,495-file source guards match. Combined and complete-evidence commands
exit **1**. The partial report is
`/tmp/samgita-repair-final-v36-partial-terminal-20261025.json`, SHA256
`52a93582633b5deccc321089e2165997716dc0e22b9d5dabd6820a6a24860eb8`.

Platform/API/native: **59 core + 11 web/0**; authority **3/0 twice**;
populated recovery/restart **4 core + 1 web/0 twice**. Compile, format, strict
Credo, forced Dialyzer, audit, assets and production assembly pass. The first
populated aggregate retains `github_controller_test.exs:56`'s first-page
assertion failure; the second passes. Existing records, intentional unresolved
work and activation guards are preserved; unrelated GitHub code stays untouched.

On the same pushed baseline,
[Foundation 40161524332](https://github.com/gsmlg-opt/Samgita/actions/runs/40161524332)
succeeds. [Conformance 40161568088](https://github.com/gsmlg-opt/Samgita/actions/runs/40161568088)
fails: selected job
[121074052197](https://github.com/gsmlg-opt/Samgita/actions/runs/40161568088/job/121074052197)
reaches its **eight-minute timeout** after partition 1 prints **370/0**.
Partition 2, platform and outside-native-consumer steps do not run and receive
no acceptance. All **49 isolated profiles / 297 tests / 0 failures / 0 exclusions**
pass in their separate job; the complete-evidence job fails independently.
Terminal metadata, step status and log hashes are in
`/tmp/samgita-v36-hosted-terminal-report-20261025.json`, SHA256
`d44275a7088943dac24dd8482a7b90501a37ee5141828a61cb49c7e4a7dda25f`.

The [cleanup/partition repair](scripted-cleanup-qualification.md) records the
deterministic race reproduction, supervised-fixture change and **44/0 twice**
focused results. CI uses four complete required partitions at the original
deadlines. These scoped passes do not replace the failed v36 matrix or establish
final-source hosted success. Continue the full compatibility plan and rerun all
required final checks. A11, legacy/external/OS acceptance and full compatibility
remain incomplete; no tag, publication or deployment.

## Terminal frozen v27 local and hosted matrices

Frozen source `0aba494a89eb02bd651ea1792d755c6cee6c452c` completed all
**19 platform + 23 package commands**, followed by mandatory completeness.
Both independent **1,495-file source guards match**. The original combined
command exits **1**; its platform failure and incomplete-evidence failure are
preserved, rather than replaced by selected passing checks.

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-repair-final-combined-v27-20261025.py
python3 -B /tmp/samgita-collect-v27-20261025.py
```

| Retained local check | Terminal result |
| --- | --- |
| Default driver, seeds 501432 / 987654 | 718/0 each, zero exclusions |
| All 49 isolated native profiles, both seeds | 292/0 each, zero exclusions |
| Native outside consumer | 1/0 against the pinned binary |
| Neutral outside consumers | 32/0 core, 1/0 direct example, 1/0 WebSocket example |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | 42/0 each, including overflow/replay |
| Native wire | 42/0 |
| Populated aggregate, seed 501432 | Core 230/0/1 excluded; web 131/1 failure/8 excluded |
| Populated aggregate, seed 987654 | Core 230/0/1 excluded; web 131/0/8 excluded |
| Platform/API/native block | 59 core + 11 web, zero failures |
| Native authority, both seeds | 3/0 each on its retained dedicated database |
| Recovery/restart, both seeds | 4 core + 1 web, zero failures each |
| Compile, format, strict Credo, forced Dialyzer, legacy checks | Passed |
| Root and all three independent-lock audits | Passed, no advisory exceptions |
| Frozen web dependencies, assets and local production assembly | Passed |

The first populated aggregate retains the same GitHub controller assertion at
`github_controller_test.exs:56`: it assumes the newly registered connection
appears on the first default page. The failed response contains existing rows;
`GitHub.connections/2` orders by UUID and paginates. The later seed's pass does
not repair or erase that failure. No GitHub code, test, records or pagination
contract is changed in this compatibility scope. Neither isolated database was
cleared, unresolved work discarded, nor activation's fail-closed guard bypassed.

Logs and exact commands remain under
`/tmp/samgita-repair-final-{combined,platform,packages}-v27-20261025/`.
The terminal collector records every exit, test count and log SHA256 in
`/tmp/samgita-repair-final-v27-terminal-20261025.json`, SHA256
`33c12caa944c4bbcb2487f4df91ea2203320d6d8ed473734113bed993f362030`.
Historical v24 and earlier outcomes remain unchanged.

The exact pushed source also completed hosted qualification:

| Workflow/job | Outcome |
| --- | --- |
| [Foundation 40155413357](https://github.com/gsmlg-opt/Samgita/actions/runs/40155413357) | Success, including both fresh-then-reused aggregate runs |
| [Selected actual-binary/platform job](https://github.com/gsmlg-opt/Samgita/actions/runs/40155446191/job/121055764965) | Success: driver partitions 363 + 355 = 718/0, wire 42/0, outside native consumer 1/0, platform 59 + 11/0, authority 3/0 twice |
| [All 49 isolated profiles](https://github.com/gsmlg-opt/Samgita/actions/runs/40155446191/job/121055765113) | Success: 292/0, zero exclusions |
| [Full compatibility evidence gate](https://github.com/gsmlg-opt/Samgita/actions/runs/40155446191/job/121055765071) | Failure; conformance workflow remains failed overall |

Hosted run metadata is retained in
`/tmp/samgita-v27-hosted-terminal-20261025.json`, SHA256
`c3b389d072965927717f99942610833b1cc66a5da772961164872373441db872`.
Per-job logs, counts, steps and hashes are indexed by
`/tmp/samgita-v27-hosted-logs-20261025/report.json`, SHA256
`e819cd9512adee67157537c1d4b0c107b9ead9d5ab8483805d3283004b2a8cc8`.
Fresh hosted database success does not close the retained local failure.

The ledger remains **462 implemented / 12 missing / 11 blocked requirements**
and **3,901 implemented / 2,720 missing contracts**, zero verified. Continue the
source-reviewed reachable phase/history, MCP health, Guardian, plugin, trust and
model-metadata cases, then exact request-correlation owners and the complete
final-source matrices. These proposals are unrun and grant no promotion. A11,
upstream-unreachable emitters, external/backend/OS success, the unexplained
listener failure and full compatibility remain incomplete. No tag, publication,
production migration or deployment occurs.

## Retained account/config response owners and blocker recheck

The [52 response-projection owners](native-response-projections-qualification.md)
bind exact original rows/nodes to unchanged passing v24 assertions and the v25
account repeat. Full source/log/manifest checks match; no executable change or
verified promotion. Contracts are 3,901 implemented/2,720 missing; requirements
remain 462 implemented/12 missing/11 blocked. Full final-source/hosted matrices
and the complete compatibility goal remain required.

The source-only final blocker audit independently rechecks all eleven blocked
requirements, whole production Rust searches, nineteen pinned files and 41 exact
anchors/immutable links. All 5,259 codex-rs Rust sources match the hash-verified
archive; the parent additionally compares all 5,276 repository Rust files,
including seventeen tools/Bazel files, with no extra paths or byte differences.
Legacy v1 wire declarations still have no negotiated production emitter; the
production approval path constructs v2 requests. Explicit prediction rejection,
deprecated suppression and declaration/consumer-only notifications remain
blocked. Scripted codec/handler tests remain separate evidence.

UserVerification enroll/delete/verify request/result success still needs an
explicitly owned, authorized macOS account with appropriate Keychain, Secure
Enclave and biometric resources. Stock-Linux unavailable/error outcomes do not
qualify success. The existing A11 source/pre-emission boundary remains blocked;
no new network query, source upgrade or confidentiality acceptance is claimed.
Artifacts are `/tmp/samgita-v27-final-blocker-source-audit-20261025.json`, SHA256
`ac9729acdecc4a38050cc037a3bc57c8f87477cfd69118c7b542351af82969a1`, and
`/tmp/samgita-v27-final-blocker-parent-preflight-20261025.json`, SHA256
`4bb0c4dddde0780a90f140ae9eed51bf5dda6f5af0ba809ad574353ab057b827`.
No blocker is cleared or replaced with mock acceptance.

## Native hook catalog continuation

The [five-file owning block](hook-catalog-qualification.md) passes 29/0 at both
fixed seeds, strict checks and matching 1,495-file/binary guards. One new native
case checks exact inert MCP metadata, three ordered warnings and same-process
catalog restoration. Six precise owners become implemented; prompt/agent schema
success remains missing with immutable skip/producer evidence. Contracts are
3,849 implemented/2,772 missing, zero verified; requirements remain
462 implemented/12 missing/11 blocked. No runtime/fixture/deadline/cleanup/authority
change; complete final-source/hosted qualification and all broader gates remain.

## Retained command, search and import request owners

The [52-owner evidence continuation](native-request-owners-continuation.md)
checks exact original rows/nodes, unchanged native assertions/dependencies and
terminal v24 native repeats. The expected complete manifest/diff matches; no
code, fixture, timeout, cleanup or authority changes occur. Contracts are
3,843 implemented/2,778 missing, zero verified; requirements remain
462 implemented/12 missing/11 blocked. This is scoped retained evidence, not
fresh final-source qualification; all broader incomplete gates remain required.

## Native live status and search continuation

The [seven-file owning block](thread-status-projection-qualification.md) passes
49/0 at both seeds, with compile/format/strict Credo and matching 1,495-file/binary
guards. Two new stock-native cases check exact error-latch/recovery ordering,
pending-tool read/search without inference, explicit handle reply and cold
notLoaded history. No production code, fixture, deadline, cleanup, permission or
activation guard changes. Ten exact original physical rows/nodes become
implemented: 3,791 implemented/2,830 missing contracts, zero verified;
requirements remain 462 implemented/12 missing/11 blocked. Final full matrices
and all broader incomplete gates remain required.

## Native history, voices and badRequest continuation

The [nine-file owning block](native-history-voices-qualification.md) passes
89/0 at both fixed seeds, including nine new actual-native cases, with warning-free
compile, format, strict Credo and matching 1,495-file/binary guards. Exact supplied
history survives storage/provider/cold boundaries; realtime voice selection
reaches captured native sessions; a specific HTTP 400 signature produces native
badRequest with explicit recovery and no retry. No lifecycle deadline, process
cleanup, permission or activation guard changes.

Exactly 140 original physical rows/nodes are bound to the final passing source;
the complete manifest diff and unchanged sections match the expected JSON.
Contracts become 3,781 implemented/2,840 missing, zero verified; requirements remain
462 implemented/12 missing/11 blocked. The unpaired local-shell normalization
proposal correction occurred during source review, not a native failure/repair.
Historical retention and captured synthetic dependencies do not establish live
legacy emission or external success. Continue the remaining live state cases
and full final-source matrix, retaining all A11/aggregate/completeness blockers.

## Terminal frozen v24 local matrix

The complete combined runner terminates at exact source
`2ed69924c8e82adcbfb41740f28789832c86bf02` before further integration. Both
manifest-inclusive 1,495-file source guards match. All 23 package commands pass;
all 19 platform commands execute. The combined command exits 1, preserving both
aggregate failures and mandatory completeness exit 1.

| Check | Actual result |
| --- | --- |
| Default driver, seeds501432/987654 | **715/0 twice** |
| All49 isolated native profiles, same seeds | **283/0 twice**, zero excluded |
| Outside-umbrella actual-native consumer | **1/0** |
| Neutral outside consumers | Core32/0, standalone1/0, WebSocket consumer1/0 |
| Neutral WebSocket seeds455834/501432/987654 | **42/0 at each seed** |
| Native wire | **42/0**; warning-free compile, format and audit pass |
| Populated root, both seeds | Core230/0/one excluded; web131/one failure/eight excluded |
| Platform/API/native | **59 core +11 web/0** |
| Dedicated authority, both seeds | **3/0 twice** |
| Original recovery/restart, both seeds | **4 core +1 web/0 twice** |
| Remaining platform checks | Compile, format, strict Credo, Dialyzer, audit, legacy checks, frozen web dependencies, assets and local production assembly pass |

Both aggregate failures retain the first-page membership assertion in
`github_controller_test.exs:56`: the retained database contains older records,
and its first page does not contain the newly registered connection. No test,
pagination, data, activation guard or retry policy is changed. The separate
recovery/authority databases retain prior history and intentional unresolved
work. These results do not justify a reset, discarded task or automatic replay.

Commands, exits, times, logs and source hashes remain in
`/tmp/samgita-repair-final-{combined,platform,packages}-v24-20261025/` and their
same-named Python runners. The terminal report is
`/tmp/samgita-repair-final-v24-terminal-20261025.json`, SHA256
`2b8e9b912d515af0116d5708b180b0308f854be46bed2b528f4b02ff6452aeb4`.
Its manifest has 3,591 implemented/3,030 missing contracts. The subsequent
[50-owner index](native-envelope-owners-qualification.md#app-account-and-plugin-requests-at-2ed6992)
changes that to 3,641 implemented/2,980 missing; requirements remain 462 implemented/
12 missing/11 blocked, with zero verified. This does not alter historical v21
evidence or counts. No release, publication, migration or deployment occurs.

## Terminal hosted checkpoint at 2ed6992

Both workflows finish on exact pushed source
`2ed69924c8e82adcbfb41740f28789832c86bf02`.
[Foundation40149859308](https://github.com/gsmlg-opt/Samgita/actions/runs/40149859308)
passes. [Conformance40149942489](https://github.com/gsmlg-opt/Samgita/actions/runs/40149942489)
passes both native execution jobs and fails its mandatory complete-evidence job;
the overall workflow remains **failed**.

The selected driver partitions pass **361 + 354 = 715/0**. All 49 required isolated
profiles pass **283/0, zero excluded**. The wire package passes42/0, the outside
actual-native consumer1/0, platform59 core+11 web/0 and authority3/0 at both fixed
seeds. Hosted foundation's two fresh-database aggregate runs pass; they do not
resolve the retained local database's first-page assertion.

The exact terminal API report is
`/tmp/samgita-v24-hosted-terminal-20261025.json`, SHA256
`e18948a89535377f46ca0e16cbcbc4114dee2dce3c8b19af56e7ace0bfd33111`.
Full downloaded logs, extracted counts and hashes are in
`/tmp/samgita-v24-hosted-logs-20261025/report.json`, SHA256
`73f095e9dc1408d346faa63cbeed1bd044fed2d92dfb9cdadb1a859137c3fe37`.
A11, source-unreachable production emissions, external/OS success and full
compatibility remain incomplete. Subsequent executable changes require fresh
final-source qualification; these results do not qualify them in advance.

## Terminal-error and managed-metadata continuation

The [complete ten-file owning block](managed-errors-qualification.md) passes
49/0 twice at501432/987654, including14 new actual-native cases. It preserves
the first49/2 PathUri-oracle failure and static numeric/environment failures;
the corrected wire oracle follows pinned source, the numeric token has equal
AST, and final test-environment compile/format/strict Credo pass. Forty-seven
exact owners bring contracts to3539 implemented/3082 missing, zero verified;
requirements stay462 implemented/12 missing/11 blocked. No execution runtime,
cleanup assertion or deadline is weakened. Continue the remaining reachable
native variants and full final-source local/hosted qualification.

## Retained client-owner continuation

The [bounded index](retained-client-owners-qualification.md) binds93 existing
positive operation/history owners to both passing native repeats in the terminal
v21 package matrix. Every selected ID/pointer/hash and source preimage is checked;
the resulting full JSON and exact93-owner diff match. Inventory consistency and37
regressions pass. Counts become3492 implemented/3129 missing contracts, zero
verified; requirements remain462 implemented/12 missing/11 blocked. This unit
changes no executable. New native behavior and final-source qualification remain
required, with A11, unreachable/external/OS and aggregate gates still incomplete.

## Terminal frozen v21 local matrix

The complete combined runner terminates at exact executable source
`4d2d1e370045fd268862435d868dd0a1d4ee2dc3` before further integration.
Both manifest-inclusive 1,490-file source guards match. All23 package commands
pass; all19 platform commands execute. The combined command exits1, preserving
the two aggregate failures and the mandatory completeness exit1.

| Check | Actual result |
| --- | --- |
| Default driver, seeds501432/987654 | **700/0 twice**, 698.461/703.264s |
| All49 isolated native profiles, same seeds | **280/0 twice**, 645.877/652.1s; zero excluded |
| Outside-umbrella actual-native consumer | **1/0** |
| Neutral outside consumers | Core32/0, standalone1/0, WebSocket consumer1/0 |
| Neutral WebSocket seeds455834/501432/987654 | **42/0 at each seed** |
| Native wire | **42/0**; warning-free compile, format and audit pass |
| Populated root, both seeds | Core230/0/one excluded; web131/one failure/eight excluded |
| Platform/API/native | **59 core +11 web/0** |
| Dedicated authority, both seeds | **3/0 twice** |
| Original recovery/restart, both seeds | **4 core +1 web/0 twice** |
| Remaining required platform checks | Compile, format, strict Credo, Dialyzer, audits, legacy checks, frozen web dependencies, assets and local production assembly pass |

Both aggregate failures are the unchanged first-page membership assertion in
`github_controller_test.exs:56`, after registration on the retained populated
database. No pagination, assertion, data, guard or retry policy is changed.
Recovery retains the same databases, explicit fixture evidence and intentional
unresolved-work block; native completion still requires review and acceptance.

Exact commands, exits, logs and source hashes are retained in
`/tmp/samgita-repair-final-{combined,platform,packages}-v21-20261025/` and their
same-named Python runners. The terminal collector report is
`/tmp/samgita-repair-final-v21-terminal-20261025.json`, SHA256
`7915e6ecaaf9a47f78217c8fafdb147ccb7bbb9c3e11ce4c0e75b00ff1f0897a`.
Counts remain462 implemented/12 missing/11 blocked requirements and3399
implemented/3222 missing contracts, zero verified. This is local qualification,
not publication, deployment, A11 or full compatibility acceptance.

## Terminal hosted checkpoint at 4d2d1e3

Both workflows finish against exact pushed source
`4d2d1e370045fd268862435d868dd0a1d4ee2dc3`.
[Foundation 40145185169](https://github.com/gsmlg-opt/Samgita/actions/runs/40145185169)
passes. [Conformance 40145207220](https://github.com/gsmlg-opt/Samgita/actions/runs/40145207220)
passes both required native execution jobs and fails its mandatory complete-evidence
job. The overall conformance workflow remains **failed**.

The default driver partitions pass **355 + 345 = 700/0**, seed501432. All49
explicit isolated native profiles pass **280/0, zero excluded**. The wire package
passes42/0; the outside-umbrella actual-native consumer passes1/0. Platform/API/
native tests pass **59 core +11 web/0**; dedicated authority passes **3/0 at each
of501432/987654**. Foundation repeats pass **230 core +131 web/0**, retaining
one/eight exclusions. A fresh hosted database does not resolve the separate
retained local GitHub first-page assertion.

Metadata, exact steps and complete logs are retained in
`/tmp/samgita-hosted-4d2d1e3-terminal-20261025/`. SHA256 values:

| Artifact | SHA256 |
| --- | --- |
| `report.json` | `00868b3bbd2ae4332a28251add1f20367ff6fbc93823f614f50651fcc92d1bf1` |
| `conformance.log` | `c3258676da9c3423217dcc0bc18ed04ccac35e9992dce7c21a3d6abdc1655516` |
| `foundation.log` | `c3d4ddf9d59677e1f630727a0075425cd945b849a468c7b67d2ab6c07d85453f` |

These are actual stock Codex results using owned synthetic dependencies. They do
not qualify real external accounts/backends, other OSes, source-unreachable
production emissions, A11 or the complete goal. Counts remain485 requirements,
**462 implemented/12 missing/11 blocked**, and6621 contracts,
**3399 implemented/3222 missing**, zero verified. No tag, publication, production
migration or deployment occurs. Later executable changes require new qualification.

## Independent search/ranking continuation

The [owning record](search-ranking-qualification.md) passes24/0 twice in the
complete four-file native block, with warning-free compile, format, strict
Credo and a matching source guard. Its first ordinary-pagination failure exposes
the pinned created_at forward-cursor precision defect. Exact duplicate/skip
diagnostics retain that limitation; valid created pagination is not claimed.
All independent full/first sort/timestamp, updated/recency continuation and local
plugin rank/keyword assertions remain. Four exact physical owners bring contracts
to3399 implemented/3222 missing; requirements stay462 implemented/12 missing/
11 blocked, zero verified. Freeze this source for complete local/hosted checks;
all broader compatibility/security/publication gates stay incomplete.

## Fork lifecycle continuation

The [owning record](fork-boundary-qualification.md#paginated-ephemeral-active-and-prediction-continuation)
passes its complete seven-file block43/0 at both fixed seeds, with strict checks
and a matching1,490-file source guard. Paginated ephemeral fork, active callback
boundaries and prediction instruction/tool inheritance deepen five existing
properties without a state/count promotion. Original active durable-item,
dynamic-tool schema and invented response-field failures remain documented with
their pinned source corrections. Requirements remain462 implemented/12 missing/
11 blocked, contracts3395 implemented/3226 missing, zero verified. Complete
combined-source local and exact-source hosted qualification remain required;
A11, upstream-unreachable/external/OS and all broader gates stay incomplete.

## Image-view and sandbox continuation

The [owning record](image-view-fork-qualification.md) adds a real native image
read, exact independently decoded pixels and warm/first-cold selective history
after only the owned image is removed. Invalid bytes and low detail produce the
exact model-visible error without any invented imageView record. Fork omitted/
null preserve the named readonly profile; invalid enum/type preserve histories
before the explicit valid override and permitted child turn. The complete
six-file native block passes36/0 twice, fixed seeds, with compile/format,
strict Credo438 files and a matching manifest-inclusive source guard.

Twelve exact physical owners bring contracts to **3395 implemented/3226 missing**,
zero verified; requirements stay **462 implemented/12 missing/11 blocked**,
zero verified. The prior cold/process/config block below keeps its historical
counts. Complete final-source local/hosted checks remain required; no selected
pass closes A11, upstream-unreachable runtime paths, external/OS success or the
full goal.

## Cold item, process and config continuation

The [owning record](cold-items-process-config-qualification.md) retains all first
failures and exact source-backed oracle corrections. Five new structured-MCP
and content-array native cases pass5/0 at both fixed seeds; the complete
15-file owning block passes115/0 twice, with compile/format, strict Credo437
files and matching 1,488-file source guard. No production driver, original
cleanup, timeout or assertion is weakened. A low-detail image deliberately
remains a negative provider-preparation case; public input/history stays exact.

Exactly127 physical owners gain scoped implemented evidence, with four existing
MCP metadata owners gaining nonnull depth and existing content/image/namespace
rows gaining further depth without another count. Regenerated ledger:485
requirements, **462 implemented/12 missing/11 blocked**;6621 contracts,
**3383 implemented/3238 missing**;zero verified. Inventory consistency passes.
Final combined-source local/hosted matrices remain required; v20 below is a
historical exact-source result. A11, upstream-unreachable native emitters,
required external/OS success and full compatibility stay incomplete.

## Terminal frozen v20 local matrix

Before the next source edits, both complete runners finish on the unchanged
`4db58a8` executable snapshot. Both 1,485-file source guards include the manifest
and match. All 19 platform commands execute. At both 501432 and 987654, core
passes **230/0/one excluded**; web reports **131/one failure/eight excluded**.
Both failures are the retained `GitHubControllerTest` first-page assertion at
`github_controller_test.exs:56`. No reset, row deletion or unrelated repair occurs.

The platform/API/native block passes **59 core + 11 web/0**. Dedicated authority
passes **3/0 at both seeds** in its separate retained database; original recovery
and restart pass **4 core + 1 web/0 twice** in the original populated database.
Compile, format, strict Credo, forced Dialyzer, strict audit, frozen frontend
dependencies, assets, legacy exclusion and local production assembly pass.

All 23 independent-package commands pass. Complete driver repeats are
**678/0 twice**; all 49 explicit profiles are **277/0 twice**. Actual-native and
neutral outside consumers pass. Neutral WebSocket passes **42/0** at each of
455834, 501432 and 987654. Wire tests pass **42/0**; independent audits,
warning-free compile/format, inventory consistency and Python regressions pass.

Commands, full logs, source hashes and terminal results are retained in
`/tmp/samgita-repair-final-{combined,platform,packages}-v20-20261025/` and matching
Python runners. The terminal summary is
`/tmp/samgita-repair-final-v20-terminal-20261025.json`, SHA256
`d431ca9d15bad038b085887774bd0cc6231fc9ea1140f6c0197fa86fdd2a40f3`.
The combined command exits 1 for the retained aggregate failures and mandatory
completeness exit 1. Counts remain **462 implemented / 12 missing / 11 blocked**
requirements, **3256 implemented / 3365 missing** contracts, zero verified.
This matrix does not qualify subsequent source changes or clear A11,
source-unreachable emitters, unavailable external/OS success or publication gates.

## Hosted checkpoint at 4db58a8

Both workflows are terminal on exact pushed source
`4db58a8860e62d67117fa2b0ca093374ede1c7e0`.
[Foundation 40137498744](https://github.com/gsmlg-opt/Samgita/actions/runs/40137498744)
passes. [Conformance 40137556158](https://github.com/gsmlg-opt/Samgita/actions/runs/40137556158)
passes both native execution jobs and fails the mandatory full-evidence gate.
The overall conformance workflow remains **failed**.

The wire package passes 42 tests; default driver partitions pass
**368 + 310 = 678/0**, seed 501432; the outside-umbrella actual-native consumer passes 1/0.
Platform/API/native scenarios pass **59 core + 11 web/0**. The separate retained
authority profile passes **3/0 at each of 501432/987654**. All 49 required isolated
native profiles execute **277/0/zero excluded**, including the added Stop and
selected review cases. These use the immutable real Codex binary with synthetic
dependencies; they do not qualify real external accounts/backends or other OSes.

Foundation's two populated repeats each pass **230 core/0/one excluded** and
**131 web/0/eight excluded**, alongside isolated restart/rollback, independent
packages/consumers, static checks, forced Dialyzer, strict audit, assets and local
production assembly. Fresh hosted data does not erase the preserved local
GitHub first-page failure. No release, publication or deployment occurs.

Exact-head metadata, full logs, parsed per-step counts and hashes are retained in
`/tmp/samgita-hosted-4db58a8-20261025/`. Report SHA256 is
`b045c590170b02c9134f7e369cef6701d521be28befd1c74950e7c7158cd9fd4`;
conformance log SHA256 is
`6a12b78dc06463f4435a51f42cb10819ce8498720cf4b2f9d089b618bdd98221`.
The tested manifest records **462 implemented / 12 missing / 11 blocked**
requirements and **3256 implemented / 3365 missing** contracts, **zero verified**.
A11, source-unreachable emitters, required external/OS success and all remaining
behavior evidence stay incomplete; no target exclusion is inferred.

## Stop, review, cwd and native settlement continuation

Three actual-native cases add Stop continuation with selected persisted
HookPrompt, warm/cold selective enteredReviewMode, and five-turn cwd inheritance
with sibling isolation. The complete nine-file native block passes61/0 at
501432/987654, with the original failed timeline oracle retained in v1. The
corrected projection preserves all expected events/deadlines. Exact evidence is
`/tmp/samgita-native-stop-cwd-authority-v2-20261025/`.

Two additional actual-native platform cases preserve uncertainty after a forged
opaque handle and reject settlement after native completion/worker-role removal.
The expanded dedicated retained-DB profile passes3/0 twice. Original platform
authority/race/integration passes21 core+7 web/0 twice; original recovery/restart
passes4 core+1 web/0 twice, with no reset, deleted records or activation bypass.
The initial ephemeral includeTurns fixture error remains in v2; only the new
history-dependent case now explicitly requests persistent paginated history.
The passing v3 platform source guard differs from v2 only in that test fixture
and authority profile; all passing native-source hashes remain exact.

Root/driver warnings-as-errors compile, formatting, namespace preflight and
strict Credo435 files pass. V3 commands/logs/source/results are
`/tmp/samgita-native-stop-cwd-authority-v3-20261025/`.
Only21 exact primary properties/variants gain scoped implemented evidence:
seven HookPrompt, five enteredReviewMode, one cwd and eight existing direct
native owners. Inventory consistency and all37 Python regressions pass.
Generated ledger:462 implemented/12 missing/11 blocked requirements;
3256 implemented/3365 missing contracts; zero verified. Full final-source local
and hosted checks remain required; source-unreachable legacy/notification paths,
real external/OS success and A11 are not passed. No release/publication/deployment.

## Hosted checkpoint at 9a46afe

Both workflows are terminal on exact pushed source
`9a46afe995ed1c726ddab180d9935935419e68b8`:
[foundation40133286182](https://github.com/gsmlg-opt/Samgita/actions/runs/40133286182)
passes; [conformance40133297065](https://github.com/gsmlg-opt/Samgita/actions/runs/40133297065)
passes both native execution jobs and fails mandatory completeness. The overall
conformance workflow is **failed**, not waived or expected-success.

The native wire package passes42 tests; default driver partitions pass
**367+310=677/0**, seed501432; the actual-binary outside consumer passes1/0.
Platform/API/native scenarios pass **59 core +11 web/0**. The dedicated retained
authority database profile explicitly executes at both501432 and987654,
**1/0 each**. All49 required isolated profiles execute **275/0/zero excluded**.
Foundation's two populated repeats pass230 core/0/one excluded and131 web/0/eight
excluded each, alongside restart/rollback, independent packages/consumers,
static checks, forced Dialyzer, audit, assets and local production assembly.
These fresh hosted aggregates do not erase the retained local GitHub-page failure.

Exact-head metadata, complete logs, per-step counts and hashes are retained in
`/tmp/samgita-hosted-9a46afe-20261025/`; `conformance.log` SHA256 is
`a1e7606d1a8d63a87ca12bd0f0cdb3122eee5be3ce9ab5c3c21d81219adc4bdd`.
The manifest remains **462 implemented /12 missing /11 blocked requirements**,
**3235 implemented /3386 missing contracts**, zero verified. Full qualification,
A11, source-unreachable legacy/notification success and required external/OS
success remain incomplete. No publication, release or deployment follows.

## Terminal frozen v19 local matrix

The complete unchanged9a46afe executable snapshot finishes both runners before
subsequent source edits. All19 platform commands execute; the sole failure is
`GitHubControllerTest`'s unchanged first-page assertion
(`github_controller_test.exs:56`) at seed501432. Core230/0 and web131/1 run at
that seed; the second populated run passes230 core/0 and131 web/0. One core and
eight web exclusions remain explicit. No row is removed, database reset or
unrelated pagination repair performed.

The platform/native block passes59 core+11 web/0. The dedicated retained
authority profile passes1/0 at each fixed seed in its separate allowlisted DB;
the original retained DB passes recovery/restart4 core+1 web/0 twice. Compile,
format, strict Credo, forced Dialyzer, strict dependency audit, frozen frontend
dependencies, assets, legacy exclusion and production assembly pass. Assembly
does not publish or deploy anything.

All23 independent package commands pass. Complete driver suites are677/0
at501432 and987654; all49 native profiles are275/0 at both seeds. Actual-native
and neutral outside consumers pass. Neutral WebSocket is42/0 at the original
455834 seed and501432/987654. Wire tests, all package warning-free compile/
format checks, inventory regressions/consistency and independent strict audits
pass. Both final executable/config/workflow source guards match.

Commands, logs and source hashes are retained in
`/tmp/samgita-repair-final-{combined,platform,packages}-v19-20261025/` and their
matching Python runners. The combined runner exits1 for the retained platform
failure and required completeness exit1. The ledger remains3235 implemented/
3386 missing contracts and462 implemented/12 missing/11 blocked requirements,
zero verified. This records an executed complete matrix with explicit failures,
not full compatibility, A11 closure or acceptance of subsequent source changes.

## Isolated native authority concurrency continuation

The [management-wins profile](native-authority-qualification.md#management-wins-dispatch-with-independent-postgresql-transactions)
passes **1/0 twice** on the same dedicated scratch DB, with three independently
verified backend PIDs and an actual `pg_blocking_pids` barrier. Legal management
commands commit cancellation/fencing before a waiting real-approval response
dispatch; original and repeated dispatch plus real Driver execution reject
`ownership_lost`, without a ticket/send. Existing records, pending native
interaction and unresolved effects remain. The new database is exact-allowlisted
and distinct from the preserved recovery DB; no fabricated resolution, cleanup
or guard bypass is used. Seven test-only fixture bodies are extracted unchanged.

The initial profile command failed before tests on the local SQL_ASCII template;
the absent named scratch database was explicitly created UTF8 from template0.
The linked record preserves that prerequisite failure and exact provisioning.
Existing authority/race/integration checks pass **21 core +7 web/0 twice**, then
recovery/restart **4 core +1 web/0 twice**, in the original retained database.
Compile/format/strict Credo435 files and source guard pass. Commands/hashes are in
`/tmp/samgita-native-authority-lock-v2-20261025/` and the linked record. Counts
remain **462 implemented /12 missing /11 blocked requirements**, **3235
implemented /3386 missing contracts, zero verified**. Full authorization,
final-source local/hosted matrices, A11 and external/OS success remain incomplete.

## Persisted output continuation

The [selective reasoning/Plan unit](output-notice-qualification.md#selective-persisted-reasoning-and-plan-items)
passes **25/0 twice** in its complete eight-file owning block, plus changed-file
**6/0**, warning-free compile/tests, formatting, strict Credo and an unchanged
source guard. It preserves independently prescribed reasoning empty positions
and extracted Plan body/turn identity through actual paginated `thread/items/read`.
Eleven individually hash-checked physical owners bring the ledger to **3235
implemented /3386 missing contracts**, zero verified; requirements remain
**462 implemented /12 missing /11 blocked, zero verified**. The linked record
contains commands/hashes and the warm UDS-only limitation. No cold process,
live backend, A11 or full compatibility acceptance follows from the scoped pass.

## Hosted fixture interpreter prerequisite

[Conformance40131233584](https://github.com/gsmlg-opt/Samgita/actions/runs/40131233584)
at `16e60c24541e4a4fe37ddba08f5a5299cae2588e` fails the new required-skills
profile before initialization: `disconnected, uncertain:false`. Authentication,
executor metadata, timeout and request-ID profiles passed before it; downstream
profiles are skipped, not accepted. Its separate completeness job also fails.
[Foundation40131214046](https://github.com/gsmlg-opt/Samgita/actions/runs/40131214046)
passes at the same source. Selected conformance was still running when this
repair was prepared; no overall hosted pass is claimed.

The new fixture imports standard-library `tomllib` at module startup. The exact
failed image is `ubuntu22/20261012.322`; its official
[software inventory](https://github.com/actions/runner-images/blob/ubuntu22/20261012.322/images/ubuntu/Ubuntu2204-Readme.md)
lists default Python3.10.12. Neither native job selected another interpreter.
Running the unchanged fixture with `--help` under an isolated Python3.10.20
exits1 with `ModuleNotFoundError: No module named 'tomllib'`, before any namespace,
executor or Codex startup; the identical file under Python3.13.15 exits0. The
hosted child stderr was deliberately discarded and its interpreter version was
not logged, so this directly reproduces the missing prerequisite, not a captured
hosted Python traceback. A final hosted rerun is required to confirm the repair.

Both native jobs now explicitly select Python3.13 and print its version and load
the fixture with `--help` before fetching/starting Codex. TOML parsing, native
assertions, deadlines, firewall, isolation and process ownership are unchanged.
The driver README distinguishes the fixture's Python3.11+ requirement from the
transport cleanup helper. The actual required-skills profile passes **1/0 at each
of seeds501432 and987654** after this change, with namespace and import preflight
and an unchanged targeted workflow/fixture source guard. Evidence:
`/tmp/samgita-hosted-python-repair-v1-20261025/` and
`/tmp/samgita-hosted-skills-python-diagnosis-20261025.json`; the official runner
source response is `/tmp/samgita-hosted-skills-runner-source-20261025.json`.
These focused passes do not qualify the whole package or repair A11.

### Terminal hosted interpreter-repair checkpoint

At `8fcf76cbc226371b397232326ed1ea4e81fff4f5`,
[foundation40132321197](https://github.com/gsmlg-opt/Samgita/actions/runs/40132321197)
passes. [Conformance40132352439](https://github.com/gsmlg-opt/Samgita/actions/runs/40132352439)
has terminal **successful selected and isolated native jobs**, while its mandatory
completeness job fails. Both native jobs report **Python3.13.16** and load the
unchanged TOML fixture before native startup. All49 required isolated profiles
execute: **275 tests /0 failures /0 excluded**. The earlier required-skills
startup failure is absent in this repair run; no assertion or deadline changed.

The selected job passes **365+310=675 driver tests**, the outside-umbrella actual
binary consumer **1/0**, and the platform/API/native journey **59 core +11 web/0**.
Foundation passes both populated repeats (**230 core/0/one excluded;131 web/0/eight
excluded** each), restart/rollback, packages/consumers, strict static checks,
forced Dialyzer, audits, assets and local production assembly. Exclusions remain
explicit and do not qualify the separate native profiles. Nothing is published
or deployed.

The previous16e60c2 selected job also subsequently finishes successfully with
the same675 driver,1 consumer and59+11 platform counts. Its isolated job remains
failed and later profiles skipped; the later8fcf76c run supplies the successful
interpreter-repair evidence, not a retroactive pass for16e60c2.

Exact-head metadata, logs and parsed counts are retained in
`/tmp/samgita-hosted-8fcf76c-20261025/`; its `conformance.log` SHA256 is
`80fcf19e5dbf575efe2563cc78a73e73db3506656fe9c81a0e20242b6ba6720e`.
The mandatory gate exits1 at **462 implemented /12 missing /11 blocked
requirements** and **3224 implemented /3397 missing contracts**, zero verified.
That manifest predates the eleven later reasoning/Plan owners. It does not
qualify subsequent executable additions or full compatibility. A11, unreachable
production emitters and required external/OS success remain incomplete.

### Explicitly interrupted v18 local matrix

The frozen `16e60c2` platform runner completed all17 commands with a matching
source guard. Runtime/API/native concurrency passes **59 core +11 web/0**;
both consecutive populated-database recovery/restart repeats pass **4 core +1
web/0** each. Compile, formatting, strict Credo, forced Dialyzer, strict audit,
legacy exclusion, frozen frontend install, assets and production assembly pass.
No assembly was started or published. Aggregate seed501432 retains the GitHub
first-page assertion failure; seed987654 passes. The pagination test is unchanged,
and this is not a green aggregate matrix.

The package runner completed six commands: inventory regressions **37/0**,
inventory consistency, namespace and sandbox prerequisites, driver compilation
and formatting. Its first full driver seed501432 was deliberately interrupted
with SIGINT to the verified exclusively owned matrix process group, before
editing the workflow or integrating further native regressions. Its test count
is unfinished; the second seed, all49 profiles, consumers, wire and WebSocket
checks are **not run in v18**. The process group was confirmed empty afterward.
`interruption.json` records the unchanged source at interruption and completed
commands. This is partial evidence, never a package-suite pass.

Exact commands/logs remain in
`/tmp/samgita-repair-final-{combined,platform,packages}-v18-20261025/`.
The separately executed mandatory `--require-verified` gate exits1. Counts remain
**462 implemented /12 missing /11 blocked requirements** and **3224 implemented /
3397 missing contracts, zero verified**. The next fixed-source complete local
and final-pushed hosted matrix remains required; source-unreachable emitters,
external/OS success, A11 and release acceptance stay incomplete.

## Scoped continuation after 636b2ad

The [native hook warning/context differential](hook-lifecycle-qualification.md#warning-versus-model-context)
and [fourteen exact notification-owner index](notification-owner-supplement-qualification.md)
add sixteen implemented contracts, zero verified: **3,224 implemented /
3,397 missing**. Requirements stay **462 implemented /12 missing /11 blocked**,
zero verified. The same v6 complete21-file native block passes **127/0 twice**,
190.3/190.4 seconds; hook-first passes **8/0**. Compile/format/strict Credo and
source guard pass. Exact commands/hashes are in the v6 authority record below.
Only independently asserted synchronous hook literals/effects and present-null
rate-limit fields gain evidence; no positive account, alias or lifecycle
qualification is inferred. Complete frozen-source local/hosted matrices remain
required; A11, source-unreachable emitters and external/OS success stay open.

The [successful operator-reply receipt replay unit](native-authority-qualification.md#successful-operator-receipt-replay-after-worker-role-removal)
passes **17 core +7 web/0 twice**, fixed seeds, on the same retained database.
An authorized successful REST receipt replay control is followed by management
API worker-role removal; repeated original reply commands and explicit real
Driver sends reject with exact errors while journals/native pending effects
remain unchanged. No DB reset, history cleanup or guard bypass occurs. Root/
driver compile, format, strict Credo433 files and the executable/config/workflow
guard pass. The combined21-file native block passes **127/0 twice**.
Exact commands/logs are `/tmp/samgita-native-repair-continuation-v6-20261025/`;
results SHA256 `35a9a2fa9de9df3839b92464f1d396488b2341a3c6a5439b1b9347fb19e94e28`,
source SHA256 `472fffa65eca4866ca6df9319aa149b2339c69348febdcd21c2b6e7590f07b5f`.
This strengthens the still-missing authorization lifecycle, with no count or
fully verified promotion. Full final-source local/hosted matrices remain open.

The [required-skills native differential](environment-skills-qualification.md)
passes the complete nineteen-file owning block **113/0 twice**, seeds501432/
987654 (168.4/171.8 seconds). Skills-first and timeout-first controls each pass
**1/0**; compile, format, strict Credo433 files and executable/config/workflow
guard pass. Exact commands/logs are
`/tmp/samgita-native-repair-continuation-v5-20261025/`;
results SHA256 `0bd111e5478afd8ce449be4e6e9814856db7ba0a3c56fe9e094dc570e390ae68`,
source SHA256 `104fc85eb0e8ac2b5dd1c234797116af680b081606ccdd59403f1d6a308e75af`.
The real executor discovers only owned inert files; a missing skill fails before
inference. The synthetic provider is not live backend acceptance. Initial
refused HTTP/ancestor traffic and supported per-thread fixture configuration
repair remain in the linked record; no deadlines/caps/assertions are relaxed.
Two exact physical properties become implemented: **3,208 implemented /
3,413 missing**, zero verified; requirements remain unchanged. This is49
required hosted profiles. Full final-source local/hosted matrices remain open.

The [granular/default and unsupported strict-session permission unit](permission-lifetime-qualification.md#granular-policy-and-unsupported-session-strictness)
passes **30/0 twice**, seeds501432/987654, in the complete seven-file owning
block; the lifetime file alone passes **9/0**. The same block proves
[positive elapsed goal inheritance](goal-fork-qualification.md#positive-elapsed-usage-through-public-goal-reads)
using the existing no-work interval, with no added delay/provider request.
Compile, format, root strict Credo and executable/config/workflow guard pass.
Exact commands/logs are
`/tmp/samgita-native-repair-continuation-permission-policy-v1-20261025/`;
results SHA256 `32bdbc75cc9c9262f99a7c2ca257a1048a1c2e0c69582e4b862674755e02304d`,
source SHA256 `423c23cd7d6df3c4c07c06e1eb6bbbed6150ae5f3e197848bd38df297a9f76d8`.
One exact bool/default owner becomes implemented: **3,206 implemented /
3,415 missing**, zero verified. Requirements are unchanged; approval/default
lifecycle stays missing. Complete final-source matrices remain required.

The next v3 extension passes the full sixteen-file owning block **92/0 twice**,
seeds501432/987654. It adds [exact native upgrade request-ID and reconnect](environment-owners-qualification.md#exact-original-upgrade-request-id-through-reconnect),
and [no-source-goal, per-fork config and public stopped-state inheritance](goal-fork-qualification.md#source-absence-per-fork-config-and-stopped-goal-states).
The timeout fixture also compares bearer values case-sensitively. Existing
deadlines, caps, three goal provider requests, restarts, guards and cleanup remain.
Compile, format, root strict Credo and executable/config/workflow source guard
pass. Exact commands/logs are `/tmp/samgita-native-repair-continuation-v3-20261025/`;
results SHA256 `2a99c6e37ecb807251bb04836c4b110107db7cc775e807642581f844b9d9c516`,
source SHA256 `6e6ae83bdcc3c7c8fd9728c5b95ae09f5424a110ef3591fbc940cc48473f540d`.
One further exact physical owner becomes implemented: **3,205 implemented /
3,416 missing**, zero verified; requirements remain unchanged. This is48 required
hosted profiles, with final-source local/hosted qualification still required.

The fifteen-file owning block passes **91/0 twice**, seeds `501432` and
`987654`, after the same-sender queued-notification barrier and three native
extensions. The [notification record](notification-test-synchronization.md#queued-notification-after-reconnect)
preserves the unexplained historical failure, isolated negative reproduction
results and deterministic held-callback regression. No production Session or
deadline changes. The new [executor timeout](environment-owners-qualification.md)
distinguishes real500ms expiry from delayed5000ms success without status retries;
the [personality differential](default-gates-qualification.md#new-thread-personality-instruction-differential)
asserts actual provider instructions; the [goal prefix extension](goal-fork-qualification.md#current-goal-snapshot-with-historical-prefixes)
copies the current accounted21 snapshot through2/1/0-turn histories and cold
empty-child resume, with exactly the existing three provider requests.

Warning-free compile/tests, formatting, root strict Credo (431 files) and the
executable/config/workflow source guard pass. Exact commands and logs are under
`/tmp/samgita-native-repair-continuation-v2-20261025/`; results SHA256
`c967f72292bd73506520f86958662d8ea1c3a37106624e4eab1f9b6dd2d292f7`,
source SHA256 `595ddba6fe770b9b229e3fddcc7f820fba6008c8959596354b99e8046779c4ca`.
The initial v1 timeout profile failed before native startup because the draft
omitted required isolated `CODEX_HOME`. Supplying the same explicit scratch
environment as the retained thread fixture corrects the fixture without
relaxing the driver guard. Both initial and successful logs remain.

Eleven existing direct environment owners plus the two new primary properties
gain implemented-only evidence after checking each physical node/hash. Inventory
regressions **37/0** and generated consistency pass: **485 requirements:0
verified/462 implemented/12 missing/11 blocked;6621 contracts:0 verified/3204
implemented/3417 missing**. Prefix enrichment changes no count. The timeout is
the47th explicitly required hosted profile, not a hosted pass. The failed v17
local and terminal636b2ad hosted outcomes below remain historical evidence;
complete final-source local/hosted qualification, further reachable behavior,
A11 and external/OS success remain required. No publication or deployment.

## Hosted checkpoint at 589e02f

Both workflows are terminal at exact pushed source
`589e02ffd96f7372b2d654835e8c0df0c183511b`.
[Foundation40127514136](https://github.com/gsmlg-opt/Samgita/actions/runs/40127514136)
passes every step: both populated aggregates (**230 core/0/one excluded +
130 web/0/seven excluded** each), restart/rollback **1/0**, neutral core **32/0**,
both neutral outside consumers **1/0** each, WebSocket/native wire **42/0** each,
strict static checks, forced Dialyzer, audits, assets and production assembly.
The assembly is never started, published or deployed.

[Conformance40127696162](https://github.com/gsmlg-opt/Samgita/actions/runs/40127696162)
is **failed overall**. Both native execution jobs pass every step: default
driver partitions **365/0 +306/0 =671/0**, seed501432; wire **42/0**; native
outside consumer **1/0**; fenced runtime/API/concurrency **59 core +10 web/0**;
and all **47 explicit isolated profiles,271/0**, without excluded tests or
skipped downstream steps. These include actual executor expiry/control, personality
instruction selection and accounted prefix inheritance. App-server frames come
from the immutable pin; owned synthetic dependencies do not prove live providers.

Mandatory completeness passes all **37 inventory regressions** and generated
source consistency, then fails `--require-verified`: **485 requirements:0
verified/462 implemented/12 missing/11 blocked;6621 contracts:0 verified/3204
implemented/3417 missing**. Those are the hosted source's original counts; later
request-ID/goal extensions are not retroactively qualified. This does not repair
the retained local populated GitHub assertion or complete the entire local matrix.

The terminal-only read-only collector
`/tmp/samgita-collect-hosted-589e02f-20261025.py` verifies exact head and completed
status before saving both full logs/step metadata in
`/tmp/samgita-hosted-589e02f-20261025/`. Its report SHA256 is
`10a115e7cd7a2abcbffc88018b30f1789be34c1b890f21fe14ee2fdd147eb2d9`.
The [latest stable A11 source recheck](a11-ingress-boundary.md#latest-stable-upstream-availability)
still finds no supported complete pre-emission projection. Full final-source
local/hosted qualification, reachable remaining behavior, source-unreachable
emitters and external/OS success remain incomplete. No release or deployment.

## Frozen local matrix at 636b2ad

The v17 combined runner is terminal against executable source
`636b2adaaac39a33cc77608883b77d0585ed0212`, exiting one. All **17 platform
commands** ran. The package runner executed **8/23 commands** before its
retained fail-fast rule stopped on the second default-driver run; the remaining
15 commands, including both46-profile repeats, consumers and WebSocket/wire
checks, were **not run** locally in this matrix. Hosted results below are a
separate qualification and do not fill these local cells.

| Preserved platform check | Actual terminal result |
| --- | --- |
| Populated root seed501432 | Core **230/0/1 excluded**, web **130/0/7 excluded** |
| Populated root seed987654 | Core **230/0/1 excluded**, web **130/1/7 excluded** |
| Native runtime/API/concurrency | Core **59/0**, web **10/0** |
| Both consecutive recovery/restart repeats | Core **4/0**, web **1/0** each |
| Compile, format, strict Credo, forced Dialyzer, audit, legacy exclusion | Passed |
| Frozen frontend install, assets and production assembly | Passed; assembly never started |

The platform failure is the unchanged GitHub first-page assertion at
`github_controller_test.exs:56`. The database remains
`samgita_redesign_recovery_repair_test`; no reset, task/history deletion,
pagination/assertion change, fake mapping or activation bypass occurs. Both
recovery/restart repeats pass after the populated suites. The earlier Fake Agent
listener-rebind failure remains without a claimed repair.

Package inventory37 regressions/consistency, namespace/native-sandbox preflight,
driver compile and format pass. Complete default driver seed501432 passes
**670/0** in654.2s; seed987654 finishes **670/1** in646.7s. The new failure is
`native_notification_test.exs:171,187`: after reconnect acknowledgement, the
queued notification's exact stale-session reply is absent from the displayed
mailbox at the unchanged100ms assertion. Reconnect close/gap/open notifications
are present. This log alone does not establish delayed, lost or wrong replies.
It is not classified as harmless flakiness. The bounded diagnosis checks a
same-sender processed-state barrier and preserves exact generation/no-send
requirements; its results are separate from this failed original matrix.

Platform's executable source guard passes. Package's final guard was **not
reached** after the failure. A separate post-failure comparison nevertheless
matches all **1476** saved executable/configuration/workflow files, recorded in
`post-failure-source-check.json`. Documentation-only edits do not change those
inputs. Exact commands/logs remain in
`/tmp/samgita-repair-final-{combined,platform,packages}-v17-20261024/` and adjacent
`.py` runners. Platform/package/combined results SHA256 values are respectively
`2f0182807f8a43e7abb38eb3ae2c6c7bc7755aad6d948689c7fcb96c8e282717`,
`ddbbd4596d750fa4adbc45253c3e9346b4f7c3cb76d2ddeea7cb8ac84dc2e509`,
`8b6e2c0699a04efbf57d773df86ea2b741ede91d9074c3752a1410af6c01b21e`.
No complete-local-matrix, full-compatibility, A11, publication or deployment
claim follows. The notification repair and complete final-source rerun remain
required.

## Hosted checkpoint at 636b2ad

Both workflows are terminal at exact pushed source
`636b2adaaac39a33cc77608883b77d0585ed0212`.
[Foundation 40124365695](https://github.com/gsmlg-opt/Samgita/actions/runs/40124365695)
passes every step: both populated aggregates (**230 core/0/one excluded +
130 web/0/seven excluded** each), restart/rollback **1/0**, neutral core **32/0**,
both neutral outside consumers **1/0** each, neutral WebSocket and native wire
**42/0** each, strict static checks, forced Dialyzer, audits, assets and local
production assembly. The assembled release is never started or published.

[Conformance 40124375328](https://github.com/gsmlg-opt/Samgita/actions/runs/40124375328)
is **failed overall**. Both native execution jobs pass every step: driver
partitions **364/0 + 306/0 = 670/0**, seed501432; native wire **42/0**; native
outside consumer **1/0**; fenced runtime/API/concurrency **59 core + 10 web/zero
failures**; and all **46 explicit isolated profiles, 269/0**, without exclusions
or skipped downstream steps. These include supplied-history imports, actual
session-start provenance and deferred goal inheritance with cold restart.
The app-server frames come from the immutable pin; model/service dependencies
are owned synthetic fixtures. No live provider success follows.

Mandatory completeness passes all **37 inventory regressions** and source
consistency, then fails `--require-verified`: **485 requirements: 0 verified /
462 implemented / 12 missing / 11 blocked; 6,621 contracts: 0 verified /
3,191 implemented / 3,430 missing**. Passing selected journeys does not waive
the remaining behavior, unreachable production emitters, external/OS success
or A11. The [terminal preserved local matrix](#frozen-local-matrix-at-636b2ad)
retains its populated GitHub assertion and new seed987654 queued-notification
failure; hosted seed501432 does not repair them.

The terminal-only read-only collector
`/tmp/samgita-collect-hosted-636b2ad-20261025.py` verifies exact head and completed
status before collecting. Metadata, exact counts/line anchors and complete logs
remain in `/tmp/samgita-hosted-636b2ad-20261025/`. Foundation log SHA256 is
`ae4f0df04fb16c5f7625477d0b88613a47cb7772b96e85751d2aa165a5afc8b6`;
conformance log SHA256 is
`4d4e2ec6cd46a7818860d7b300b4b9bc329e877be6bb9a90741f6e530dcf01e8`.
No tag, package publication, production migration, credential or deployment
change occurs. The full goal remains active and incomplete.

## Frozen local matrix at 96f7130

The v16 combined runner is terminal against executable source
`96f7130f57286c02f8ec2af940b3ca2a462e446d`. All **23 package commands** pass;
all **17 platform commands** run. Both populated root repeats fail the retained
GitHub first-page assertion at `github_controller_test.exs:56`, so the combined
runner exits one. Both source guards match all1465 executable/configuration/
workflow files. No executable source changes during qualification.

| Independent check | Actual terminal result |
| --- | --- |
| Complete default driver, seeds501432/987654 | **665/0** each |
| All42 isolated native profiles, both seeds | **259/0** each |
| Neutral WebSocket, seeds455834/501432/987654 | **42/0** each |
| Native wire and neutral core | **42/0**, **32/0** |
| Native and both neutral outside consumers | **1/0** each |
| Inventory37 regressions/consistency, namespace/sandbox, package compile/format/audits | Passed |

| Preserved platform check | Actual terminal result |
| --- | --- |
| Both populated root repeats | Core **224/0/1 excluded**, web **128/1/5 excluded** each |
| Native runtime/API/concurrency | Core **53/0**, web **8/0** |
| Both consecutive recovery/restart repeats | Core **4/0**, web **1/0** each |
| Compile, format, strict Credo, forced Dialyzer2166 modules, audit, legacy exclusion | Passed |
| Frozen frontend install, assets and production assembly | Passed; assembly never started |

The database remains `samgita_redesign_recovery_repair_test`. No reset, retained
row deletion, assertion/pagination change, fake mapping or activation bypass
occurs. These results preserve the unrelated GitHub failure and do not repair
the earlier Fake Agent listener-rebind failure. Exact commands/logs remain in
`/tmp/samgita-repair-final-{combined,platform,packages}-v16-20261024/`, with
adjacent `.py` runners. Platform results SHA256 is
`3abf0ee27dbe261b67ed222cf33c6ccb78867ddd3ee1e08e3d4e9475c2eec60c`;
package results SHA256 is
`bbaea62444aac089536009ab98fd205802b29e2806c543ac804f963cf2632741`;
combined results SHA256 is
`5e218d5e775d6caeb6ab45964f3a68dde0c10b59626c1781dfe4e815948eb880`.

A later documentation-only [thirty-owner request index](native-envelope-owners-qualification.md#thirty-selected-request-owners-at-96f7130)
binds unchanged native assertions to exact physical owners, bringing contracts
to3171 implemented/3450 missing, zero verified. The frozen run's inventory
remains3141/3480; indexing does not change that historical result. Requirements
stay462 implemented/12 missing/11 blocked, zero verified. New executable units
need final-source local/hosted qualification. Full compatibility, A11, unreachable
emitters and external/OS acceptance remain incomplete; no release or deployment.

## Hosted checkpoint at 96f7130

Both workflows are terminal at exact pushed source
`96f7130f57286c02f8ec2af940b3ca2a462e446d`.
[Foundation 40104781858](https://github.com/gsmlg-opt/Samgita/actions/runs/40104781858)
passes every required step, including both populated aggregates (**224 core/0/one
excluded + 128 web/0/five excluded** each), restart/rollback **1/0**, neutral core
**32/0**, both neutral outside consumers **1/0** each, neutral WebSocket and native
wire **42/0** each, strict static checks, forced Dialyzer, audits, assets and local
production assembly. The assembled release is never started or published.

[Conformance 40104857905](https://github.com/gsmlg-opt/Samgita/actions/runs/40104857905)
is **failed overall**. Both native execution jobs pass: complete default driver
partitions **366/0 + 299/0 = 665/0**, seed501432; native wire **42/0**; native
outside consumer **1/0**; fenced runtime/API/concurrency **53 core + 8 web/zero
failures**; and all **42 explicit isolated profiles, 259/0**, without exclusions
or skipped downstream steps. This includes Admin discovery, stock sleep/steer,
computed goal budgeting and local/Git plugin metadata. Model/service dependencies
in these scenarios are synthetic; actual app-server frames come from the pin.

Mandatory completeness passes all **37 inventory regressions** and consistency,
then fails `--require-verified`: **485 requirements: 0 verified / 462 implemented /
12 missing / 11 blocked; 6,621 contracts: 0 verified / 3,141 implemented / 3,480
missing**. No requirement is waived or promoted by passing selected journeys.
A11, source-unreachable emitters, external/OS success and full compatibility remain
incomplete. Fresh hosted success does not repair the separate retained populated
local database's GitHub first-page assertion or earlier Fake Agent listener failure.

The terminal-only read-only collector
`/tmp/samgita-collect-hosted-96f7130-20261024.py` checks exact head and completion
before collecting logs. Full metadata, counts, line anchors and logs are retained
in `/tmp/samgita-hosted-96f7130-20261024/`. Foundation log SHA256 is
`5674a010369eda0e89a9fa848f0afdabd921b4ec6b52941e35dfad61eba4a0bb`;
conformance log SHA256 is
`e7dd433fd9eec76f4cc1ae037f626b6d6d93f92e75e24a90ee3f980e24389260`.
Documentation records these results without changing the tested executable inputs.
No tag, publication, production migration, credential or deployment change occurs.

## Frozen local matrix at 0bc98a3

The v15 combined runner is terminal against executable source
`0bc98a34686ecda75acf3d03f9ef6e013d6a476b`. All **23 package commands** pass;
all **17 platform commands** run, with one populated-root aggregate failure.
The combined runner exits one. Both executable/configuration/workflow source
guards match all 1,459 recorded files. Documentation-only owner indexes during
the run do not change its executable inputs or retroactively change the earlier
inventory command's counts.

| Independent check | Actual terminal result |
| --- | --- |
| Complete default driver, seeds 501432 / 987654 | **665/0** each |
| All 39 isolated native profiles, both seeds | **253/0** each |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Native wire and neutral core | **42/0**, **32/0** |
| Native and both neutral outside consumers | **1/0** each |
| Inventory regressions/consistency, namespace/sandbox prerequisites, package compile/format/audits | Passed |

| Preserved platform check | Actual terminal result |
| --- | --- |
| Populated root seed501432 | Core **224/0/1 excluded**, web **128/0/5 excluded** |
| Populated root seed987654 | Core **224/0/1 excluded**, web **128/1/5 excluded** |
| Native runtime/API/concurrency | Core **53/0**, web **8/0** |
| Both consecutive recovery/restart repeats | Core **4/0**, web **1/0** each |
| Compile, format, strict Credo, forced Dialyzer, audit, legacy exclusion | Passed |
| Frozen frontend install, assets and production assembly | Passed; assembly never started |

The one failure is unchanged `github_controller_test.exs:56`: the connection
created in that test is absent from the first returned page in the preserved
populated database. No pagination, assertion, GitHub source or existing row is
changed. The database remains `samgita_redesign_recovery_repair_test`, with no
reset, task deletion, fake mapping or activation-guard bypass. Both restart
repeats pass after those populated suites. This does not repair the unrelated
aggregate failure or certify the older Fake Agent listener-rebind behavior.

Exact commands, counts and logs remain in
`/tmp/samgita-repair-final-{combined,platform,packages}-v15-20261024/`.
Platform `results.json` SHA256 is
`a6c9995514bc0c39860106a3878e91c04e1c3a8a389bcc79550fbe0da9849e89`;
package `results.json` SHA256 is
`beadcd30e7344dfc894ab562522db9a9d617e043aeed4666eb82d9aa1b6412ed`.
New executable profiles require another complete final-source local and hosted
qualification. Full compatibility, A11, source-unreachable emitters and
external/OS success remain incomplete. No publication, tag or deployment.

## Hosted checkpoint at 0bc98a3

Both workflows are terminal at exact pushed commit
`0bc98a34686ecda75acf3d03f9ef6e013d6a476b`.
[Foundation 40099601790](https://github.com/gsmlg-opt/Samgita/actions/runs/40099601790)
passes all required steps: both populated aggregates (**224 core/0/one excluded
+ 128 web/0/five excluded** each), restart/rollback **1/0**, independent protocol
packages/consumers, strict checks, forced Dialyzer, audits, assets and production
assembly. No release process is started.

[Conformance 40099682575](https://github.com/gsmlg-opt/Samgita/actions/runs/40099682575)
is **failed overall**, with both native execution jobs successful and mandatory
completeness failed. The default driver partitions pass **366/0 + 299/0 = 665/0**,
seed501432; native wire **42/0**, outside native consumer **1/0** and fenced native
runtime/API/concurrency **53 core + 8 web/zero failures** pass. All **39 explicit
isolated profiles, 253/0**, pass without exclusions or skipped downstream steps.
This includes Git review targets, unanswered-approval cold restart, System-skill
shared cache, queued PNG snapshots and V1/V3 realtime controls.

Completeness passes **37 inventory regressions** and consistency, then fails
`--require-verified`: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked; 6,621 contracts: 0 verified / 3,047 implemented / 3,574 missing**.
The subsequent [source index](native-owner-supplement-qualification.md) first
adds 22 notification/configuration/selective-history owners, then fifteen native
goal owners. Neither unit retroactively changes this run or turns an entry fully
verified. That index brings contracts to **3,084 implemented / 3,537 missing**;
later scoped native units bring the current total to **3,141 implemented /
3,480 missing**. The exact hosted completeness outcome above remains unchanged.

The read-only collector
`/tmp/samgita-collect-hosted-0bc98a3-20261024.py` asserts exact heads and terminal
states. Full logs, per-step counts/anchors and metadata are retained in
`/tmp/samgita-hosted-0bc98a3-20261024/`. Foundation log SHA256 is
`0e7dbbd52a0ab33b01d1bfb78bb1bdf91c2834f64545bcf957034b062b7e95af`;
conformance log SHA256 is
`1eab1a2b8cffafdaf21bbc9725b92f36d10f2a62cd01c9371a9c3bf7f551624e`.

The independent frozen local v15 matrix subsequently finishes with all package
commands passing and its second populated aggregate reproducing the unchanged
GitHub first-page assertion at `github_controller_test.exs:56`; both
recovery/restart repeats pass without resetting the database. Hosted fresh-run
success does not repair or erase that local failure. Full compatibility, A11,
unreachable emitters and external/OS success
remain incomplete; no tag, publication, production migration or deployment.

## Frozen local matrix at 7a5de5e

The v14 combined runner is terminal against executable source
`7a5de5efe50bb7718c64fb0ec1172cfb67eae1d5`. All **17 platform commands** and
**23 independent-package commands** pass; both complete executable/configuration/
workflow source guards match. The combined runner exits zero. The database remains
`samgita_redesign_recovery_repair_test`; no reset, record deletion, fake mapping or
activation-guard bypass occurs.

| Independent check | Actual terminal result |
| --- | --- |
| Complete default driver, seeds 501432 / 987654 | **663/0** each |
| All 35 isolated native profiles, both seeds | **237/0** each |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Native wire and neutral core | **42/0**, **32/0** |
| Native and both neutral outside consumers | **1/0** each |
| Inventory regressions/consistency, namespace/sandbox prerequisites, package compile/format/audits | Passed |

| Preserved platform check | Actual terminal result |
| --- | --- |
| Both consecutive populated root aggregates | Core **224/0/1 excluded**, web **128/0/5 excluded** each |
| Native runtime/API/concurrency | Core **53/0**, web **8/0** |
| Both consecutive recovery/restart repeats | Core **4/0**, web **1/0** each |
| Compile, format, strict Credo, forced Dialyzer, audit, legacy exclusion | Passed |
| Frozen frontend install, assets and production assembly | Passed; assembly never started |

The prior GitHub first-page assertion failure does not reproduce in this run.
Its cause is not repaired: no GitHub test, assertion, pagination, fixture or
retained row was changed. Its older failures remain below. This successful
checkpoint does not establish a listener-rebind repair or override completeness,
A11, source-unreachable emitters or unavailable external/OS acceptance.

Exact commands, terminal exits, logs and source hashes are retained in
`/tmp/samgita-repair-final-{combined,platform,packages}-v14-20261024/`, with adjacent
`.py` runners. Platform results SHA256 is
`e41c0d0dc61f11924d836437a6409d4cb336b5a1d502e742218199029e564de4`;
package results SHA256 is
`999d3d5c2531166683e5b3b9e5149562440aa6e7c60a51d8a958a4b850ea5bbc`.
The combined results SHA256 is
`b2c60393564662bdd5f308ca9beff4f7e28845387805e0fbd5964d085211756e`.
Subsequent executable edits require another complete final-source matrix.

## Hosted checkpoint at 7a5de5e

Both workflows reached terminal status at exact pushed source
`7a5de5efe50bb7718c64fb0ec1172cfb67eae1d5`.
[Foundation 40092693712](https://github.com/gsmlg-opt/Samgita/actions/runs/40092693712)
passes every required step. Both populated aggregates pass **224 core/0/one
excluded + 128 web/0/five excluded**, seeds 985029 and 951067. Restart/rollback
passes **1/0**; neutral core **32/0**, both neutral outside consumers **1/0**
each, neutral WebSocket **42/0** and native wire **42/0** pass. Compile, format,
strict Credo, forced Dialyzer, audits, assets and production assembly pass.

[Conformance 40092735407](https://github.com/gsmlg-opt/Samgita/actions/runs/40092735407)
is **failed overall**, with both execution jobs successful and the required
completeness job failed. The selected actual-binary/platform job passes native
wire **42/0**, both complete default-driver partitions **364/0 + 299/0 = 663/0**
at 501432, native outside consumer **1/0**, and native runtime/API/concurrency
**53 core + 8 web / zero failures** at 49576. All **35 isolated native profiles,
237/0**, pass with no exclusions. No consumer/platform step is skipped.

Completeness passes **37 inventory regressions** and consistency, then fails
`--require-verified`: **485 requirements: 0 verified / 462 implemented / 12 missing /
11 blocked**; its source has **6,621 contracts: 0 verified / 2,963 implemented /
3,658 missing**. Later documentation-only indexing of five native review owners
and 52 synthetic legacy owners does not retroactively change this hosted ledger.
It supplies no real legacy emitter or fully verified requirement.

The read-only collector
`/tmp/samgita-collect-hosted-7a5de5e-20261024.py` asserts exact heads and terminal
states. Full logs, per-step counts/anchors, metadata and hashes are retained in
`/tmp/samgita-hosted-7a5de5e-20261024/`. Foundation log SHA256 is
`bc75bb1bf08b12d6756f07b3a27355af2b57ecab32b8b3612c0319b7b32f59e1`;
conformance log SHA256 is
`546089e01a3b7d4f6124fe2a7600c213e46a3d2123442ec8cdc9e25f557dd369`.
These local evidence artifacts are not published packages. No release, tag,
publication, production migration or deployment follows.

## Frozen local matrix at 5c22159

The v13 combined runner is terminal against executable source
`5c221594fa19c0d686cba63f387f2bee6f16f70b`. All **23 independent-package
commands passed**. All **17 platform commands ran**, with only the first
populated-root aggregate failing. Both complete executable/configuration/workflow
source guards match the current documentation head `7324d90`; no executable
change occurred during validation. The combined runner exited one and retains
the aggregate failure. There was no reset, task deletion or guard bypass.

| Independent check | Actual terminal result |
| --- | --- |
| Complete default driver, seeds 501432 / 987654 | **653/0** each |
| All 31 isolated native profiles, both seeds | **214/0** each |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Native wire and neutral core | **42/0**, **32/0** |
| Native and both neutral outside consumers | **1/0** each |
| Inventory regressions/consistency, namespace/sandbox prerequisites, package compile/format/audits | Passed |

| Preserved platform check | Actual terminal result |
| --- | --- |
| Populated root, seed 501432 | Core **224/0/1 excluded**, web **128/1/5 excluded** |
| Consecutive root, seed 987654 | Core **224/0/1 excluded**, web **128/0/5 excluded** |
| Native runtime/API/concurrency | Core **53/0**, web **8/0** |
| Consecutive recovery/restart, both seeds | Core **4/0**, web **1/0** each |
| Compile, format, strict Credo, forced Dialyzer, audit, legacy exclusion | Passed |
| Frozen frontend install, assets and production assembly | Passed; assembly never started |

The only aggregate failure remains `github_controller_test.exs:56` (test
declared at 39): the retained populated database does not guarantee a newly
inserted connection is on page one. No GitHub fixture, pagination, assertion or
retained row is changed. This is separate from activation/restart recovery.

Exact commands, terminal exits, logs and source hashes are retained in
`/tmp/samgita-repair-final-{combined-v13,platform-v11,packages-v13}-20261024/`,
with adjacent `.py` runners. Platform results SHA256 is
`432581ea27e502d7e376980478531b82cfc76148a132736a7a2f4701f9bef094`;
package results SHA256 is
`1e1e8662e0cd4ab5839ec381827bd54237d8a8aaea34b55ae165ee8d5769e353`.
The documentation-only `7324d90` foundation repeat
[40087442409](https://github.com/gsmlg-opt/Samgita/actions/runs/40087442409)
also reached terminal success. Neither this checkpoint nor the hosted execution
success below completes compatibility, A11, source-unreachable or external/OS
acceptance. No publication, tag or deployment follows. Executable work resumes
only after this terminal checkpoint.

## Hosted checkpoint at 5c22159

Both workflows reached terminal status at exact pushed executable source
`5c221594fa19c0d686cba63f387f2bee6f16f70b`.
[Foundation 40086202012](https://github.com/gsmlg-opt/Samgita/actions/runs/40086202012)
passed every required step. Both populated aggregates passed **224 core/0/one
excluded + 128 web/0/five excluded**, seeds `329070` and `984655`.
Restart/rollback passed **1/0**; neutral core **32/0**, both outside consumers
**1/0** each, neutral WebSocket **42/0** and native wire **42/0** passed.
Strict checks, forced Dialyzer, audits, assets and production assembly passed.
The assembled release was not started or published.

[Conformance 40086270651](https://github.com/gsmlg-opt/Samgita/actions/runs/40086270651)
is **failed overall**, with two successful execution jobs and the required failed
completeness job. The selected actual-binary/platform job passed native wire
**42/0**, both complete default-driver partitions **330/0 + 323/0 = 653/0**
at `501432`, the native outside consumer **1/0**, and native runtime/API/
concurrency **53 core + 8 web / zero failures** at `664202`. No downstream
consumer/platform step was skipped. The isolated-native job passed all **31
required profiles, 214/0**, with no exclusions, including the newly required
actual-native BEM profile. The MCP cleanup-marker assertions and production
guardians remain intact; this new-source run no longer has the previous hosted
MCP fixture-close failure. The older failure remains recorded below.

The completeness job passed **37 inventory regressions** and consistency, then
failed `--require-verified` with **485 requirements: 0 verified / 462 implemented /
12 missing / 11 blocked**. Its historical ledger has **6,621 contracts: 0 verified /
2,795 implemented / 3,826 missing**. Later documentation-only owner indexing at
`7324d90` raises the scoped implemented count to 2,821 without changing executable
source or retroactively changing this hosted report. Selected successful native
jobs do not close completeness, source-unreachable contracts, external/OS success
or A11.

The read-only collector
`/tmp/samgita-collect-hosted-5c22159-20261024.py` asserts exact heads and terminal
states before downloading full logs. Metadata, parsed counts, per-step line
anchors and complete logs are retained in `/tmp/samgita-hosted-5c22159-20261024/`.
The foundation log SHA256 is
`f8c293705e8cd01e42a849a9936b4bfc461215dd51f89d4bfe95370c6b32751d`;
the conformance log SHA256 is
`49f0f3f01809932a15f6d4ceeb6bca2a82d6a47414a82332bb0a2f7eec364b8c`.
These are local retained evidence artifacts, not published package artifacts.
No tag, release, deployment or production-readiness claim follows.

## Frozen local matrix at 0629d92

The v12 combined runner reached terminal status against executable source
`0629d92cd20fea196de729da3b4fa77747003080`. Both executable/configuration/
workflow hash guards passed. All **23 independent-package commands passed**;
the platform half ran all **17 commands** and failed its first populated-root
aggregate. The combined matrix therefore failed, rather than suppressing that
result. No database reset, task deletion, guard bypass or test exclusion was
introduced for this repeat.

| Independent check | Actual terminal result |
| --- | --- |
| Complete default driver, seeds 501432 / 987654 | **647/0** each |
| All 30 isolated native profiles, both seeds | **208/0** each |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Independent native wire | **42/0** |
| Native and both neutral outside consumers, package compile/format/audits | Passed |
| Inventory regressions/consistency, namespace and native sandbox prerequisites | Passed |

| Preserved platform check | Actual terminal result |
| --- | --- |
| Populated root, seed 501432 | Core **224/0/1 excluded**, web **128/1/5 excluded** |
| Consecutive root, seed 987654 | Core **224/0/1 excluded**, web **128/0/5 excluded** |
| Native runtime/API/concurrency | Core **53/0**, web **8/0** |
| Consecutive recovery/restart, both seeds | Core **4/0**, web **1/0** each |
| Compile, full format, strict Credo, forced Dialyzer and audit | Passed |
| Legacy exclusion, frozen frontend install, assets and production assembly | Passed; assembly never started |

The retained failure is the first-page assertion at
`github_controller_test.exs:56` (test declared at 39): a newly inserted connection
need not appear on the first page of this retained populated database. It is not
the repaired activation/restart failure. The GitHub test, pagination and retained
rows were not changed; its actual failure remains an aggregate gate. Later
success at a different seed does not erase it.

Exact commands, per-command logs, source hashes and terminal exits are in
`/tmp/samgita-repair-final-{combined-v12,platform-v10,packages-v12}-20261024/`;
the corresponding `.py` runners are adjacent to those directories. These local
successes do not resolve the separately observed hosted MCP teardown failure
below. Executable edits resume only after this terminal checkpoint. Completeness,
A11, unreachable legacy branches and external/OS success remain incomplete.

## Hosted checkpoint at 3dcf64b

Both workflows reached terminal state at exact pushed documentation head
`3dcf64b43d0f4a288bcff0b27af33c9e516177e1`; executable source is unchanged
from `0629d92cd20fea196de729da3b4fa77747003080`.
[Foundation 40082783873](https://github.com/gsmlg-opt/Samgita/actions/runs/40082783873)
passed all required steps, including both populated aggregates (**224 core/0/
one excluded + 128 web/0/five excluded** each), restart/rollback **1/0**,
independent packages/consumers, strict checks, forced Dialyzer, audits, assets
and production assembly. This is not publication or deployed behavior.

[Conformance 40082826118](https://github.com/gsmlg-opt/Samgita/actions/runs/40082826118)
is **failed overall**. The independent native wire passed **42/0** and driver
partition 1 passed **340/0**, seed `501432`. Partition 2 ran **307 tests / one
failure** at the same seed: M7 in `native_mcp_control_lifecycle_test.exs:315`
fails its setup `on_exit` assertion at line 69 because the fixture journal has
no `fixture_closed` marker. The reported stack is in cleanup; it does not
identify a failed stream cancellation assertion or establish a root cause.
The native outside-consumer and platform steps were skipped after this failure.
Do not count them as passed or the whole driver as green.

The separate isolated-native job passed all **30 required profiles, 208/0**,
with no exclusions, including the new missing/null/empty differential cases.
The required completeness job failed correctly with **485 requirements:
0 verified / 462 implemented / 12 missing / 11 blocked**. Its original ledger
has **6,621 contracts: 0 verified / 2,693 implemented / 3,928 missing**. Later
documentation-only evidence indexing does not change those historical counts.
No deadline, assertion, sandbox, cleanup or completeness gate was relaxed.

Exact terminal metadata, complete raw logs, derived counts/line anchors and
SHA256 fingerprints are retained in `/tmp/samgita-hosted-3dcf64b-20261024/`,
collected by `/tmp/samgita-collect-hosted-3dcf64b-20261024.py`. The collector
requires both exact heads and terminal statuses before download. The
[MCP ordering repair](mcp-cleanup-order-qualification.md) subsequently reproduces
the missing live-caller marker before repair and passes the same regression plus
**9/0** complete MCP cases at `501432` and **29/0** MCP/process cleanup cases at
`987654`. It moves graceful fixture acknowledgement before caller death without
changing production guardians, deadlines or existing cleanup assertions. The
exact interrupted hosted shutdown stage remains unknown; new-source hosted
qualification is still required. A11,
source-unreachable branches, real external/OS success and complete compatibility
remain incomplete. No tag, release, package publication or deployment follows.

## Hosted checkpoint at 67d2c32

Both workflows reached terminal status at exact pushed source
`67d2c32dd85dc90eec57060a8fe720e769d8851d`.
[Foundation 40078557857](https://github.com/gsmlg-opt/Samgita/actions/runs/40078557857)
passed. It includes both populated aggregates (**224 core/0/one excluded +
128 web/0/five excluded** each), restart/rollback **1/0**, neutral core **32/0**,
both outside consumers **1/0** each, neutral WebSocket and native wire **42/0**
each, required strict checks/audits, forced Dialyzer, assets and assembly.

[Conformance 40078574020](https://github.com/gsmlg-opt/Samgita/actions/runs/40078574020)
is **failed overall**. Its selected actual-binary/platform job passed native
wire **42/0**, both complete driver partitions (**331/0 + 312/0 = 643/0**),
the native outside consumer **1/0**, and native runtime/API/concurrency
**53 core + 8 web / zero failures**. The separate isolated-native job passed
all **30 required profiles, 205/0**, with no exclusions. Partition 2, the outside
consumer and platform journey actually ran; they were not inferred from the
first partition. The ripgrep prerequisite repair is now observed passing.

The independent required evidence job failed correctly: **485 requirements:
0 verified / 462 implemented / 12 missing / 11 blocked**. Inventory consistency
also records **6,621 contracts: 0 verified / 2,667 implemented / 3,954 missing**.
No required gate, original eight-minute partition deadline, assertion,
authorization boundary or sandbox policy was relaxed. Selected native success
does not close completeness, A11, unavailable external services/OS profiles or
the source-proven unreachable legacy contracts.

Terminal metadata, complete raw logs, derived counts, line references and
SHA256 fingerprints are retained in `/tmp/samgita-hosted-67d2c32-20261024/`.
Collection used `/tmp/samgita-collect-hosted-67d2c32-20261024.py`, which checked
both exact heads and terminal states before downloading. This is hosted evidence
for the pinned native binary with synthetic dependencies where declared, not
real provider integration, package publication or deployed behavior.

## Frozen local matrix at 67d2c32

The v11 combined runner serializes the preserved-platform and independent-package
matrices against `67d2c32dd85dc90eec57060a8fe720e769d8851d`. Both halves reached
terminal status with their executable/configuration/workflow hash guards passing.
All **23 package commands passed**. The platform half finished all **17 commands**
and is **failed**, because both populated aggregate runs retain the same GitHub
first-page assertion failure. The parent reports a failed matrix; it does not
erase that exit status when the independent package checks pass.

| Independent package check | Actual outcome |
| --- | --- |
| Inventory regressions / consistency | **37/0**; 485 requirements, 6,621 contracts, zero verified |
| Namespace and pinned native sandbox prerequisites | Passed |
| Complete default driver, seeds 501432 / 987654 | **643/0** each |
| All 30 explicit isolated profiles, both seeds | **205/0** each |
| Native / both neutral outside consumers | **1/0** each; neutral core **32/0** |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Independent native wire | **42/0** |
| Package compile, format and strict dependency audits | Passed |

| Platform check | Actual outcome |
| --- | --- |
| Preserved root aggregates, seeds 501432 / 987654 | Core **224/0/1 excluded**; web **128/1/5 excluded** each |
| Native runtime/API/concurrency journeys | Core **53/0**, web **8/0** |
| Consecutive recovery/restart runs, both seeds | Core **4/0**, web **1/0** each |
| Compile, formatting, strict Credo, forced Dialyzer, dependency audit | Passed |
| Legacy exclusion, frozen frontend install, assets, production assembly | Passed |

The unchanged assertion is `github_controller_test.exs:56`, in the test declared
at line 39: the newly created connection is absent from the first default page
when prior fixtures remain. No GitHub pagination, fixture, assertion or database
record was changed. Fresh hosted success cannot erase this aggregate failure.
The database `samgita_redesign_recovery_repair_test` remains populated, with no
reset, fake mapping, activation bypass, automatic replay or task acceptance.
The successful production assembly was never started.

Exact commands and raw logs are retained in
`/tmp/samgita-repair-final-platform-v9-20261024/` and
`/tmp/samgita-repair-final-packages-v11-20261024/`; the serialized parent is
`/tmp/samgita-repair-final-combined-v11-20261024.py`, with both exit statuses in
its adjacent `results.json`. Documentation-only recording does not change this
tested executable source. Subsequent executable additions require a new final
matrix. These outcomes do not close A11 or full compatibility. No tag,
publication or deployment.

## Frozen independent matrix at 5cd40c9

The explicitly owned v10 runner reached both terminal results at unchanged
`5cd40c940093eab63fefe5003f1039098ece0a37`, with no concurrent local native/Mix
validation or executable/config changes. The package matrix passed all commands;
the independent platform matrix failed its two populated aggregate runs.

| Check | Actual outcome |
| --- | --- |
| Inventory regressions / consistency | 37/0; 485 requirements and 6,621 contracts, zero verified |
| Required namespace and native sandbox probes | Passed |
| Complete default driver, seeds 501432 / 987654 | **621/0** each |
| All 30 isolated native profiles, both seeds | **205/0** each |
| Independent native / neutral outside consumers | Passed |
| Neutral WebSocket, seeds 455834 / 501432 / 987654 | **42/0** each |
| Independent native wire | **42/0** |
| Package compiles, formats and strict audits | Passed |
| Preserved root aggregate, both seeds | Core **224/0/1 excluded**; web **128/1/5 excluded** each |
| Native platform/API/race journeys | Core **53/0**, web **8/0** |
| Two consecutive recovery/restart seeds | Core **4/0**, web **1/0** each |
| Root compile/format/strict Credo/forced Dialyzer/audit | Passed |
| Legacy exclusion, frozen frontend install, assets, production assembly | Passed |

Both aggregate failures are the unchanged `github_controller_test.exs:56`
assertion (test declared at line 39): a newly registered connection is absent
from the first default page on this populated database. This is independent of
the passing recovery/activation tests; neither repeat was counted green.
The named database `samgita_redesign_recovery_repair_test` was preserved, with
no reset, record removal, fake mapping, activation bypass or automatic replay.
The production assembly was never started. No tag/publication/deployment follows.

Exact commands, times, source guards and raw logs are retained in
`/tmp/samgita-repair-final-packages-v10-20261024/`,
`/tmp/samgita-repair-final-platform-v8-20261024/` and
`/tmp/samgita-repair-final-combined-v10-20261024/results.json`.
These outcomes qualify that frozen snapshot; new executable tests require their
own final-source matrix. A11 and complete conformance remain incomplete.

## Hosted prerequisite checkpoint at 5cd40c9

Both terminal workflows used exact source
`5cd40c940093eab63fefe5003f1039098ece0a37`. Foundation
[40073298832](https://github.com/gsmlg-opt/Samgita/actions/runs/40073298832)
passed; conformance
[40073376712](https://github.com/gsmlg-opt/Samgita/actions/runs/40073376712)
failed. Native protocol passed **42/0**. Driver partition 1 reported **340 tests,
2 failures**, seed `501432`: both content-search cases failed setup with
`BLOCKED_ENV: ripgrep required`. Partition 2, outside consumer and platform
journeys were skipped. The separate 30-profile job passed **205/0**. Required
completeness failed with all **485 requirements** unverified; source consistency
recorded **462 implemented / 12 missing / 11 blocked** requirements and
**2,473 implemented / 4,148 missing** contracts, zero verified.

The selected-conformance job now explicitly installs and checks distribution
`ripgrep`. The fixture still discovers only that executable for its private
PATH and fails when it is absent. No assertion, deadline, capability, sandbox
policy or required gate changes. A subsequent terminal hosted run must validate
this environment repair; the preceding run does not qualify the changed workflow.
Collection metadata, line-anchored failure/count excerpts and immutable raw logs
are retained in `/tmp/samgita-hosted-5cd40c9-20261024/`.

Local validation from `apps/samgita_codex_driver`, with `CODEX_BINARY` set to the
pinned `tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`, ran
`devenv shell --no-tui -- mix test test/native_search_projections_test.exs --seed 501432`:
**2/0**. An initial invocation omitted that required variable and failed setup
with `BLOCKED_ENV: immutable CODEX_BINARY required`; no native scenario ran in
that invocation. This is local regression evidence, not hosted validation of
the package-install step.

## Combined-source platform checkpoint at e39ca5f

The input/form additions are committed and pushed at
`e39ca5f8c7738c0f6fd1188de555e89dd1edb6a9`; local HEAD, origin/main and the live
remote ref matched. The only untracked file is the user-supplied repair prompt,
which is deliberately excluded from commits.

The v7 preserved-platform runner completed **17 commands** against this exact
executable source and passed its end-of-run source guard. The same retained
`samgita_redesign_recovery_repair_test` database was neither reset nor trimmed.
Seed `501432` passed **224 core/0/one excluded + 128 web/0/five excluded**.
Seed `987654` passed core and failed **one of 128 web cases**: the retained
`github_controller_test.exs:56` first-page assertion, in the test declared at
line 39. This remains an aggregate failure. No GitHub code, pagination, fixture,
assertion or database contents were changed to hide it.

Real native runtime/API/races passed **53 core + 8 web / zero failures**.
Both consecutive activation/recovery/restart seeds passed **4 core + 1 web /
zero failures**. Genuine unmapped work remains blocked; no dispatch, journal or
review/acceptance protection is bypassed. Warning-free compile, format, strict
Credo, forced Dialyzer, legacy tests/scan, audit, frozen web dependencies, assets
and production dependencies/assets/assembly all passed. The runner returned
nonzero for the one actual aggregate failure. Complete commands, source hashes,
exits and logs: `/tmp/samgita-repair-final-platform-v7-20261024/`. The assembly
at `/tmp/samgita-repair-final-prod-v7-20261024/rel/samgita` was never started.

The independent-package v9 matrix started serially after that platform runner,
but its command group terminated with **exit 143** during default driver seed
`501432`, without an ExUnit summary or a recorded command result. The cause is
unestablished. Its inventory/prerequisite/compile/format commands passed; the
partial default run and all unexecuted later commands remain **incomplete**.
The tail contains guardian broken-pipe cleanup diagnostics after the parent
disappeared; these do not establish a test assertion failure or its cause.
Read-only process inspection found no remaining Codex/fixture processes from
that group. Original logs and results remain in
`/tmp/samgita-repair-final-packages-v9-20261024/` and
`/tmp/samgita-repair-final-combined-v9-20261024/`; no partial pass is claimed.
Subsequent executable additions require a new complete matrix.

Hosted [CI 40071661625](https://github.com/gsmlg-opt/Samgita/actions/runs/40071661625)
and [conformance 40071678362](https://github.com/gsmlg-opt/Samgita/actions/runs/40071678362)
are terminal at the same exact head. CI passed its first and populated-repeat
seeds (**224 core/0/one excluded + 128 web/0/five excluded** each),
restart/rollback **1/0**, independent packages/consumers, strict checks, audits,
assets and production assembly. This hosted success does not erase the retained
local first-page failure above.

Conformance is **failed overall** at its required completeness step. Both
execution jobs passed: native wire **42/0**, default driver partitions
**325/0 + 286/0 = 611/0**, all 30 isolated profiles **205/0**, native outside
consumer **1/0**, and platform **53 core + 8 web/0**. Driver partitions and
profiles used seed `501432`; consumer/platform used `578177`/`979423`.
The driver-suite count includes different test layers, not 611 individually
claimed real-binary cases. Inventory regressions **37/0** and source consistency
passed. The strict gate exited one: `unverified requirements remain in entries`.
Its matching ledger was **485 requirements: 462 implemented / 12 missing /
11 blocked; zero verified**, and **6,621 contracts: 2,347 implemented / 4,274
missing; zero verified**. Terminal metadata, exact counts and complete logs:
`/tmp/samgita-hosted-e39ca5f-20261024/`. Later additions need new final-source
checks. A11, source-unreachable paths, external/OS success and complete evidence
remain incomplete. No tag, publication, deployment or production migration
occurred.

## Hosted and independent-package checkpoint at c3dda0c

Exact source `c3dda0c2b89edfe821c63bc4808fd3e307ecbccf` completed the normal
hosted workflows. [Foundation 40068650688](https://github.com/gsmlg-opt/Samgita/actions/runs/40068650688)
passed both seeds (**224 core/0/one excluded + 128 web/0/five excluded** each),
restart/rollback **1/0**, neutral core **32/0**, both outside consumers **1/0**
each, neutral WebSocket/native wire **42/0** each, strict checks, audits, assets
and production assembly.

[Conformance 40068677611](https://github.com/gsmlg-opt/Samgita/actions/runs/40068677611)
is **failed overall**. Its selected actual-binary/platform job passed native
wire **42/0**, both default driver partitions (**317/0 + 271/0 = 588/0**), the
native outside consumer **1/0**, and native platform/API/races **53 core + 8 web /
zero failures**. The isolated native job passed all **30 profiles, 205/0**.
The unchanged eight-minute partition deadlines remained in place. The required
completeness job failed with **485 requirements: 462 implemented / 12 missing /
11 blocked; zero verified**, and **6,621 contracts: 2,220 implemented / 4,401
missing; zero verified**. Exact head metadata and complete logs:
`/tmp/samgita-hosted-c3dda0c-20261024/`.

The local v8 independent-package runner then passed **23 commands** and its
end-of-run executable/configuration/workflow hash guard. Default driver seeds
`501432` and `987654` passed **588/0**, 521.3/520.3s; all 30 profiles passed
**205/0**, 408.4/407.9s. Native and neutral outside consumers passed;
WebSocket seeds `455834`, `501432`, `987654` each passed **42/0**, and native
wire passed **42/0**. Inventory regressions **37/0**, inventory consistency,
namespace/native-sandbox prerequisites, package compile/format and all relevant
strict dependency audits passed. Full commands, hashes, exits and logs:
`/tmp/samgita-repair-final-packages-v8-20261024/`.

The following source-reviewed indexing adds **63 exact contracts**, without
executable changes or verified promotions:
[47 Project/thread inputs](project-thread-input-fields-qualification.md) and
[16 notification/error/plugin fields](notification-error-plugin-fields-qualification.md).
The resulting field ledger is **2,283 implemented / 4,338 missing; zero
verified**; the requirement ledger is unchanged. These counts do not rewrite
the historical hosted evidence. Subsequent executable tests require a fresh
final-source local and hosted matrix. The last retained populated-database
aggregate still has the unchanged GitHub first-page failure; A11,
upstream-unreachable emitters, external/OS success and full compatibility remain
incomplete. No release, publication or deployment occurred.

## Hosted and populated-platform checkpoint at 3fbaf74

Exact pushed source `3fbaf74d9eec8a9cdf0b391ec940b7b324a94b62` completed the
normal hosted workflows. [Foundation 40064532193](https://github.com/gsmlg-opt/Samgita/actions/runs/40064532193)
passed both populated seeds (**224 core/0/one excluded + 128 web/0/five excluded**
each), restart/rollback **1/0**, neutral core **32/0**, both outside consumers
**1/0** each, neutral WebSocket and native wire **42/0** each, all strict
checks/audits, forced Dialyzer, assets and local production assembly.

[Conformance 40064648290](https://github.com/gsmlg-opt/Samgita/actions/runs/40064648290)
remains **failed overall**. Its selected actual-binary/platform job passed native
wire **42/0**, both full driver partitions (**297/0 + 250/0 = 547/0**), the native
outside consumer **1/0**, and native platform/API/concurrency **53 core + 8 web /
zero failures**. All **30 explicit isolated profiles, 205/0**, passed in the
separate native job. Both original eight-minute driver-partition deadlines
remain unchanged. The required evidence gate failed with **485 requirements:
462 implemented / 12 missing / 11 blocked; zero verified**. The matching manifest
also retains **6,621 contracts: 2,165 implemented / 4,456 missing; zero verified**.
Terminal metadata and complete logs: `/tmp/samgita-hosted-3fbaf74-20261024/`.

These hosted results include the prediction durable-metadata precondition,
metadata plugin-startup isolation, managed-network metadata and persisted
Unicode-span tests. They supersede the two selected failures at `6dcd341` only
for this tested source and environment; their original failures remain below.
Plugin startup is disabled in the affected metadata module. No suite-wide
startup/egress-isolation claim is made for other fixtures.

The local v6 platform runner completed all **17 commands** at the same source,
with its end-of-run executable/configuration/workflow hash guard passing. The
preserved `samgita_redesign_recovery_repair_test` database was neither reset nor
trimmed. Root seed `501432` passed **224 core/0/one excluded + 128 web/0/five
excluded**. Seed `987654` passed core but failed **one of 128 web tests** at
`github_controller_test.exs:56`: the unchanged default-first-page assumption for
a newly created connection still encounters retained populated fixtures. This
is an **aggregate failure**; no page size, fixture, assertion or GitHub code was
changed. Fresh hosted success does not erase the local failure.

Native runtime/API/race cases passed **53 core + 8 web / zero failures**.
Consecutive recovery/activation and restart checks passed **4 core + 1 web /
zero failures**, at both seeds. Genuine unresolved work remains fail-closed.
Compile, format, strict Credo, legacy tests/scan, forced Dialyzer, strict audit,
frozen web dependencies, assets and production dependencies/assets/assembly all
passed. The runner exits nonzero for the retained aggregate failure. Exact
commands, source hashes, exits and logs:
`/tmp/samgita-repair-final-platform-v6-20261024/`. The assembly at
`/tmp/samgita-repair-final-prod-v6-20261024/rel/samgita` was never started.

The v7 independent-package runner completed **23 commands / zero failures**,
with its end-of-run executable/configuration/workflow hash guard passing.
Default driver seeds `501432` and `987654` passed **547/0** each,
463.3/466.6s. All 30 profiles together passed **205/0** at both seeds,
402.3/408.8s. The native outside consumer passed **1/0**; neutral core and
both outside consumers passed **32/0 + 1/0 + 1/0**. Neutral WebSocket seeds
`455834`, `501432` and `987654` passed **42/0** each; native wire passed
**42/0**. Compile/format, strict dependency audits, namespace/native-sandbox
prerequisites and 37 inventory regressions/checks passed. Commands, tool/source
hashes, exits and complete logs:
`/tmp/samgita-repair-final-packages-v7-20261024/`.

The subsequent documentation-only timestamp-owner indexing advances two exact
contracts to scoped implemented: current totals are **2,167 implemented / 4,454
missing contracts, zero verified**. The hosted run above retains its historical
2,165 count. This indexing changes no executable source. A11, source-unreachable
legacy paths, real external/OS success, the local aggregate failure and complete
compatibility remain incomplete. No release, tag, publication, production
migration or deployment occurred.

## Hosted checkpoint at 6dcd341 and new fixture repairs

Exact source `6dcd341f4c58296e5eeda739e5f9207b1056a24a` reached terminal
hosted results. [Foundation 40063212399](https://github.com/gsmlg-opt/Samgita/actions/runs/40063212399)
passed both populated seeds (**224 core/0/one excluded; 128 web/0/five excluded**
each), restart/rollback, neutral core **32/0**, both outside consumers **1/0**,
neutral WebSocket and native wire **42/0** each, all strict checks/audits,
forced Dialyzer, assets and local production assembly.

[Conformance 40063234384](https://github.com/gsmlg-opt/Samgita/actions/runs/40063234384)
failed overall. All **30 explicit profiles, 205/0**, passed. The selected job
passed native wire **42/0** and driver partition one **285/0**, then failed
partition two **254/one failure**. Outside-consumer and native-platform steps
did not run. The failure is the
[metadata plugin-startup race](thread-metadata-qualification.md#background-plugin-fixture-repair),
not an owned-process cleanup failure. The separate required evidence gate also
failed: **485 requirements: 462 implemented / 12 missing / 11 blocked;
6,621 contracts: 2,132 implemented / 4,489 missing; zero verified**. Complete
terminal metadata/logs: `/tmp/samgita-hosted-6dcd341-20261024/`.

The frozen local v6 package attempt ended **539/one failure**, seed `501432`,
507.5s, and aborted before its remaining package/profile commands. Its distinct
[prediction timestamp precondition](prediction-boundary-qualification.md#durable-state-precondition-repair)
is repaired by materializing durable metadata while retaining complete timestamp
and history-byte equality. Its original failure is preserved in
`/tmp/samgita-repair-final-packages-v6-20261024/`. New metadata/prediction repeats
pass **13/0** at both seeds with all scoped static checks; network/span units
have their separately recorded native results. None substitutes for the new
combined-source, preserved-database and hosted final matrix. A11, immutable
non-emitting legacy paths, external/OS acceptance and the complete goal remain
incomplete; no release/tag/publication/deployment occurred.

## Hosted checkpoint at e4dd2be

Exact pushed source `e4dd2be02980f09b7f3462626b091f3f40c45f46` completed both
normal workflows. [Foundation 40061306170](https://github.com/gsmlg-opt/Samgita/actions/runs/40061306170)
passed both populated-database seeds (**224 core/0/one excluded + 125 web/0/two
excluded**, each), dedicated restart/rollback **1/0**, neutral core **32/0**,
both outside consumers **1/0** each, WebSocket **42/0**, native wire **42/0**,
strict checks/audits, forced Dialyzer, assets and local production assembly.

[Conformance 40061334993](https://github.com/gsmlg-opt/Samgita/actions/runs/40061334993)
finished **failed overall**. Its selected actual-binary/platform job passed
native wire **42/0**, both full default-driver partitions (**274/0 + 234/0 =
508/0**), outside consumer **1/0**, and native platform **53 core + 5 web /
zero failures**. All **30 explicit profiles, 205/0**, passed in the separate
isolated-native job. Original eight-minute partition deadlines remain unchanged.
The required evidence job failed: **485 requirements: 462 implemented / 12
missing / 11 blocked; 6,621 contracts: 2,099 implemented / 4,522 missing; zero
verified**. Terminal metadata and full logs:
`/tmp/samgita-hosted-e4dd2be-20261024/`.

These results include the thirteen managed-policy cases and precede the new
eleven model-default/attribution cases. They are selected real-binary evidence,
not complete compatibility, A11 closure, real provider acceptance or a release.
Later executable test additions need their own combined-source/hosted checks.

## Frozen populated-platform checkpoint at e4dd2be

The v5 platform runner executed all seventeen required checks with a passing
end-of-run source hash guard. The preserved
`samgita_redesign_recovery_repair_test` database was neither reset nor trimmed.
Seed `501432` passed **224 core/0/one excluded + 125 web/0/two excluded**.
Seed `987654` passed core but failed **one of 125 web tests**:
`github_controller_test.exs:56` expects a newly created connection on the default
first page. Retained concurrency fixtures exceed that page; UUID ordering
determines placement. This pre-existing pagination assertion remains an
**aggregate failure**. No GitHub behavior/test, pagination limit, fixture record
or assertion was changed to obtain green results.

Native runtime/API/race cases passed **53 core + 5 web / zero failures**.
Recovery/activation plus restart passed **4 core + 1 web / zero failures** in
both consecutive seeds. Genuine unresolved work remains fail-closed. Compile,
format, strict Credo, legacy tests/scan, forced Dialyzer, strict dependency audit,
frozen web dependencies, assets and production dependencies/assets/assembly all
passed. The runner still exits nonzero for the retained aggregate failure.
Commands, exits, source hashes and complete logs:
`/tmp/samgita-repair-final-platform-v5-20261024/`.
The unpublished assembly at
`/tmp/samgita-repair-final-prod-v5-20261024/rel/samgita` was never started.
Fresh hosted success does not supersede the preserved local failure. These
results precede the new attribution/model-default tests; final source needs its
own complete required matrix. No tag, publication, deployment or live-data
change occurred.

## Frozen independent-package checkpoint before managed policy

The v5 runner completed **23 commands / zero failures** with executable,
configuration and workflow hashes frozen at `0cb70cc`; subsequent `fbcbd79` and
`3904bac` changed documentation/manifest only. Its end-of-run source guard passed.
Default driver seeds `728846` and `987654` passed **495/0** each, 441.0/423.6s.
All 30 profiles together passed **205/0** at seeds `501432` and `987654`,
436.0/450.0s, with the corrected explicit private Secret Service tool paths.
Native outside consumer passed **1/0**; neutral core and both outside consumers
passed **32/0 + 1/0 + 1/0**. Neutral WebSocket seeds `455834`, `501432` and
`987654` passed **42/0** each; native wire passed **42/0**. All selected
compile/format/audit, namespace/native-sandbox and 37 inventory regressions/checks
passed. Commands, source/tool hashes, exits and complete logs:
`/tmp/samgita-repair-final-packages-v5-20261024/`.

This supersedes the earlier omitted-tool prerequisite failure for this runner's
scope. It precedes the new managed-policy tests; their focused **13/0** repeats
and the single corrected Credo draft failure are recorded in
[managed qualification](managed-requirements-qualification.md). New executable
test/helper source still requires its own combined/hosted qualification. The
unchanged populated-database GitHub failure, A11, completeness and external/OS
gates remain unmet. No publication, tag or deployment occurred.

## Hosted checkpoint at 0cb70cc

Exact pushed source `0cb70cc3b9d747fe9e9dd76cddcef0331a505767` completed both
normal workflows. [Foundation 40058689978](https://github.com/gsmlg-opt/Samgita/actions/runs/40058689978)
passed both populated-database seeds (**224 core/0/one excluded + 125 web/0/two
excluded**, each), dedicated restart/rollback **1/0**, neutral core **32/0**,
both outside consumers **1/0** each, WebSocket **42/0**, native wire **42/0**,
strict checks/audits, assets and local production assembly. This hosted database
does not supersede the unchanged local GitHub first-page failure below.

[Conformance 40058706792](https://github.com/gsmlg-opt/Samgita/actions/runs/40058706792)
finished **failed overall**. Its selected actual-binary/platform job passed
native wire **42/0**, both required default-driver partitions (**256/0 +
239/0 = 495/0**), outside consumer **1/0**, and native platform **53 core +
5 web / zero failures**. The independent isolated-native job passed all
**30 explicit profiles, 205/0**, including private Secret Service persistence.
Both Mix partitions retain the original eight-minute step deadline and cover
the complete sorted default test-file set, with no excluded native scenario.

The separate required evidence gate failed unchanged: **485 requirements:
462 implemented / 12 missing / 11 blocked**; **6,621 contracts: 1,931 implemented /
4,690 missing**, **zero verified**. These selected real-binary successes do not
close the full compatibility goal, A11, source-unreachable legacy paths or
external/OS acceptance. Terminal metadata, complete logs and per-step counts:
`/tmp/samgita-hosted-0cb70cc-20261024/`. No release, tag, publication, deployment
or live credential change occurred. Later executable additions require their
own combined-source and hosted checks.

## Hosted checkpoint at 570a6f0

Exact pushed source `570a6f04639c730b94a10c6ea735c912c5d06fc9` finished both
normal workflows. [Foundation 40056135170](https://github.com/gsmlg-opt/Samgita/actions/runs/40056135170)
passed both populated-database seeds (**224 core / zero failures / one excluded**,
**125 web / zero failures / two excluded**, each), dedicated restart/rollback
**1/0**, neutral core **32/0**, both outside consumers **1/0** each, WebSocket
**42/0**, native wire **42/0**, static checks, strict audits, assets and local
production assembly. Its isolated hosted database does not supersede the
retained local first-page pagination failure below.

[Conformance 40056232904](https://github.com/gsmlg-opt/Samgita/actions/runs/40056232904)
finished **failed overall**. The selected actual-binary/platform job passed
native wire **42/0**, default driver **475/0**, outside consumer **1/0**, and
platform **53 core + 5 web / zero failures**. Its independent isolated-native job
passed all **30 explicit profiles, 205/0**. The separate required evidence gate
failed unchanged: **485 requirements: 462 implemented / 12 missing / 11 blocked**,
**6,621 contracts: 1,741 implemented / 4,880 missing**, **zero verified**.
The later envelope-only indexing in `fdfbe68` is not included in these hosted
counts. Passing selected native jobs cannot satisfy completeness or A11.

Terminal workflow metadata, full logs and per-step counts are retained in
`/tmp/samgita-hosted-570a6f0-20261024/`. Local, tracking and live remote refs
were checked equal at this source before the next documentation commit. There
was no tag, package publication, deployment or live credential change. Later
executable additions still require final combined-source and hosted checks.

## Hosted checkpoint at fb72c55

Exact pushed source `fb72c5571a8bb56e4c97c8b8170f17349d51c851` completed both
normal workflows. [Foundation 40053085514](https://github.com/gsmlg-opt/Samgita/actions/runs/40053085514)
passed its retained aggregate checks, both populated-database seeds (**224 core
and 125 web**, zero failures each), restart/rollback, independent packages and
consumers, audits, static checks, assets and local release assembly. Its hosted
database is not the long-lived local recovery database; this does not supersede
the local pagination failure below.

[Conformance 40053092658](https://github.com/gsmlg-opt/Samgita/actions/runs/40053092658)
finished **failed overall**. Its selected actual-binary/platform job passed
native wire **42/0**, default driver **457/0**, outside consumer **1/0**, and
platform **53 core + 5 web / zero failures**. The separate isolated-native job
passed all **30 explicitly selected profiles, 205 tests / zero failures**,
including real private namespaces, native sandbox write/denial and private
Secret Service prerequisites. Synthetic model/service dependencies do not
qualify actual external provider accounts or other OS profiles.

The independent full-compatibility evidence job failed its unchanged required
gate: **485 requirements (462 implemented, 12 missing, 11 blocked)** and
**6,621 contracts (1,678 implemented, 4,943 missing)**, with **zero verified**.
The gate remains required and no expected-failure or continue-on-error wrapper
was added. The three job outcomes are separate; neither passing job establishes
full compatibility, A11 or production readiness. Downloaded terminal metadata,
complete logs and per-step test counts are retained in
`/tmp/samgita-hosted-fb72c55-20261024/`. Local, tracking and live remote refs
converged at this source. No tag, publication, deployment or live credential
change occurred. Subsequent executable changes require their own qualification.

## Later package checkpoint and environment correction

The frozen v4 package runner used executable hashes from `570a6f0` (the later
`fdfbe68` edits only documentation/manifest). Inventory regressions **37/0**,
consistency, private-namespace/native-sandbox prerequisites, driver compilation
and formatting passed. Default driver seeds `728846` and `987654` each passed
**475/0**, 409.7/410.0s. All 30 profiles at seed `501432` ended **205 tests /
one failure**, 451.3s: the runner omitted the private keyring tool environment,
so `native_gateway_success_profile.exs:27` failed its explicit
`GNOME_KEYRING_DAEMON executable required` prerequisite before fixture startup.
The runner stopped at that failure; remaining commands did not run. Its source
hash guard was checked unchanged before integrating new test units.

The environment correction supplies existing absolute Nix tool paths through
GNOME_KEYRING_DAEMON, DBUS_DAEMON and GDBUS. No test, timeout, assertion or
production source changed for this correction. The explicit native Gateway
profile then passed **1/0**, 6.0s (6.54s command wall time), including private
OS Secret Service, cold native persistence and primary logout. This focused
pass does not replace the still-required final complete profile combination.
The original failed run remains in
`/tmp/samgita-repair-final-packages-v4-20261024/`; corrected tool values,
commands and logs are in `/tmp/samgita-native-followup-units-20261024/`.
Twenty additional native cases subsequently pass their five-module **25/0**
block twice; the linked per-unit records retain their failed drafts and scope.
The final aggregate/hosted gates must use that delivered source.

## Earlier frozen independent-package matrix

The complete serial package matrix passed with **23 commands / zero failures**.
Its 1,370 executable/configuration/workflow source hashes were frozen at
`a42bd98856b90b2e0538a330b86673026cc9410b`; `fb72c55` and the documentation
updates differ only outside that source set. The end-of-run hash guard passed.

| Check | Actual result |
| --- | --- |
| Inventory regressions/consistency; namespace/native sandbox prerequisites | Passed |
| Driver compile/format, default seeds `728846`, `987654` | 457/0 each, 369.6/366.0s |
| All 30 explicit native profiles together, seeds `501432`, `987654` | 205/0 each, 432.5/452.3s |
| Native outside consumer | 1/0; no Repo/Phoenix/umbrella dependency |
| Neutral core suite and two outside consumers | 32/0, 1/0, 1/0 |
| Neutral WebSocket compile/format and seeds `455834`, `501432`, `987654` | 42/0 each; original bounds/assertions/deadlines retained |
| Native wire compile/format/tests | 42/0 |
| Driver, WebSocket and native wire Hex audits | Passed; root audit passed in the platform matrix |

The command list, source hashes, every exit and complete logs are in
`/tmp/samgita-repair-final-packages-v3-20261024/`; runner:
`/tmp/samgita-repair-final-packages-v3-20261024.py`. It uses verified Devenv,
`MIX_ENV=test`, the hash-checked native binary and explicit private D-Bus/GNOME
tool paths, with no competing local Mix/native validation. This completes this
package checkpoint only. The local populated umbrella failure, A11, unavailable
native paths, external/OS profiles and full evidence gate remain incomplete.
New native test units follow this frozen matrix and need their own results.

## Latest populated-database aggregate checkpoint at c5c0cba

The serial v4 platform runner froze executable/configuration/workflow source
at `c5c0cba` and passed its end-of-run hash guard. On the same retained
`samgita_redesign_recovery_repair_test`, seed `501432` passed **224 core/0/one
excluded + 125 web/0/two excluded**. Seed `987654` passed **224 core/0/one
excluded**, but reported **125 web/one failure/two excluded**: the unchanged
GitHub first-page assumption at `github_controller_test.exs:56` described below.
The generated record UUID happens to fit one first page and miss the other;
one passing run does not establish a pagination repair. No records were deleted,
guard bypassed, mappings changed or assertions skipped. The aggregate is failed.

Native runtime/API/races passed **53 core + 5 web / zero failures**. Both
consecutive recovery/restart seeds passed **4 core + 1 web / zero failures**.
Compilation, formatting, strict Credo, legacy checks, forced Dialyzer, strict
root audit, frozen web dependencies, assets and local production assembly all
passed. Exact commands, source hashes, every exit and logs:
`/tmp/samgita-repair-final-platform-v4-20261024/`; unpublished local assembly:
`/tmp/samgita-repair-final-prod-v4-20261024/rel/samgita`. It was not started.

The subsequent CI-only change uses official Mix file partitions for the full
default driver suite. Both partitions remain required, seed `501432`, each
with the original eight-minute step limit and original native test deadlines.
Hosted `570a6f0` already spent 463.9s on 475 tests before these 20 additions;
sharding bounds growing work without excluding scenarios or increasing a
failure timeout. Local full-suite repeats and both hosted partitions are
separate final checks. No full evidence gate, A11 or release criterion changes.

## Earlier populated-database aggregate checkpoint

At `53ec89b95f6577e8cf328a22f1f77d9548384042`, the final-source platform
runner retained `samgita_redesign_recovery_repair_test` without reset, row
deletion, changed mappings or relaxed activation. Compilation, full format and
strict Credo passed. Both full umbrella seeds, `501432` and `987654`, reported
**224 core tests / zero failures / one excluded** and **125 web tests / one
failure / two excluded**. Dedicated e2e cases are run separately below.

The failure is the unchanged GitHub connection-management test at
`apps/samgita_web/test/samgita_web/controllers/github_controller_test.exs:56`:
it requires a just-created connection to appear in the default first page.
Retained independent-transaction concurrency fixtures now exceed that page.
`Samgita.GitHub.connections/2` orders UUIDs and applies the requested bounded
limit/offset, so the new UUID need not occur there. Both runs show retained
concurrency connections in the response. This is a separate pre-existing
pagination assumption, not a recurrence of the repaired activation guard or a
driver failure. No GitHub source/test was changed, page enlarged, fixture deleted,
aggregate assertion skipped or gate converted to success. The aggregate remains
**failed** and prevents a passing-release claim.

Independent checks continued with every exit recorded, while retaining the
failure. Native runtime/API/concurrency checks passed **53 core + 5 web tests**,
including the two differently named ordinary Agents and execution/review/
acceptance separation. Consecutive recovery/restart seeds each passed
**4 core + 1 web tests** on the same populated database. Legacy scanner tests
and exact runtime scan, forced Dialyzer, strict Hex audit, frozen web dependency
installation, assets, production dependencies/assets and local production
assembly all passed. No assembled service was started, tagged or published.

Commands are the repository checks plus:

```sh
mix test --seed 501432
mix test --seed 987654
mix test apps/samgita/test/samgita/runtime_registration_test.exs \
  apps/samgita/test/samgita/codex_runtime_test.exs \
  apps/samgita/test/samgita/codex_runtime_notification_test.exs \
  apps/samgita/test/samgita/codex_runtime_tool_retirement_test.exs \
  apps/samgita/test/samgita/codex_runtime_race_test.exs \
  apps/samgita/test/samgita/codex_runtime_operator_authority_test.exs \
  apps/samgita_web/test/samgita_web/controllers/codex_runtime_controller_test.exs \
  apps/samgita_web/test/samgita_web/integration/codex_runtime_test.exs \
  --include e2e --include real_codex --seed 501432
mix test apps/samgita/test/samgita/recovery_activation_test.exs \
  apps/samgita_web/test/samgita_web/integration/restart_reconcile_test.exs \
  --include e2e --seed 501432
# Repeat the recovery command with --seed 987654.
```

Verified Devenv supplies Elixir/OTP; `MIX_ENV=test`,
`PGHOST=/tmp/samgita-p3-pg/socket`, `POSTGRES_PORT=55443`, `POSTGRES_USER=gao`,
the named database override and hash-pinned `CODEX_BINARY` select only isolated
synthetic resources. Source hashes, commands, exits and logs are in
`/tmp/samgita-repair-final-platform-v3-20261024/` and
`/tmp/samgita-repair-final-platform-v3-remaining-20261024/`. Both source guards
passed. Production assembly uses a separate
`/tmp/samgita-repair-final-prod-v3-20261024` build path and synthetic configuration.
Later source additions require corresponding final validation; this is a
checkpoint, not completion of the full compatibility goal or A11.

The later [A11 ingress boundary assessment](a11-ingress-boundary.md) inventories
browser, API, Agent, GitHub and proof/ticket paths. A browser envelope alone cannot
close the accepted raw-metadata contract; supported pre-emission instrumentation
or a reviewed migration of every secret-bearing ingress remains a prerequisite.

The [locked native artifact acquisition repair](native-artifact-acquisition.md)
reproduces the hosted MDEx download failure, preserves both checksum checks, and
loads the unchanged native module in a cold outside consumer. Hosted
[40039092156](https://github.com/gsmlg-opt/Samgita/actions/runs/40039092156)
at `403607ca405702475c86e01840fe090bd23f4f53` then passed the selected native/
consumer/platform job and all 15 explicit native profiles. Wire **42/0**, driver
**418/0**, platform **42/0 + 5/0**, native acquisition and the outside consumer
all passed. The overall workflow failed its independent required completeness
gate. This closes that repair checkpoint only; later source additions require
their own final matrix. Foundation at the same commit and at `f0385f2` also
passed. A11, complete evidence and external profiles remain incomplete.

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

## Hosted continuation and cached dependency analysis

At `2565d96403573ca0ba0d20961ef8ca3eaaec20ff`, pinned conformance
[39990785776](https://github.com/gsmlg-opt/Samgita/actions/runs/39990785776)
passed its selected actual-binary/platform job: independent schema, the full
208-case driver suite, outside consumer and fenced platform/API scenarios.
The separate completeness job failed its unsatisfied evidence requirement;
the overall workflow remains failed. This supersedes the earlier selected-job
upgrade-ordering failure, while preserving that failure's record below.

Foundation [39990749699](https://github.com/gsmlg-opt/Samgita/actions/runs/39990749699)
passed compilation, repeated populated tests, restart, independent packages,
assets and the legacy scan, then failed Dialyzer with
`call_to_missing: SamgitaCodexDriver.Session.notify_native/3`. Audit and production
assembly steps consequently did not run. Compilation logs explicitly show the
driver recompiling, so this is not evidence that the function is absent in source.

The restored dependency PLT predates the new path-dependency export. Retained
Dialyxir `Mix.Tasks.Dialyzer.dependency_hash/0` hashes only lockfile contents and
the application list; `check_plt/1` skips BEAM checking when that hash matches.
Neither input changes for a new function in the reusable driver. The supported
`--force-check` option exists specifically for local dependencies. CI now uses
`mix dialyzer --force-check`, retaining the cache and every warning/error gate.
No dependency source is patched and no warning is ignored. Local verification:
`devenv shell --no-tui -- env MIX_ENV=test mix dialyzer --force-check` checked
**2,165 modules**, reported **zero errors/skips**, and exited zero. Log:
`/tmp/samgita-ci-plt-force-check.log`. At workflow repair commit
`81409cae03c95a80a6966376533f349a70c3dc2e`, hosted foundation
[39992212088](https://github.com/gsmlg-opt/Samgita/actions/runs/39992212088)
passed the complete job, including forced dependency analysis, audits and
production assembly. This establishes the scoped hosted PLT repair; later
source still requires its own final checks.

## Native profile test static gate

Foundation [39993653513](https://github.com/gsmlg-opt/Samgita/actions/runs/39993653513)
at `5fdc6592725dff138f491493cb7a8b475e6d7186` stopped at strict Credo before
database/test steps. Its only finding was an escaped TOML string in
`native_project_profiles_test.exs:23`. The test now uses an interpolated sigil
with the same bytes and assertions. No Credo rule or test gate changed.
Local strict Credo then found a nested assertion helper in the pending plugin
test; extraction preserves every content/count assertion. The integrated check
passed **286 files with no issues**, followed by **22 actual-binary profile,
plugin, filesystem and environment tests**, seed `501432`. Log:
`/tmp/samgita-operation-profiles-static-check.log`. Final-source hosted results
are recorded separately.

## Continuing gates

At pushed checkpoint `a8852e9feff8d8a2f3524b10f1f79b46d2347add`, foundation
[40008539588](https://github.com/gsmlg-opt/Samgita/actions/runs/40008539588)
stopped at strict Credo: the combined output-contract correction had one nested
function in `Schema.Output.contract/2` at depth three. A private helper extraction
preserves both correction selectors and the exact branch-renaming operation;
no check or exclusion changes. Its focused final checks and subsequent hosted
result are recorded separately. The independent-lock audit workflow additions
retain failure behavior for every advisory; root-only audit cannot certify the
optional package's retained lockfile.

Local follow-up `376f6b6` passed strict Credo on **303 files**, both **42-case**
native-schema repeats and both **23-case** catalog/fuzzy/history repeats, followed
by populated aggregate/platform/recovery tests, forced Dialyzer, audit, assets
and local production assembly. Exact scope and limits are in
[integrated qualification](qualification.md#integrated-source-after-native-catalog-and-file-search).
This confirms the local static repair, not a final hosted or full-compatibility
success claim.

The unexplained populated-suite listener `:eaddrinuse` is a distinct unresolved
qualification concern, not the original repaired neutral replay race or database
guard. Later root/recovery repeats pass with the original assertions and no
runtime listener change. [Failure-time socket diagnostics](fake-listener-recovery.md)
retain the original failure and bounded non-reproduction/control experiments.

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

The pinned inventory check and its 17 Python regressions passed after these
repairs and the controlled compaction follow-up. Counts are generated from the pin,
not inferred from selected passing journeys. Following selected native Project
implementation evidence at that historical checkpoint was **0 verified /
17 implemented / 464 missing / 4 blocked requirements**. The regenerated current
inventory now records **0 verified / 137 implemented / 343 missing / 5 blocked requirements;
0 verified / 3 implemented / 6,618 missing contracts**. The scoped native
method/notification implementation status is distinct from full qualification.
See [native Project evidence](native-project-qualification.md). Legacy approvals retain their schemas and
[exact upstream reachability evidence](legacy-approval-qualification.md); no
scripted peer is counted as enabled real-binary legacy success. Required external
account/backend/OS profiles remain incomplete. No release/tag, package
publication, deployment, production migration or sibling-service change occurs.

## Output-notice hosted prerequisite investigation

At `085c4cc8d4af95f5016649c36689bd6a09e8ade5`, foundation
[40028893237](https://github.com/gsmlg-opt/Samgita/actions/runs/40028893237)
passed. Conformance
[40028914024](https://github.com/gsmlg-opt/Samgita/actions/runs/40028914024)
passed all thirteen explicit isolated profiles, but its default driver job failed
**four of 381 cases**, seed `897445`. All four output-notice cases failed during
the private namespace fixture's startup, before native protocol assertions.
The outside consumer and platform stages were skipped; completeness also failed.
The failure log is `/tmp/samgita-085c4cc-hosted-driver-failure.log`.

That job used Ubuntu 24.04 image `20261012.334.1`; the successful explicit
namespace profiles used Ubuntu 22.04 image `20261012.322.1`. The output-notice
test unconditionally requires `unshare --user --map-root-user --net`, but was
added to default test discovery. Its controller's stderr is intentionally
discarded and its readiness wait does not report child exit. This establishes
a prerequisite/profile mismatch, not the exact OS denial. No timeout increase,
test skip or successful hosted repair is claimed at this diagnostic checkpoint.

The selected job now runs a required fixed-command namespace preflight before
the driver. It compares user/network namespace identity, requires mapped root,
loopback only and no IPv4/IPv6 default route, and exposes `unshare`/`ip` stderr
without printing environment or credentials. It changes no host permission and
starts no listener or Codex process. Local `python3 -B
scripts/codex/check_namespace_prerequisites.py` exited zero with all those
properties true. The next hosted run must establish the actual prerequisite
outcome before selecting a repair. Full compatibility and A11 remain incomplete.

The diagnostic selected job at `fe5222d` in
[40030194617](https://github.com/gsmlg-opt/Samgita/actions/runs/40030194617/job/120676271523)
then reproduced the concrete prerequisite failure:
`unshare: write failed /proc/self/uid_map: Operation not permitted`. Its native
wire package passed 42 tests and audit; the preflight exited one before driver,
consumer or platform execution. Job logs are saved in
`/tmp/samgita-fe5222d-hosted-namespace-failure.log`. The initial attempt to obtain
logs through `gh run view` was unavailable while the workflow was running;
the completed job's API log supplies the actual diagnostic.

The selected job is now explicitly pinned to Ubuntu 22.04, matching the existing
successful namespace profile, and both jobs require the same preflight. The four
output-notice cases remain in default discovery with every assertion and original
deadline unchanged. No test moves/skips, host-network fallback, `sudo`, AppArmor
change or host permission relaxation is introduced. This qualifies the declared
namespace-capable environment; it does not claim support for the denied hosted
Ubuntu 24.04 profile or identify which host security mechanism denied `uid_map`.
Hosted validation at `38e47451ebbd7020977a8104d74bf1d71cd0fc7b` in
[40030585186](https://github.com/gsmlg-opt/Samgita/actions/runs/40030585186)
passed the namespace preflight in both native jobs. All thirteen explicit native
profiles passed. The selected default driver ran **381 tests / one failure**,
seed `853090`, in 239.1s: its streamed patch case received an unexpected native
approval/tool request. The other three output-notice cases passed. Thus the
namespace startup failure is resolved for this declared hosted profile, while
patch execution still has a distinct unresolved environment/authorization
boundary. No native approval is granted by this fixture. Outside-consumer and
platform stages were skipped; the completeness gate also failed. The job log is
`/tmp/samgita-38e4745-hosted-driver-failure.log`.

The failing assertion now reports only the unexpected native method and the
synthetic fixture's reason/thread/turn/item/grant-root context. It still rejects
every server request, with no response, retry, sandbox change or deadline change.
The next hosted run must expose the actual native reason before choosing a
behavioral repair; source inspection alone does not establish it. Foundation
[40031002577](https://github.com/gsmlg-opt/Samgita/actions/runs/40031002577)
passed at `b217123e74c46f5d5b4cc4b5978d3b6cc8febaa7`, independently of the
failed conformance gate. A11, external profiles and full compatibility remain
incomplete.
