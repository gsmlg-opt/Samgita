# Repair evidence and continuing compatibility work

This record executes `samgita-codex-repair-followup.txt` on the existing `main`,
starting from `3c54d748871313bd69858ff05d0fd2c606019e6a`. It supplements the
[compatibility ledger](implementation-plan.md) and [qualification](qualification.md).
Local checks, hosted checks, full compatibility and confidentiality acceptance
remain separate gates. No production data, credentials or services are changed.

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
