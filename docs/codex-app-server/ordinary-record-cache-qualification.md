# Ordinary installed cache and recorded import metadata

This unit follows `fa0862ef6c5afbc248ce943d9926631211ad8798` on existing
`main`. It continues the complete client/driver goal against stock Codex
`rust-v0.163.0`, source commit `83086188ae0614bd882818ff1aa23f3194962012`,
executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The runtime profile is Linux x86_64 musl, explicitly owned stdio sessions and
`experimentalApi:true`. YOLO is fixed launch setup. No security, permission,
credential, authentication,
authorization, approval or sandbox behavior is tested. Retained tests and gates
stay intact; audits, broad mixed suites and hosted workflows remain unrun under
the user's restriction. No production implementation, dependency, migration,
shared cleanup helper or immutable binary changes.

## Installed metadata with an explicit background-operation boundary

`native_ordinary_installed_null_test.exs` uses a new independently bounded local
data fixture. It starts with remote plugin discovery disabled, enables only its
fixture fragment after initialization, then explicitly calls `plugin/reconcile`.
That ACK follows native filesystem materialization and cache publication. The
test requires original native-created manifest, marker, skill and remote identity
files before querying installed metadata. No test authors those cache files.

The subsequent `plugin/installed` read both returns that committed snapshot and
initiates a separate refresh. The fixture explicitly observes and holds this
second HTTP request without returning status, headers or body. The native reply
must contain the prescribed marketplace/plugin identities and a **present null**
path. Original captured request/reply bytes, string/integer correlation and the
exact standalone null schema node are checked. Neither a missing property nor a
locally rewritten reply satisfies this oracle.

The actual business-request order is full installed GET1, bundle GET1, installed
GET2. Only GET1 and bundle1 receive successful responses. The three known opaque
startup routes are exhaustively accounted for, at most once each; they do not
gain authentication or policy evidence. All other requests and extra refreshes
fail the fixture. Six correlated native request/reply pairs, one initialized
notification and two empty loaded-thread inventories occur, without a thread,
turn, inference or tool call.

Owned native shutdown must consume the real helper ACK and reap native/helper
processes before the fixture's held handler is released. It then closes that
handler **without a response** and confirms its own shutdown. This deliberately
cancels an accounted background operation; it does not claim second-sync success,
external consistency, restart durability or invisible side effects. Cache files
remain unchanged after the target read and shutdown. Existing remote lifecycle
and reconciliation fixtures, their two-refresh profiles, every assertion and
all cleanup deadlines stay unchanged.

The source ordering is `plugins/reconcile.rs:32–109` awaiting manager reconciliation;
`core-plugins/src/manager.rs:1681–1787` committing its snapshot and dropping its
lexical sync permit before ACK; `plugins.rs:853` starting the later refresh;
manager1381–1396 preserving prior cached rows during that refresh; and
`plugins.rs:2212–2228` producing `path:None`. Nine relied-on source files match
the pinned archive in
`/tmp/samgita-ordinary-installed-null-profile-20261028-report.md`, SHA256
`40d2003dd198d9b2d65627790e62a5fab53da52c4e10efa91a85405fc8cf1d8d`.
The dedicated fixture SHA256 is
`420480edbac94f69dce752a2bf191fbf2d403971c8b728b1b11d152ca027ecb2`.

## All outer import-report categories with genuine cold readback

The existing `native_import_record_history_test.exs` gains one case using its
unchanged capture, setup, no-effect and owned-cleanup helpers. Its earlier case
already qualifies selected categories and captured cold persistence; this unit
adds all ten outer `itemType` labels in one native report:
`AGENTS_MD`, `CONFIG`, `SKILLS`, `PLUGINS`, `MCP_SERVER_CONFIG`, `SUBAGENTS`,
`HOOKS`, `COMMANDS`, `MEMORY`, `SESSIONS`.

These are inert categories, with no settings bodies, hooks, plugin or MCP
definitions. The public record-only operation supplies two descriptive successes
and one externally reported failure, under deliberately different outer labels.
The native UUID and completion timestamp must be genuine; the timestamp lies
within the actual record-call window. An independently prescribed whole-result
oracle requires exact inner types, order, nulls, source/target strings and title.
A distinct native process's first history read returns the identical record.

Pinned processor408–445 dispatches report recording without the import executor;
processor670–715 deliberately flattens inner outcomes and discards outer labels.
Thus accepting all outer categories **does not preserve those categories as
durable provenance** and does not execute an import. Public warm/cold reads
establish the persisted inner representation. No test opens or writes SQLite.

The unchanged bounded capture records original JSONL payload bytes before
Session decoding. The new request is checked against the exact complete
`ClientRequest` schema and its physical `itemType` reference/ten-value enum.
Fourteen outgoing envelopes are prescribed across two owned processes: twelve
correlated requests/replies and two initialized notifications. No import/detect,
configuration write, thread creation, turn, hook, plugin or MCP execution occurs.
Empty inference journal/workspace/thread inventories, absent reported-path tree,
unchanged inputs and confirmed native/provider teardown remain required.

Five causal source files match the immutable archive in
`/tmp/samgita-ordinary-import-group-20261028-handoff.md`, SHA256
`3c8e116cad67c439de5ff3e955798e6bd172c083b44a56f998ec670e565fe03a`.
They cover protocol types, public dispatch, record/read processing and native
state persistence. The source-only draft is separate from runtime acceptance.
No actual import family, policy, permission or external-provider behavior gains
evidence from this metadata recording.

## Physical owners and focused functional evidence

Exactly two previously missing physical owners gain scoped `implemented` evidence:

| Owner | Exact schema pointer | Canonical node SHA256 |
| --- | --- | --- |
| 160 | `ClientRequest.json#/definitions/ExternalAgentConfigImportHistoryRecordTypeResultParams/properties/itemType` | `5faed15b28b715034e7f4f5d868b2b51ec2339ea0c1dbc47c883a23ba989ecd5` |
| 4572 | `v2/PluginInstalledResponse.json#/definitions/PluginMarketplaceEntry/properties/path/anyOf/1` | `b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb` |

IDs, pointers and hashes stay stable. No alias, adjacent policy/capability,
whole method family, background-sync completion or globally verified credit
follows. Requirements remain **462 implemented /12 missing /11 blocked**;
contracts become **5,730 implemented /755 missing /136 blocked**, zero globally
verified in either ledger.

The new installed case plus unchanged reconciliation and remote lifecycle cases
pass **3/0 at both501432 and987654**, then strict Credo, on their first run.
Evidence: `/tmp/samgita-ordinary-installed-null-focused-20261028`.
Results JSON SHA256:
`7e15bcd24a56443411640356e30d37eb85a3752b4502ad607d65888388ba9f2d`;
source JSON SHA256:
`e9a7a2614be44392b964de2a18d37de499a95bee57989f75e312cc4643d96107`.

The final owning block adds the full two-case import file: **5/0 at both fixed
seeds**,9.020s/9.222s including command startup, followed by strict Credo.
Scoped format and compile pass; all1,760 guarded sources stay identical.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-record-cache-focused-20261028.py
```

Results JSON SHA256:
`86e56880b6256c124233bb22ed0657ec7be5daa0b6330bef49757303fb86e2ae`;
source JSON SHA256:
`1f72a6c84a5832008571b9700f5a041be40b2714e19f288d933d9c2d27c27561`.
These focused results precede manifest/runner integration.

## Final combined-source functional qualification

The original main-block argv, every prior164 case and its320-second bound stay
intact. The added case shares that existing import file, so its expected count
becomes165. The independent installed-null case makes the extension count12,
with its existing120-second bound. No test, assertion or error is removed,
skipped or retried to obtain success. All **17 reviewed functional steps pass**
against **1,760 identical guarded sources**:

| Check | Actual result |
| --- | --- |
| Selected neutral overflow/replay | 16/0,13 excluded at each of455834,501432,987654 |
| Main native block | 165/0 at501432 and987654;283.759s and284.213s |
| Separate native extension block | 12/0 at both seeds;20.647s and20.696s |
| Owned cleanup phases | 4/0, original ACK/exit/deadline requirements intact |
| Outside-umbrella consumer | 1/0 against actual pinned Codex, no Repo/Phoenix |
| Other checks | Driver format/compile, inventory consistency, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-record-cache-combined-20261028
```

Results JSON SHA256:
`e65b03ed396a62a5e0e264105454baaea0770140d46063c90831d7744295a1d7`;
source JSON SHA256:
`5a37fa0465c22199c4743c402ee55c3dcbc1701d7f5739b1fe4c194811d78214`.
The frozen source fingerprint is
`c8026edb51d2882ba418ba347f49b1ac99591ef021232af75cc1c99efcdbd088`.
Exact argv, individual command results and log hashes remain in the evidence
directory. Thirteen WebSocket tests are unselected, with retained assertions
unchanged. No prohibited test, audit, broad mixed suite or hosted workflow runs.
Full compatibility and release acceptance remain separate incomplete gates.

## Local production assembly

A new plain source copy, not a Git worktree, contains2,304 explicitly hashed
inputs. It passes all five ordinary build steps: production dependency resolution,
compile with warnings as errors, frozen Bun web install, minified assets/digest,
and `mix release --overwrite`. Bun1.3.13 and Tailwind4.3.1 are verified before
execution. Copied inputs remain exact apart from generated static output; all
1,760 guarded root sources also remain identical. No database or release starts.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-record-cache-local-assembly-20261028.py
```

The local artifact is
`/tmp/samgita-ordinary-record-cache-local-assembly-20261028/source/_build/prod/samgita-0.1.0.tar.gz`,
20,083,133 bytes, SHA256
`ed79ae51eac66b50e46e560395da4deb554dec4d7409d18fe531330d4b00a190`.
Results JSON SHA256:
`1b89bc66c7aa051f2891459fbc89c6cd645675cfbbb2de39b5a36bebbb3c5c93`;
source JSON SHA256:
`9688769f2fe045597027492621633ca57e459b07a095960adb791768154e8ec3`;
copied-input manifest SHA256:
`4be21c4f166c0901f0215cae7560353cd22c8603ff2f2a1c1543d5446162aab2`.
This proves local assembly only. The repository has no enabled normal publication
workflow for this artifact; CD stays disabled. Required prohibited/hosted and
complete-compatibility gates remain incomplete. Nothing is tagged, published,
released, started or deployed.

## Continuing boundaries

Continue the remaining source-supported ordinary functional work and physical
owner review. The next source-feasible candidate is inert System layer source/
path metadata, with an absent-default-system-file environment prerequisite;
it remains unrun and belongs to a following unit.

The bounded review of remaining Installed/Search/Read plugin fields leaves29
owners unrun:26 policy/access shapes and3 workspace eligibility reason shapes.
Some have real local producers, and remote reasons can be forwarded from backend
data. They are excluded by the current verification scope, not declared
upstream-impossible. Their schema states and evidence counts do not change.

A separate34-owner response review leaves17 prohibited fields,11 without an
ordinary producer established in the reviewed paths,4 requiring an alternate
verified native artifact/runtime,1 existing-Review evidence-binding gap and1
unresolved Shutdown trigger. A genuine Shutdown producer exists; ordinary close
returns the prior snapshot before removing the child, so it does not yet provide
the required deterministic selective-history observation. No mirror assertion,
manufactured record or race-selected success promotes any of these owners.
The archive-matched source/node closure and immutable upstream links are in
`/tmp/samgita-ordinary-response-remaining-20261028-report.md`, SHA256
`adab996021ce5144cec3d66c88aa95599a1d72baca954ddd33108afc1c14d4b9`.
This is a bounded review, not a claim that all remaining ordinary work is complete.

A11's supported pre-emission prerequisite, source-proven absent legacy emitters,
real external/backend/other-OS success, prohibited and broad/hosted checks, full
compatibility and release remain incomplete. Successful repeats do not resolve
the historical intermittent cleanup cause. Existing dependency locks, database
fail-closed guards, historical data, replay and production cleanup remain intact.
Nothing is tagged, published, released, deployed or run against a live service.
